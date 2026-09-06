#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Friendly pre-upstream test installer. Run with `sh`, so the executable bit is
# deliberately not required after archive/copy round trips.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
	echo "install-test: $*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must be run as root on the target OpenWrt device"
[ -f "$ROOT/tools/install-dev-backend.sh" ] || fail "backend installer not found in $ROOT/tools"
command -v ucode >/dev/null 2>&1 || fail "ucode not found"

# Package-manager installs resolve these automatically. The copied-checkout
# path must instead fail before changing files and tell the tester exactly what
# is missing. rpcd-mod-ucode installs /usr/lib/rpcd/ucode.so; the remaining
# packages are checked by loading the runtime module they provide.
MISSING_PACKAGES=""

add_missing() {
	package=$1
	case " $MISSING_PACKAGES " in
		*" $package "*) ;;
		*) MISSING_PACKAGES="${MISSING_PACKAGES}${MISSING_PACKAGES:+ }$package" ;;
	esac
}

[ -f /usr/lib/rpcd/ucode.so ] || add_missing rpcd-mod-ucode
ucode -e "require('fs')" >/dev/null 2>&1 || add_missing ucode-mod-fs
ucode -e "require('rtnl')" >/dev/null 2>&1 || add_missing ucode-mod-rtnl
ucode -e "require('ubus')" >/dev/null 2>&1 || add_missing ucode-mod-ubus

if [ -n "$MISSING_PACKAGES" ]; then
	if command -v apk >/dev/null 2>&1; then
		fail "missing required runtime package(s): $MISSING_PACKAGES; install with: apk add $MISSING_PACKAGES"
	elif command -v opkg >/dev/null 2>&1; then
		fail "missing required runtime package(s): $MISSING_PACKAGES; install with: opkg install $MISSING_PACKAGES"
	else
		fail "missing required runtime package(s): $MISSING_PACKAGES"
	fi
fi

printf '%s\n' "Installing l2-info pre-upstream test build from: $ROOT"
sh "$ROOT/tools/install-dev-backend.sh"

if [ -d /www/luci-static/resources ]; then
	[ -f "$ROOT/tools/install-dev-luci.sh" ] || fail "LuCI installer not found in $ROOT/tools"
	sh "$ROOT/tools/install-dev-luci.sh"
	printf '\n%s\n' "Test install complete. Refresh LuCI and open: Status -> MAC & VLAN Lookup"
else
	printf '\n%s\n' "LuCI was not detected; backend-only test install complete."
fi

printf '%s\n' "Command-line check: ubus call l2-info snapshot"
printf '%s\n' "Remove this test install with: sh $ROOT/tools/uninstall-test.sh"
