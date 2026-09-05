// SPDX-License-Identifier: Apache-2.0
//
// Development-only, read-only probe for bridge/link rtnetlink behaviour.
//
// It records just enough of RTM_GETLINK to establish how bridge identity is
// exposed by ucode-mod-rtnl. Interface hardware addresses are deliberately not
// emitted. Instead the probe records whether an address was present and, when
// sysfs exposes the same interface address, whether the two values agree. This
// lets D47's bridge-address input be verified without putting a real MAC in a
// capture.
//
// Run on an OpenWrt target with ucode-mod-rtnl installed:
//
//   ucode tools/probe-rtnl-links.uc
//
// Capture an ordinary bridge first; if the target is a safe lab box, repeat
// with an empty temporary bridge present. Do not commit unreviewed output as a
// fixture; D15 redaction still applies to contributed captures.

'use strict';

import { access, lsdir, readfile } from 'fs';

const RTEXT_FILTER_BRVLAN_COMPRESSED = 0x04;

let nl = require('rtnl');

function macfmt(mac) {
	let h = lc(replace(mac ?? '', /[^0-9A-Fa-f]/g, ''));

	if (length(h) != 12)
		return null;

	let out = [];

	for (let i = 0; i < 12; i += 2)
		push(out, substr(h, i, 2));

	return join(':', out);
}

function dump(payload) {
	let rows = nl.request(nl.const.RTM_GETLINK, nl.const.NLM_F_DUMP, payload);
	let err = nl.error();

	if (err != null)
		return { error: err, rows: [] };

	// ucode-mod-rtnl leaves the result null for a successful zero-row dump;
	// error state is independent (D48).
	return { error: null, rows: rows ?? [] };
}

function shape(l) {
	let name = l.ifname ?? l.dev ?? null;
	let address = macfmt(l.address);
	let sysfs_address = name ? macfmt(readfile(`/sys/class/net/${name}/address`)) : null;
	let out = {
		name,
		master: l.master ?? null,
		linkinfo: l.linkinfo ?? null,
		address_present: address != null,
		address_matches_sysfs: (address != null && sysfs_address != null)
			? address == sysfs_address
			: null
	};

	let bridge = l.af_spec?.bridge;

	if (bridge != null)
		out.bridge_af_spec = {
			bridge_vlan_info: bridge.bridge_vlan_info ?? []
		};

	return out;
}

function shaped(d) {
	return {
		error: d.error ?? null,
		rows: map(d.rows ?? [], shape)
	};
}

let generic = dump({});
let bridge = dump({
	family: nl.const.AF_BRIDGE,
	ext_mask: RTEXT_FILTER_BRVLAN_COMPRESSED
});

let sysfs = [];

for (let name in sort(lsdir('/sys/class/net') ?? [])) {
	let dir = `/sys/class/net/${name}/bridge`;

	if (!access(dir, 'r'))
		continue;

	let vf = readfile(`${dir}/vlan_filtering`);

	push(sysfs, {
		name,
		vlan_filtering: (vf == null) ? null : trim(vf)
	});
}

print(sprintf('%J\n', {
	generic_links: shaped(generic),
	af_bridge_links: shaped(bridge),
	sysfs_bridges: sysfs
}));
