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

/* Only these collections can change diff identity or movement interpretation:
 * FDB rows directly; port facts through PVID and local-address derivation; and
 * bridge facts through br.address, which also participates in derived.local
 * (D47). Names and neighbours are annotations and must not make an FDB diff
 * unusable. */
var DIFF_COLLECTIONS = [ 'bridges', 'ports', 'fdb' ];

function observationKey(r) {
	return [ r.subject.mac, r.attrs['fdb.port'], r.derived.vlan ].join('/');
}

function collectionFingerprint(snap, name) {
	var st = snap.scope?.[name] || {};

	return JSON.stringify({
		status: st.status ?? null,
		reason: st.reason ?? null,
		note: st.note ?? null
	});
}

function readerFingerprint(snap) {
	return Object.keys(snap.scope?.readers || {}).sort().map(function(id) {
		var r = snap.scope.readers[id] || {};
		var provides = (r.provides || []).filter(function(c) {
			return DIFF_COLLECTIONS.indexOf(c) >= 0;
		}).sort();

		if (!provides.length)
			return null;

		return JSON.stringify({
			id: id,
			status: r.status ?? null,
			api: r.api ?? null,
			provides: provides,
			reason: r.reason ?? null
		});
	}).filter(Boolean).join('|');
}

function scopeCompatible(a, b) {
	var differ = [];

	if (a.format != b.format || a.version != b.version)
		differ.push({ kind: 'format-version' });

	DIFF_COLLECTIONS.forEach(function(c) {
		var x = a.scope?.[c] || {}, y = b.scope?.[c] || {};

		if (x.status != y.status) {
			differ.push({
				kind: 'collection-status', collection: c,
				before: y.status ?? null, after: x.status ?? null
			});
		}
		else if (collectionFingerprint(a, c) != collectionFingerprint(b, c)) {
			differ.push({ kind: 'collection-coverage', collection: c });
		}
	});

	if (readerFingerprint(a) != readerFingerprint(b))
		differ.push({ kind: 'reader-coverage' });

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
			mac: mac,
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
	collectionFingerprint: collectionFingerprint,
	readerFingerprint: readerFingerprint,
	scopeCompatible: scopeCompatible,
	diff: diff
});
