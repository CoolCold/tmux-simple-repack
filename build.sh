#!/bin/bash
# Build the backport in a throwaway LXD container; results land in ./out
#   TARGET=24.04 SRC_SERIES=resolute REV=1 KEEP=1 ./build.sh
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

TARGET=${TARGET:-24.04}
CT=${CT:-tmux-repack-build-$$}
KEEP=${KEEP:-0}   # 1 = keep the container for debugging

timeout 300 lxc launch "ubuntu:${TARGET}" "$CT" >/dev/null
trap '[ "$KEEP" = 1 ] && echo "kept container $CT" || lxc delete -f "$CT"' EXIT
lxc exec "$CT" -- cloud-init status --wait >/dev/null

lxc file push -q backport.sh "$CT/root/"
# changelog maintainer: DEBFULLNAME/DEBEMAIL, defaulting to your git identity
NAME=${DEBFULLNAME:-$(git config user.name || true)}
MAIL=${DEBEMAIL:-$(git config user.email || true)}
lxc exec "$CT" --env DEBFULLNAME="$NAME" --env DEBEMAIL="$MAIL" --env SRC_SERIES="${SRC_SERIES:-resolute}" --env REV="${REV:-1}" -- bash /root/backport.sh

mkdir -p out
for f in $(lxc exec "$CT" -- ls /root/out); do lxc file pull -q "$CT/root/out/$f" out/; done
ls -la out/
