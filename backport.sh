#!/bin/bash
# Runs INSIDE a clean Ubuntu container: fetch tmux source from a newer Ubuntu
# series, adapt it for this series and build source + binary packages into /root/out.
set -euo pipefail

SRC_SERIES=${SRC_SERIES:-resolute}   # Ubuntu 26.04
REV=${REV:-1}                        # bump when re-releasing the same upstream version
OUT=/root/out
export DEBIAN_FRONTEND=noninteractive
. /etc/os-release                    # VERSION_ID, VERSION_CODENAME of the target

apt-get update -qq
apt-get install -y -qq build-essential devscripts equivs ubuntu-dev-tools >/dev/null

mkdir -p /root/work "$OUT" && cd /root/work
pull-lp-source tmux "$SRC_SERIES"
cd "$(find . -maxdepth 1 -type d -name 'tmux-*' | head -1)"
SRC_VER=$(dpkg-parsechangelog -S Version)
NEW_VER="${SRC_VER}~${VERSION_ID}.${REV}"

# 1. ncurses >> 6.5 is only needed for the Debian 6.5 symbol transition; noble has 6.4.
sed -i 's/libncurses-dev (>> 6\.5)/libncurses-dev/' debian/control

# 2. On noble, --as-needed + LTO drops -ljemalloc, silently falling back to glibc malloc.
#    The official package links jemalloc (less memory bloat over time); keep it that way.
sed -i 's/^export DEB_BUILD_MAINT_OPTIONS.*/&\nexport DEB_LDFLAGS_MAINT_APPEND = -Wl,--push-state,--no-as-needed -ljemalloc -Wl,--pop-state/' debian/rules

DEBFULLNAME="${DEBFULLNAME:-tmux-simple-repack}" DEBEMAIL="${DEBEMAIL:-noreply@localhost}" EDITOR=true \
  dch --force-bad-version --force-distribution -v "$NEW_VER" -D "$VERSION_CODENAME" \
  "Backport ${SRC_VER} from ${SRC_SERIES} to ${VERSION_CODENAME}: relax libncurses-dev build-dep, force jemalloc linkage." </dev/null

mk-build-deps -i -r -t "apt-get -y -qq" debian/control >/dev/null
dpkg-buildpackage -us -uc -S -d >/root/out/build-source.log 2>&1
dpkg-buildpackage -us -uc -b    >/root/out/build-binary.log 2>&1

# sanity: sixel compiled in, jemalloc actually linked
grep -q -- '--enable-sixel' /root/out/build-binary.log
objdump -p debian/tmux/usr/bin/tmux | grep -q 'NEEDED.*libjemalloc' || { echo "jemalloc NOT linked" >&2; exit 1; }

cd .. && cp -v ./*"${NEW_VER}"* tmux_*.orig.tar.gz "$OUT"/
echo "built tmux ${NEW_VER}"
