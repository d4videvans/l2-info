#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Install the backend from this checkout onto the OpenWrt device on which the
# checkout resides. Development helper only: this bypasses the package manager.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/l2-info/files/usr/share"

fail() {
	echo "install-dev-backend: $*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must be run as root on the target OpenWrt device"

for f in \
	"$SRC/rpcd/ucode/l2-info" \
	"$SRC/l2-info/assemble.uc" \
	"$SRC/l2-info/readers/rtnl.uc"
do
	[ -f "$f" ] || fail "missing source file: $f"
done

[ -x /etc/init.d/rpcd ] || fail "/etc/init.d/rpcd not found"
command -v ubus >/dev/null 2>&1 || fail "ubus not found"

mkdir -p /usr/share/rpcd/ucode /usr/share/l2-info/readers

copy_atomic() {
	src=$1
	dst=$2
	tmp="${dst}.new.$$"

	cp "$src" "$tmp"
	chmod 0644 "$tmp"
	mv "$tmp" "$dst"
}

# The assembler is loaded once when rpcd loads the ubus plugin, while readers
# are discovered from disk for each snapshot. Install/reload the core first so
# a running old assembler is never exposed to a newer reader vocabulary during
# a manual development update (for example br.address in D47).
copy_atomic "$SRC/rpcd/ucode/l2-info" /usr/share/rpcd/ucode/l2-info
copy_atomic "$SRC/l2-info/assemble.uc" /usr/share/l2-info/assemble.uc

/etc/init.d/rpcd reload

# rpcd reload can briefly race an immediate ubus lookup. Retry once so a
# successful install is not reported as failed merely because registration has
# not completed yet.
if ! ubus -v list l2-info >/dev/null 2>&1; then
	sleep 1
	ubus -v list l2-info >/dev/null 2>&1 || fail "l2-info ubus object did not register after rpcd reload"
fi

# Readers are loaded afresh by snapshot(), so no second rpcd reload is needed.
copy_atomic "$SRC/l2-info/readers/rtnl.uc" /usr/share/l2-info/readers/rtnl.uc

echo "l2-info development backend installed from: $ROOT"
echo "Verify with: ubus call l2-info snapshot"
