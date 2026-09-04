// SPDX-License-Identifier: Apache-2.0
//
// Development-only, read-only probe for R4 in docs/remediation.md.
//
// It records just enough of RTM_GETLINK to establish how bridge identity is
// exposed by ucode-mod-rtnl. It performs no writes and deliberately omits
// interface hardware addresses and unrelated link attributes.
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

function dump(payload) {
	let rows = nl.request(nl.const.RTM_GETLINK, nl.const.NLM_F_DUMP, payload);
	let err = nl.error();

	if (err != null)
		return { error: err, rows: [] };

	if (rows == null)
		return { error: 'netlink dump returned no result and no error', rows: [] };

	return { rows };
}

function shape(l) {
	let out = {
		name: l.ifname ?? l.dev ?? null,
		master: l.master ?? null,
		linkinfo: l.linkinfo ?? null
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
