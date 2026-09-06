/* SPDX-License-Identifier: Apache-2.0 */
'use strict';

const fs = require('fs');
const path = require('path');

const root = process.argv[2] || path.join(__dirname, '..');
const QUERY = path.join(root, 'luci-app-l2-info/htdocs/luci-static/resources/l2-info/query.js');

function loadQuery() {
	const src = fs.readFileSync(QUERY, 'utf8')
		.replace(/^\s*'use strict';\s*$/m, '')
		.replace(/^\s*'require [^']*';\s*$/gm, '');
	const baseclass = { extend: (o) => o };
	return new Function('baseclass', src)(baseclass);
}

const mod = loadQuery();
let failures = 0;

function assert(name, cond, detail) {
	if (cond)
		console.log(`  ok   query/${name}`);
	else {
		console.log(`  FAIL query/${name}${detail ? `: ${detail}` : ''}`);
		failures++;
	}
}

function row(mac, port, vlan, macClass = 'unicast') {
	return {
		subject: { mac },
		attrs: { 'fdb.port': port },
		derived: { vlan, mac_class: macClass }
	};
}

const snap = {
	fdb: [
		row('02:00:00:00:00:01', 'lan1', 10),
		row('02:00:00:00:00:02', 'lan2', 20),
		row('33:33:00:00:00:01', 'lan1', 10, 'multicast')
	]
};

assert('empty vlan means any', mod.parseVlan('').value === null);
assert('lowest vlan accepted', mod.parseVlan('1').value === 1);
assert('highest vlan accepted', mod.parseVlan('4094').value === 4094);
assert('vlan suffix rejected', mod.parseVlan('12abc').error === 'vlan-format');
assert('vlan zero rejected', mod.parseVlan('0').error === 'vlan-range');
assert('vlan 4095 rejected', mod.parseVlan('4095').error === 'vlan-range');

assert('mac punctuation accepted', mod.parseMac('02:00-00.00 00:01').value === '020000000001');
assert('partial mac accepted', mod.parseMac('00:00:01').value === '000001');
assert('non-hex mac rejected', mod.parseMac('zz').error === 'mac-format');
assert('overlong mac rejected', mod.parseMac('020000000001aa').error === 'mac-length');

let r = mod.filterRows(snap, { port: 'lan1', vlan: '', mac: '', nonUnicast: false });
assert('port filter', r.rows.length === 1 && r.rows[0].subject.mac === '02:00:00:00:00:01');

r = mod.filterRows(snap, { port: '', vlan: '20', mac: '', nonUnicast: false });
assert('vlan filter', r.rows.length === 1 && r.rows[0].attrs['fdb.port'] === 'lan2');

r = mod.filterRows(snap, { port: '', vlan: '', mac: '00:00:02', nonUnicast: false });
assert('partial mac filter', r.rows.length === 1 && r.rows[0].attrs['fdb.port'] === 'lan2');

r = mod.filterRows(snap, { port: '', vlan: '', mac: '', nonUnicast: true });
assert('non-unicast opt-in', r.rows.length === 3);

r = mod.filterRows(snap, { port: '', vlan: '12abc', mac: '', nonUnicast: true });
assert('invalid vlan returns no rows and an error', r.rows.length === 0 && r.query.errors.includes('vlan-format'));

r = mod.filterRows(snap, { port: '', vlan: '', mac: 'zz', nonUnicast: true });
assert('invalid mac returns no rows and an error', r.rows.length === 0 && r.query.errors.includes('mac-format'));

process.exit(failures ? 1 : 0);
