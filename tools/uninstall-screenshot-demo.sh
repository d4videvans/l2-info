#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Remove only the synthetic screenshot/demo surface.

set -eu

fail() {
	echo "uninstall-screenshot-demo: $*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must be run as root on the target OpenWrt device"

for f in \
	/usr/share/rpcd/ucode/l2-info-demo \
	/usr/share/l2-info/demo-snapshot.uc \
	/www/luci-static/resources/view/l2-info/demo.js \
	/usr/share/luci/menu.d/luci-app-l2-info-demo.json \
	/usr/share/rpcd/acl.d/luci-app-l2-info-demo.json
do
	[ ! -f "$f" ] || rm -f "$f"
done

rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/

if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null || \
		fail "demo files were removed but rpcd could not be reloaded/restarted"
fi

printf '%s\n' "Synthetic screenshot mode removed; the ordinary l2-info install was left untouched."
