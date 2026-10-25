#!/usr/bin/env python3
"""Fake Windows Terminal: run a tmux client in a pty that reports 0x0 pixels
(like WSL's ConPTY), answer pixel/DA queries the way Windows Terminal does,
send img2sixel into the pane and check what reaches the "terminal".

Exit code 0 if the result matches --expect.
"""
import argparse, fcntl, os, pty, re, select, struct, subprocess, termios, time

ap = argparse.ArgumentParser()
ap.add_argument('--tmux', default='tmux')
ap.add_argument('--img', help='image for img2sixel (default: a generated 75x80 gradient)')
ap.add_argument('--xpix', type=int, default=0, help='cell width in px reported via TIOCSWINSZ (0 = like WSL)')
ap.add_argument('--no-answer', action='store_true', help="don't answer CSI 14t/16t/18t")
ap.add_argument('--conf', default='/dev/null')
ap.add_argument('--log', default='/tmp/fakewt.log')
ap.add_argument('--expect', choices=['sixel', 'placeholder'])
a = ap.parse_args()
if not a.img:   # plain PPM, no PIL needed; libsixel's PNM loader wants one header field per line
    a.img = '/tmp/fakewt-test.ppm'
    with open(a.img, 'wb') as f:
        f.write(b'P6\n75 80\n255\n' +bytes(c for y in range(80) for x in range(75) for c in (x * 3, y * 3, 128)))

# what a real Windows Terminal answered (Cascadia Mono 12pt, 100% scaling)
ROWS, COLS, CW, CH = 30, 120, 10, 20
ANSWERS = {b'14t': b'\x1b[4;%d;%dt' % (ROWS * CH, COLS * CW),
           b'16t': b'\x1b[6;%d;%dt' % (CH, CW),
           b'18t': b'\x1b[8;%d;%dt' % (ROWS, COLS),
           b'c':   b'\x1b[?61;4;6;7;14;21;22;23;24;28;32;42;52c'}   # 4 = sixel
sock = f'/tmp/fakewt-{os.getpid()}'
tmux = lambda *args: subprocess.run([a.tmux, '-S', sock, *args], stderr=subprocess.DEVNULL)

pid, fd = pty.fork()
if pid == 0:
    os.environ['TERM'] = 'xterm-256color'
    os.execvp(a.tmux, [a.tmux, '-S', sock, '-f', a.conf, 'new', '-s', 't'])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', ROWS, COLS, COLS * a.xpix, ROWS * a.xpix * 2))

log, asked, sent, t0 = b'', set(), False, time.time()
while time.time() - t0 < 6:
    if select.select([fd], [], [], 0.1)[0]:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        log += data
        for m in re.finditer(rb'\x1b\[(14t|16t|18t|c)', data):
            asked.add(m.group(1).decode())
            if not a.no_answer or m.group(1) == b'c':
                os.write(fd, ANSWERS[m.group(1)])
    if not sent and time.time() - t0 > 2:
        tmux('send-keys', '-t', 't', f'clear; img2sixel {a.img}', 'Enter')
        sent = True
cells = subprocess.run([a.tmux, '-S', sock, 'display', '-p',
                        '#{client_cell_width}x#{client_cell_height} #{window_cell_width}x#{window_cell_height}'],
                       capture_output=True, text=True).stdout.split()
tmux('kill-server')
open(a.log, 'wb').write(log)

sixels = re.findall(rb'\x1bP[0-9;]*q"[0-9;]*', log)
result = 'sixel' if sixels else 'placeholder' if b'SIXEL IMAGE' in log else 'nothing'
version = subprocess.run([a.tmux, '-V'], capture_output=True, text=True).stdout.strip()
print(f'{version}: xpix={a.xpix} answer={not a.no_answer} queries={sorted(asked)} '
      f'cells(client,window)={cells} -> {result} {sixels[:1]}')
if a.expect:
    ok = result == a.expect
    print('PASS' if ok else f'FAIL (expected {a.expect})')
    raise SystemExit(0 if ok else 1)
