# Testing terminal stuff from WSL against the real Windows Terminal

Notes from debugging sixel in tmux under WSL2. Everything below is driven **from inside WSL**,
including by an agent (Claude Code) with no GUI access of its own.

## 1. WSL ↔ Windows interop basics

- Any `*.exe` on the Windows `PATH` runs directly from WSL (`binfmt_misc` + `WSLInterop`):
  `notepad.exe`, `explorer.exe .`, `powershell.exe`, `wt.exe`, `winget.exe`.
- Run Windows binaries from a Windows directory (`cd /mnt/c && …`). From `\\wsl$\…` paths they
  complain about the working directory.
- Output has CRLF line endings: pipe through `tr -d '\r'`. `wsl.exe -l` prints UTF-16: `tr -d '\0\r'`.
- Convert paths with `wslpath -w /linux/path` (to Windows) and `wslpath -u 'C:\…'` (to Linux).
- Pass PowerShell code as a file (`-File script.ps1`), not via `-Command`, to avoid quoting hell:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w script.ps1)" args…`

## 2. Open a Windows Terminal window that runs something in WSL

```bash
cd /mnt/c && wt.exe -w new new-tab --title mytest --suppressApplicationTitle \
    wsl.exe -d Ubuntu-24.04 -- /path/to/script.sh
```

Gotchas:

- **`wt.exe` treats every `;` as its own command separator, even inside `bash -c '…; …'`.** You get
  extra broken tabs. Put anything non-trivial into a script and run that.
- `\;` (escaped for bash) is the intentional separator, e.g. to split panes:
  `… wsl.exe -- a.sh \; split-pane -V --title mytest wsl.exe -- b.sh`
- `--title` + `--suppressApplicationTitle` make the window findable later. With split panes, the
  window title follows the active pane, so give **every** pane a `--title`.
- `wsl.exe -- cmd` is a non-login shell: snap binaries (`/snap/bin/lxc`) are not on `PATH`. Use full paths.
- Courtesy: a new window pops up on top. Warn whoever is working at the machine.

## 3. Drive the program inside: tmux, not keystrokes

If the thing under test runs in tmux, control it from any other shell; no Windows input injection
or focus is needed:

```bash
tmux send-keys -t sess 'img2sixel pic.png' Enter
tmux split-window -h -t sess
tmux display -p -t sess '#{client_cell_width}x#{client_cell_height} #{window_cell_width}x#{window_cell_height} #{sixel_support}'
tmux list-clients -F '#{client_termname} #{client_termfeatures}'
```

Running tmux inside an LXD container works the same way: `lxc exec CT -- tmux send-keys …`.
GUI apps (Notepad, Telegram, …) need `SendMessage` / `SendInput` via PowerShell instead. That is
a different story.

## 4. Look at the result: screenshot a window

Run it from WSL, from any directory, no setup needed: it does the `cd /mnt/c`, `wslpath` and CRLF
handling from section 1 itself. Usage: `tools/shot.sh [--proc NAME] TITLE [OUT.png]`, with `--proc`
first; `TITLE` is a substring, and `""` matches any title.

```bash
tools/shot.sh --list                                   # 1. find the window (see below)
tools/shot.sh mytest /tmp/shot.png                     # 2. capture by title substring
tools/shot.sh --proc WindowsTerminal "" /tmp/shot.png  #    topmost Windows Terminal window, any title
tools/shot.sh mytest                                   #    no path: ./shot-YYYYmmdd-HHMMSS.png
```

`--list` prints one line per visible window, topmost first: process name, size, `MIN` if minimized
(otherwise `-`), title:

```
WindowsTerminal          1243x672  -   mytest
WindowsTerminal           908x1140 -   Ubuntu-24.04
WindowsTerminal           183x34   MIN user@host: ~
firefox                  1920x1032 -   Some page — Mozilla Firefox
```

The real list is longer: it also has tray and helper windows (`explorer`, `TextInputHost`, small
`320x58`-ish popups). Ignore those. Window titles can be private (open documents, chats), so don't
paste the list into reports or issues.

