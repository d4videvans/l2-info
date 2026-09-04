/* SPDX-License-Identifier: Apache-2.0 */
'use strict';

const fs = require('fs');
const path = require('path');

const root = process.argv[2] || path.join(__dirname, '..');
const DIFF = path.join(root, 'luci-app-l2-info/htdocs/luci-static/resources/l2-info/diff.js');

function loadDiff() {
	const src = fs.readFileSync(DIFF, 'utf8')
		.replace(/^\s*'use strict';\s*$/m, '')
		.replace(/^\s*'require [^']*';\s*$/gm, '');
	const baseclass = { extend: (o) => o };
	String.prototype.format = function() {
		const args = arguments;
		let i = 0;
		return this.replace(/%s/g, () => String(args[i++]));
	};
	return new Function('baseclass', src)(baseclass);
}

const mod = loadDiff();
let failures = 0;

function assert(name, cond, detail) {
	if (cond)
		console.log(`  ok   diff/${name}`);
	else {
		console.log(`  FAIL diff/${name}${detail ? `: ${detail}` : ''}`);
		failures++;
	}
}

function row(mac, port, vlan, opts = {}) {
	return {
		subject: { mac },
		attrs: { 'fdb.port': port },
		derived: {
			vlan,
			vlan_source: opts.vlan_source || 'reported',
			mac_class: opts.mac_class || 'unicast',
			local: !!opts.local
		}
	};
}

function snap(rows, readers = { rtnl: { status: 'ok', provides: [ 'fdb' ] } }) {
	return {
		format: 'l2-info.snapshot',
		version: 1,
		fdb: rows,
		scope: {
			bridges: { status: 'ok' }, ports: { status: 'ok' },
			fdb: { status: 'ok' }, neighbours: { status: 'ok' },
			names: { status: 'ok' }, readers
		}
	};
}

const MAC = '02:00:00:00:00:01';

let d = mod.diff(snap([ row(MAC, 'lan2', 10) ]), snap([ row(MAC, 'lan1', 10) ]));
assert('one-to-one move', d.moved.length === 1 && d.moved[0].from === 'lan1' && d.moved[0].to === 'lan2');

d = mod.diff(snap([ row(MAC, 'lan2', 10), row(MAC, 'lan3', 10) ]), snap([ row(MAC, 'lan1', 10) ]));
assert('one-to-many stays primitive', d.moved.length === 0 && d.appeared.length === 2 && d.vanished.length === 1);

d = mod.diff(snap([ row(MAC, 'lan3', 10) ]), snap([ row(MAC, 'lan1', 10), row(MAC, 'lan2', 10) ]));
assert('many-to-one stays primitive', d.moved.length === 0 && d.appeared.length === 1 && d.vanished.length === 2);

d = mod.diff(snap([ row(MAC, 'lan3', 10), row(MAC, 'lan4', 10) ]), snap([ row(MAC, 'lan1', 10), row(MAC, 'lan2', 10) ]));
assert('many-to-many stays primitive', d.moved.length === 0 && d.appeared.length === 2 && d.vanished.length === 2);

d = mod.diff(snap([ row(MAC, 'lan2', 20) ]), snap([ row(MAC, 'lan2', 10) ]));
assert('vlan-only change is not a move', d.moved.length === 0 && d.appeared.length === 1 && d.vanished.length === 1);

d = mod.diff(snap([ row(MAC, 'lan2', 10, { local: true }) ]), snap([ row(MAC, 'lan1', 10, { local: true }) ]));
assert('local address is not moved', d.moved.length === 0);

d = mod.diff(snap([ row('01:00:5e:00:00:01', 'lan2', 10, { mac_class: 'multicast' }) ]), snap([ row('01:00:5e:00:00:01', 'lan1', 10, { mac_class: 'multicast' }) ]));
assert('multicast address is not moved', d.moved.length === 0);

let a = snap([]), b = snap([]);
assert('same scope compatible', mod.scopeCompatible(a, b).length === 0);

a = snap([], {
	rtnl: { status: 'ok', provides: [ 'fdb' ] },
	extra: { status: 'ok', provides: [ 'fdb' ] }
});
b = snap([], {
	rtnl: { status: 'ok', provides: [ 'fdb' ] },
	extra: { status: 'unavailable', provides: [ 'fdb' ] }
});
assert('reader coverage change blocks diff', mod.scopeCompatible(a, b).includes('reader coverage'));

a = snap([]); b = snap([]); b.scope.fdb.status = 'unavailable';
assert('collection status change blocks diff', mod.scopeCompatible(a, b).some((x) => x.startsWith('fdb ')));

a = snap([]); b = snap([]); b.version = 2;
assert('format version change blocks diff', mod.scopeCompatible(a, b).includes('format/version'));

process.exit(failures ? 1 : 0);
