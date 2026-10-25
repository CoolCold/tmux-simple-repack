#!/bin/bash
# Screenshot a Windows window from WSL.
#   tools/shot.sh --list                          visible windows: process, size, MIN if minimized, title
#   tools/shot.sh [--proc NAME] TITLE [OUT.png]   (TITLE may be "") capture the topmost non-minimized window whose title
#                                                 contains TITLE (and whose process is NAME, e.g. WindowsTerminal)
# stdout: the PNG path only; stderr: "OK WxH [process] title". Exit 2 = not found, 3 = only minimized matches.
set -euo pipefail
PS1_WIN=$(wslpath -w "$(dirname "$(readlink -f "$0")")/shot.ps1")

run() {  # powershell.exe from a Windows cwd; retry: WSL 3.0.3 interop sometimes times out (microsoft/WSL#42029)
  local out rc
  for _ in 1 2 3; do
    rc=0; out=$(cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS1_WIN" "$@" 2>&1 | tr -d '\r') || rc=$?
    out=$(grep -v 'UtilAcceptVsock' <<<"$out" || true)
    case $rc in
      0) echo "$out"; return 0 ;;
      2|3) echo "$out (try --list)" >&2; return $rc ;;   # real answers, don't retry
    esac
    sleep 2
  done
  echo "$out" >&2; return 1
}

proc=()
[ "${1:-}" = --proc ] && { proc=(-Process "$2"); shift 2; }
[ $# = 0 ] && set -- -h
case "$1" in
  -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
  --list) run -List ;;
  *) out=$(readlink -f "${2:-shot-$(date +%Y%m%d-%H%M%S).png}")
     title=(); [ -n "$1" ] && title=(-Title "$1")   # empty args don't survive the trip to powershell.exe
     run "${proc[@]}" "${title[@]}" -Out "$(wslpath -w "$out")" >&2 && echo "$out" ;;
esac