Picking a window:
- The title match is a case-insensitive substring; `--proc` (exact process name from `--list`)
  narrows it, e.g. to `WindowsTerminal` when browsers or other apps have similar titles.
- If several windows match, the **topmost** one that is not minimized wins (Z-order, as in `--list`).
- Minimized windows are skipped. If only minimized windows match, it fails with exit code 3
  (`MINIMIZED: … restore it first`). Not found gives exit code 2. A minimized window can't be
  captured: Windows would give you just its 183x34 title bar.
- Easiest of all: make the window yourself with a unique `--title` (section 2). Windows Terminal's
  window title is the active tab's title.

Output:
- Stdout is just the PNG path, so `f=$(tools/shot.sh mytest) && xdg-open "$f"` works. An agent can
  `Read` that file to look at it.
- Stderr gets `OK WxH [process] title`. Check that the size looks like a whole window: hundreds of
  pixels each way, up to the screen size (a maximized window is about the screen minus the taskbar).
  Something like `183x34` is a title bar, not a window.
- It captures the window itself, not a screen region (`PrintWindow` with `PW_RENDERFULLCONTENT`),
  so windows covered by other windows work fine.
- Real pixels on HiDPI screens (`SetProcessDPIAware`), without the invisible resize border
  (`DwmGetWindowAttribute(EXTENDED_FRAME_BOUNDS)`).
- Retries up to 3 times: on WSL 3.0.3 `powershell.exe` sometimes fails with
  `UtilAcceptVsock … accept4 failed 110` ([microsoft/WSL#42029](https://github.com/microsoft/WSL/issues/42029)).
- Privacy: it captures whatever is in the window, including the terminal text itself (paths, host
  names, tokens). Transparent/acrylic terminals show your desktop
  through, so check a screenshot before publishing it. Use generated images
  ([`tools/testcard.py`](tools/testcard.py), needs `python3-pil`), not random files from disk.

Under the hood it is [`tools/shot.ps1`](tools/shot.ps1). Calling it directly needs a Windows cwd
and Windows paths:
`cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /abs/path/shot.ps1)" -Title mytest -Out 'C:\tmp\shot.png'`

## 5. Ask the terminal directly

Query Windows Terminal from a plain WSL shell (no tmux in between):

```bash
stty raw -echo; printf '\e[16t'; IFS= read -r -t1 -dt r; stty sane; printf '%q\n' "$r"
```

| query | WT answer | meaning |
|---|---|---|
| `CSI 14 t` | `ESC[4;600;1200t` | text area in px (h;w) |
| `CSI 16 t` | `ESC[6;20;10t` | cell size in px (h;w) |
| `CSI 18 t` | `ESC[8;30;120t` | rows;cols |
| `CSI c` | `ESC[?61;4;6;…c` | DA1, `4` = sixel |
| `ioctl(TIOCGWINSZ)` | `(30, 120, 0, 0)` | **pixels are 0**: the root of the tmux 3.4 problem |

## 6. Test matrix without touching the host

- Throwaway LXD containers for each Ubuntu release: `lxc launch ubuntu:26.04 x`. The image is
  cached, so this takes seconds.
- Run tmux *from the container* in a real WT window:
  `wt.exe … wsl.exe -d Ubuntu-24.04 -- /snap/bin/lxc exec x -- env TERM=xterm-256color tmux new -s t`.
  The chain WT → ConPTY → WSL → `lxc exec` pty → tmux still reports 0 pixels, so this is a faithful test.
- Headless and CI-friendly: [`test/fakewt.py`](test/fakewt.py) emulates WT's answers in a pty.
- Don't run the test inside your own tmux: the outer tmux intercepts sixel and the result means nothing.

## 7. Useful one-liners

```bash
tmux -V; tmux display -p '#{version}'          # client vs *server* version (they can differ!)
python3 -c 'import fcntl,termios,struct;print(struct.unpack("HHHH",fcntl.ioctl(0,termios.TIOCGWINSZ,b"0"*8)))'
img2sixel -w 300 pic.png                        # force width in px
tmux show -s terminal-features
```
