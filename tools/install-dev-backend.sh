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
command -v ucode >/dev/null 2>&1 || fail "ucode not found"

# A package-manager install gets these through Package/l2-info DEPENDS. This
# development helper bypasses dependency resolution, so fail before copying any
# files if the target cannot load the modules the backend requires.
MISSING_PACKAGES=""

require_ucode_module() {
	module=$1
	package=$2

	if ! ucode -e "require('$module')" >/dev/null 2>&1; then
		case " $MISSING_PACKAGES " in
			*" $package "*) ;;
			*) MISSING_PACKAGES="${MISSING_PACKAGES}${MISSING_PACKAGES:+ }$package" ;;
		esac
	fi
}

require_ucode_module fs ucode-mod-fs
require_ucode_module rtnl ucode-mod-rtnl
require_ucode_module ubus ucode-mod-ubus

if [ -n "$MISSING_PACKAGES" ]; then
	if command -v apk >/dev/null 2>&1; then
		fail "missing required runtime package(s): $MISSING_PACKAGES; install with: apk add $MISSING_PACKAGES"
	elif command -v opkg >/dev/null 2>&1; then
		fail "missing required runtime package(s): $MISSING_PACKAGES; install with: opkg install $MISSING_PACKAGES"
	else
		fail "missing required runtime package(s): $MISSING_PACKAGES"
	fi
fi

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
