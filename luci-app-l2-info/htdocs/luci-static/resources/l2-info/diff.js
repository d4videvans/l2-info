/* SPDX-License-Identifier: Apache-2.0 */
/* l2-info snapshot comparison.
 *
 * Comparison is deliberately pure and lives outside the view so ambiguity is
 * testable. A change is evidence first; "moved" is emitted only for the one
 * case where one old observation pairs unambiguously with one new observation
 * for an ordinary remote unicast address (D12).
 */

'use strict';
'require baseclass';

var COLLECTIONS = [ 'bridges', 'ports', 'fdb', 'neighbours', 'names' ];

function observationKey(r) {
	return [ r.subject.mac, r.attrs['fdb.port'], r.derived.vlan ].join('/');
}

function readerCoverage(snap) {
	var out = [];

	Object.keys(snap.scope?.readers || {}).sort().forEach(function(id) {
		var r = snap.scope.readers[id] || {};

		/* A reader which failed does not contribute trustworthy coverage to
		 * this snapshot. A successful reader stays in the fingerprint even if
		 * a collection it provides is not applicable on this device. */
		if (r.status != 'ok')
			return;

		out.push('%s:%s'.format(id, (r.provides || []).slice().sort().join(',')));
	});

	return out;
}

function scopeCompatible(a, b) {
	var differ = [];

	if (a.format != b.format || a.version != b.version)
		differ.push('format/version');

	COLLECTIONS.forEach(function(c) {
		var x = (a.scope?.[c] || {}).status;
		var y = (b.scope?.[c] || {}).status;

		if (x != y)
			differ.push('%s (%s → %s)'.format(c, y, x));
	});

	var ar = readerCoverage(a).join('|');
	var br = readerCoverage(b).join('|');

	if (ar != br)
		differ.push('reader coverage');

	return differ;
}

function diff(cur, prev) {
	var a = {}, b = {}, out = { appeared: [], vanished: [], moved: [] };

	(cur.fdb || []).forEach(function(r) { a[observationKey(r)] = r; });
	(prev.fdb || []).forEach(function(r) { b[observationKey(r)] = r; });

	Object.keys(a).forEach(function(k) {
		if (!b[k])
			out.appeared.push(a[k]);
	});

	Object.keys(b).forEach(function(k) {
		if (!a[k])
			out.vanished.push(b[k]);
	});

	var appearedByMac = {}, vanishedByMac = {};

	out.appeared.forEach(function(r) {
		var d = r.derived || {};

		if (d.local || d.mac_class != 'unicast')
			return;

		(appearedByMac[r.subject.mac] ||= []).push(r);
	});

	out.vanished.forEach(function(r) {
		var d = r.derived || {};

		if (d.local || d.mac_class != 'unicast')
			return;

		(vanishedByMac[r.subject.mac] ||= []).push(r);
	});

	Object.keys(appearedByMac).forEach(function(mac) {
		var now = appearedByMac[mac] || [];
		var before = vanishedByMac[mac] || [];

		/* Any 1:N, N:1 or N:N case has more than one possible pairing. Show
		 * the primitive evidence instead of manufacturing a plausible move. */
		if (now.length != 1 || before.length != 1)
			return;

		var r = now[0], p = before[0];

		/* A VLAN-only change is real but it is not a port move. Leaving its
		 * appear/vanish evidence visible is less misleading than "lan2 → lan2". */
		if (r.attrs['fdb.port'] == p.attrs['fdb.port'])
			return;

		out.moved.push({
			mac,
			from: p.attrs['fdb.port'],
			to: r.attrs['fdb.port'],
			fromVlan: p.derived.vlan,
			toVlan: r.derived.vlan,
			weak: (p.derived.vlan_source == 'pvid' || r.derived.vlan_source == 'pvid')
		});
	});

	return out;
}

return baseclass.extend({
	readerCoverage,
	scopeCompatible,
	diff
});
