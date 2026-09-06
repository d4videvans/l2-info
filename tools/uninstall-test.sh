#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Remove files installed by tools/install-test.sh / the development installers.
# Shared OpenWrt package dependencies are intentionally left installed.

set -eu

fail() {
	echo "uninstall-test: $*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must be run as root on the target OpenWrt device"

FILES="
/usr/share/rpcd/ucode/l2-info
/usr/share/l2-info/assemble.uc
/usr/share/l2-info/readers/rtnl.uc
/www/luci-static/resources/view/l2-info/main.js
/www/luci-static/resources/l2-info/hints.js
/www/luci-static/resources/l2-info/query.js
/www/luci-static/resources/l2-info/diff.js
/usr/share/luci/menu.d/luci-app-l2-info.json
/usr/share/rpcd/acl.d/luci-app-l2-info.json
"

removed=0
for f in $FILES; do
	if [ -f "$f" ]; then
		rm -f "$f"
		printf 'removed %s\n' "$f"
		removed=$((removed + 1))
	fi
done

# Remove only project-specific directories, and only when they are empty.
rmdir /usr/share/l2-info/readers 2>/dev/null || true
rmdir /usr/share/l2-info 2>/dev/null || true
rmdir /www/luci-static/resources/view/l2-info 2>/dev/null || true
rmdir /www/luci-static/resources/l2-info 2>/dev/null || true

rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/

if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null || \
		fail "l2-info files were removed but rpcd could not be reloaded/restarted"
fi

printf '\nl2-info pre-upstream test files removed (%s file(s)).\n' "$removed"
printf '%s\n' "Shared rpcd/ucode dependencies were left installed."
