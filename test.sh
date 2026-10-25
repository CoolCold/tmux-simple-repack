#!/bin/bash
# Install ./out/*.deb over the stock tmux in a clean LXD container and check sixel.
#   TARGET=24.04 KEEP=1 ./test.sh
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

TARGET=${TARGET:-24.04}
CT=${CT:-tmux-repack-test-$$}
KEEP=${KEEP:-0}
DEB=$(ls out/tmux_*_amd64.deb | tail -1)
fail=0

timeout 300 lxc launch "ubuntu:${TARGET}" "$CT" >/dev/null
trap '[ "$KEEP" = 1 ] && echo "kept container $CT" || lxc delete -f "$CT"' EXIT
lxc exec "$CT" -- cloud-init status --wait >/dev/null
lxc exec "$CT" -- bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux libsixel-bin >/dev/null'
lxc exec "$CT" -- bash -c "echo 'set -as terminal-features \"xterm*:sixel\"' > /root/sixel.conf"
lxc file push -q test/fakewt.py "$CT/root/"
lxc file push -q "$DEB" "$CT/root/"

t() { echo "--- $*"; lxc exec "$CT" -- python3 /root/fakewt.py "$@" || fail=1; }

# tmux 3.4 does not detect sixel from DA1, so it needs terminal-features in the config
echo "=== stock tmux (control: the bug must reproduce)"
t --conf /root/sixel.conf --expect placeholder
t --conf /root/sixel.conf --xpix 10 --expect sixel

# 3.6 runs with an empty config: sixel must be auto-detected
echo "=== upgrade to $(basename "$DEB")"
lxc exec "$CT" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq /root/$(basename "$DEB") >/dev/null"
lxc exec "$CT" -- bash -c 'dpkg-query -W tmux; dpkg -s tmux | grep ^Depends; ldd /usr/bin/tmux | grep jemalloc' || fail=1
t --expect sixel
t --no-answer --expect placeholder

[ $fail = 0 ] && echo "ALL PASS" || { echo "SOME TESTS FAILED"; exit 1; }
