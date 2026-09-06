#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Add a separate synthetic LuCI demo page for safe screenshots. This does not
# replace or modify the production l2-info ubus object or view.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
	echo "install-screenshot-demo: $*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must be run as root on the target OpenWrt device"
[ -x /etc/init.d/rpcd ] || fail "/etc/init.d/rpcd not found"
command -v ubus >/dev/null 2>&1 || fail "ubus not found"

MAIN=/www/luci-static/resources/view/l2-info/main.js
DEMO=/www/luci-static/resources/view/l2-info/demo.js
[ -f "$MAIN" ] || fail "l2-info LuCI view not installed; run: sh $ROOT/tools/install-test.sh"
[ -f "$ROOT/tools/demo-backend.uc" ] || fail "missing tools/demo-backend.uc"
[ -f "$ROOT/tools/demo-snapshot.uc" ] || fail "missing tools/demo-snapshot.uc"

count=$(grep -c "object: 'l2-info'" "$MAIN" || true)
[ "$count" -eq 1 ] || fail "expected exactly one l2-info rpc object declaration in $MAIN; found $count"
count=$(grep -F -c "_('MAC & VLAN Lookup')" "$MAIN" || true)
[ "$count" -eq 1 ] || fail "expected exactly one production page title in $MAIN; found $count"
count=$(grep -F -c "Take one read-only snapshot" "$MAIN" || true)
[ "$count" -eq 1 ] || fail "expected exactly one production introduction in $MAIN; found $count"
count=$(grep -F -c "Read from the kernel, not from configuration." "$MAIN" || true)
[ "$count" -eq 1 ] || fail "expected exactly one production VLAN legend in $MAIN; found $count"
count=$(grep -F -c "This does not read the hardware again." "$MAIN" || true)
[ "$count" -eq 1 ] || fail "expected exactly one production filter description in $MAIN; found $count"

mkdir -p \
	/usr/share/l2-info \
	/usr/share/rpcd/ucode \
	/www/luci-static/resources/view/l2-info \
	/usr/share/luci/menu.d \
	/usr/share/rpcd/acl.d

cp "$ROOT/tools/demo-backend.uc" /usr/share/rpcd/ucode/l2-info-demo
cp "$ROOT/tools/demo-snapshot.uc" /usr/share/l2-info/demo-snapshot.uc
chmod 0644 /usr/share/rpcd/ucode/l2-info-demo /usr/share/l2-info/demo-snapshot.uc

# Keep the production view untouched. The demo gets its own copied view which
# calls a separate synthetic ubus object but reuses the already-installed helper
# modules and rendering code. Demo-specific wording makes it obvious that this
# page is not displaying or reading the live device.
sed \
	-e "s|object: 'l2-info'|object: 'l2-info-demo'|" \
	-e "s|_('MAC & VLAN Lookup')|_('MAC \& VLAN Lookup (synthetic demo)')|" \
	-e "s|Take one read-only snapshot.*Nothing is stored.|Synthetic demo data — no live network identifiers are shown. This page renders repository-supplied example Layer 2 data and does not read your device.|" \
	-e "s|Filter the current snapshot by any combination of port, VLAN or MAC address. This does not read the hardware again.|Filter the current synthetic snapshot by any combination of port, VLAN or MAC address. No device hardware is read.|" \
	-e "s|u = untagged, t = tagged, \* = native VLAN. Read from the kernel, not from configuration.|u = untagged, t = tagged, * = native VLAN. These values are synthetic demo data, not readings from this device.|" \
	"$MAIN" > "$DEMO"
chmod 0644 "$DEMO"

grep -Fq "object: 'l2-info-demo'" "$DEMO" || fail "demo rpc object rewrite failed"
grep -Fq "MAC & VLAN Lookup (synthetic demo)" "$DEMO" || fail "demo title rewrite failed"
grep -Fq "Synthetic demo data — no live network identifiers are shown." "$DEMO" || fail "demo introduction rewrite failed"
grep -Fq "No device hardware is read." "$DEMO" || fail "demo filter wording rewrite failed"
grep -Fq "These values are synthetic demo data, not readings from this device." "$DEMO" || fail "demo VLAN legend rewrite failed"

cat > /usr/share/luci/menu.d/luci-app-l2-info-demo.json <<'JSON'
{
	"admin/status/l2-info-demo": {
		"title": "MAC & VLAN Lookup (synthetic demo)",
		"order": 56,
		"action": {
			"type": "view",
			"path": "l2-info/demo"
		},
		"depends": {
			"acl": [ "luci-app-l2-info-demo" ]
		}
	}
}
JSON

cat > /usr/share/rpcd/acl.d/luci-app-l2-info-demo.json <<'JSON'
{
	"luci-app-l2-info-demo": {
		"description": "Read synthetic l2-info screenshot data",
		"read": {
			"ubus": {
				"l2-info-demo": [ "snapshot" ]
			}
		}
	}
}
JSON

rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null || \
	fail "demo files were installed but rpcd could not be reloaded/restarted"

if ! ubus -v list l2-info-demo >/dev/null 2>&1; then
	sleep 1
	ubus -v list l2-info-demo >/dev/null 2>&1 || fail "l2-info-demo ubus object did not register"
fi

printf '%s\n' "Synthetic screenshot mode installed."
printf '%s\n' "Refresh LuCI and open: Status -> MAC & VLAN Lookup (synthetic demo)"
printf '%s\n' "The ordinary MAC & VLAN Lookup page still uses your live device data."
printf '%s\n' "Remove demo mode with: sh $ROOT/tools/uninstall-screenshot-demo.sh"
