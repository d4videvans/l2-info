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
	var reported = (r.attrs['fdb.vlan'] === undefined) ? null : r.attrs['fdb.vlan'];
	return [ r.subject.mac, r.attrs['fdb.port'], JSON.stringify(reported) ].join('/');
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

function eligible(r) {
	var d = r.derived || {};
	return !d.local && d.mac_class == 'unicast' && !!r.attrs['fdb.port'];
}

function portPresence(rows) {
	var byMac = {};

	(rows || []).forEach(function(r) {
		if (!eligible(r))
			return;

		var mac = r.subject.mac, port = r.attrs['fdb.port'];
		byMac[mac] ||= {};
		byMac[mac][port] ||= [];
		byMac[mac][port].push(r);
	});

	return byMac;
}

function vlanFor(rows) {
	var values = [];

	(rows || []).forEach(function(r) {
		var v = r.derived?.vlan;
		if (v != null && values.indexOf(v) < 0)
			values.push(v);
	});

	return values.length == 1 ? values[0] : null;
}

function diff(cur, prev) {
	var a = {}, b = {}, out = {
		appeared: [], vanished: [], moved: [],
		presenceAppeared: [], presenceVanished: []
	};

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

	var now = portPresence(cur.fdb), before = portPresence(prev.fdb);
	var macs = {};
	Object.keys(now).forEach(function(m) { macs[m] = true; });
	Object.keys(before).forEach(function(m) { macs[m] = true; });

	Object.keys(macs).forEach(function(mac) {
		var np = Object.keys(now[mac] || {});
		var bp = Object.keys(before[mac] || {});

		np.forEach(function(port) {
			if (!(before[mac] || {})[port])
				out.presenceAppeared.push(now[mac][port][0]);
		});

		bp.forEach(function(port) {
			if (!(now[mac] || {})[port])
				out.presenceVanished.push(before[mac][port][0]);
		});

		if (np.length != 1 || bp.length != 1 || np[0] == bp[0])
			return;

		var nrows = now[mac][np[0]], brows = before[mac][bp[0]];
		out.moved.push({
			mac: mac,
			from: bp[0],
			to: np[0],
			fromVlan: vlanFor(brows),
			toVlan: vlanFor(nrows),
			weak: brows.concat(nrows).some(function(r) {
				return r.derived?.vlan_source == 'pvid';
			})
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
