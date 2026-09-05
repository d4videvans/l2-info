#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Install the LuCI view from this checkout onto the OpenWrt device on which the
# checkout resides. Development helper only: this bypasses the package manager.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/luci-app-l2-info"

fail() {
	echo "install-dev-luci: $*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must be run as root on the target OpenWrt device"
[ -d /www/luci-static/resources ] || fail "LuCI resources directory not found; is luci-base installed?"
[ -x /etc/init.d/rpcd ] || fail "/etc/init.d/rpcd not found"

FILES="
htdocs/luci-static/resources/view/l2-info/main.js
htdocs/luci-static/resources/l2-info/hints.js
htdocs/luci-static/resources/l2-info/query.js
htdocs/luci-static/resources/l2-info/diff.js
root/usr/share/luci/menu.d/luci-app-l2-info.json
root/usr/share/rpcd/acl.d/luci-app-l2-info.json
"

for f in $FILES; do
	[ -f "$APP/$f" ] || fail "missing source file: $APP/$f"
done

mkdir -p \
	/www/luci-static/resources/view/l2-info \
	/www/luci-static/resources/l2-info \
	/usr/share/luci/menu.d \
	/usr/share/rpcd/acl.d

copy_atomic() {
	src=$1
	dst=$2
	tmp="${dst}.new.$$"

	cp "$src" "$tmp"
	chmod 0644 "$tmp"
	mv "$tmp" "$dst"
}

copy_atomic "$APP/htdocs/luci-static/resources/view/l2-info/main.js" \
	/www/luci-static/resources/view/l2-info/main.js
copy_atomic "$APP/htdocs/luci-static/resources/l2-info/hints.js" \
	/www/luci-static/resources/l2-info/hints.js
copy_atomic "$APP/htdocs/luci-static/resources/l2-info/query.js" \
	/www/luci-static/resources/l2-info/query.js
copy_atomic "$APP/htdocs/luci-static/resources/l2-info/diff.js" \
	/www/luci-static/resources/l2-info/diff.js
copy_atomic "$APP/root/usr/share/luci/menu.d/luci-app-l2-info.json" \
	/usr/share/luci/menu.d/luci-app-l2-info.json
copy_atomic "$APP/root/usr/share/rpcd/acl.d/luci-app-l2-info.json" \
	/usr/share/rpcd/acl.d/luci-app-l2-info.json

# Match luci.mk's package post-install cache invalidation closely enough for a
# copied-checkout development update. The menu and ACL are then re-read after
# rpcd reload / the next LuCI request rather than leaving stale cached state.
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload 2>/dev/null || fail "rpcd reload failed"

echo "l2-info development LuCI files installed from: $ROOT"
echo "Refresh LuCI and open Status -> MAC & VLAN Lookup"
