/* SPDX-License-Identifier: Apache-2.0 */
/* l2-info snapshot comparison.
 *
 * Comparison is deliberately pure and lives outside the view so ambiguity is
 * testable. Three identities are kept separate (D12): raw observation identity
 * follows the reported FDB VLAN, primitive visible placement uses the effective
 * VLAN, and movement inference uses complete remote-unicast port presence.
 */

'use strict';
'require baseclass';

/* Only these collections can change diff identity or movement interpretation:
 * FDB rows directly; port facts through PVID and local-address derivation; and
 * bridge facts through br.address, which also participates in derived.local
 * (D47). Names and neighbours are annotations and must not make an FDB diff
 * unusable. */
var DIFF_COLLECTIONS = [ 'bridges', 'ports', 'fdb' ];

/* Raw identity follows what the FDB actually reported. An untagged row whose
 * effective VLAN comes from the PVID must remain distinct from an otherwise
 * identical row that explicitly reported that VLAN. */
function observationKey(r) {
	var reported = (r.attrs['fdb.vlan'] === undefined) ? null : r.attrs['fdb.vlan'];
	return [ r.subject.mac, r.attrs['fdb.port'], JSON.stringify(reported) ].join('/');
}

/* Primitive user-visible appeared/gone evidence is deliberately coarser than
 * raw identity: two kernel observations which resolve to the same MAC, port
 * and effective VLAN describe one visible forwarding placement. This preserves
 * VLAN-only changes while preventing raw-detail churn from reading as a host
 * disappearance. It is presentation collapse, not raw observation merging. */
function primitiveKey(r) {
	var vlan = r.derived?.vlan;
	return [
		r.subject.mac,
		r.attrs['fdb.port'],
		JSON.stringify(vlan == null ? null : vlan)
	].join('/');
}

function keyedRows(rows, keyfn) {
	var out = {};

	(rows || []).forEach(function(r) {
		var k = keyfn(r);
		if (!out[k])
			out[k] = r;
	});

	return out;
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

/* A move must not turn "several VLANs" into the same value as "no resolved
 * VLAN". Retain the complete distinct effective-VLAN set for the one old/new
 * port. null is retained as an explicit unresolved member and sorted last. */
function vlanSet(rows) {
	var values = [], unresolved = false;

	(rows || []).forEach(function(r) {
		var v = r.derived?.vlan;
		if (v == null)
			unresolved = true;
		else if (values.indexOf(v) < 0)
			values.push(v);
	});

	values.sort(function(a, b) { return a - b; });
	if (unresolved)
		values.push(null);

	return values;
}

function vlanSetContains(values, vlan) {
	return (values || []).some(function(v) {
		return (v == null && vlan == null) || v === vlan;
	});
}

/* Primitive placement evidence represented completely by a moved row need not
 * be repeated. Suppression is exact to the move's MAC, side, port and effective
 * VLAN; it is never a MAC-wide presentation filter. */
function moveAccountsFor(r, m, after) {
	var port = r.attrs['fdb.port'];
	var vlan = r.derived?.vlan;
	var expectedPort = after ? m.to : m.from;
	var vlans = after ? m.toVlans : m.fromVlans;

	return r.subject.mac == m.mac && port == expectedPort && vlanSetContains(vlans, vlan);
}

function diff(cur, prev) {
	var a = keyedRows(cur.fdb, observationKey);
	var b = keyedRows(prev.fdb, observationKey);
	var pa = keyedRows(cur.fdb, primitiveKey);
	var pb = keyedRows(prev.fdb, primitiveKey);
	var out = {
		appeared: [], vanished: [], moved: [],
		primitiveAppeared: [], primitiveVanished: [],
		visibleAppeared: [], visibleVanished: []
	};

	Object.keys(a).forEach(function(k) {
		if (!b[k])
			out.appeared.push(a[k]);
	});

	Object.keys(b).forEach(function(k) {
		if (!a[k])
			out.vanished.push(b[k]);
	});

	Object.keys(pa).forEach(function(k) {
		if (!pb[k])
			out.primitiveAppeared.push(pa[k]);
	});

	Object.keys(pb).forEach(function(k) {
		if (!pa[k])
			out.primitiveVanished.push(pb[k]);
	});

	var now = portPresence(cur.fdb), before = portPresence(prev.fdb);
	var macs = {};
	Object.keys(now).forEach(function(m) { macs[m] = true; });
	Object.keys(before).forEach(function(m) { macs[m] = true; });

	Object.keys(macs).forEach(function(mac) {
		var np = Object.keys(now[mac] || {});
		var bp = Object.keys(before[mac] || {});

		if (np.length != 1 || bp.length != 1 || np[0] == bp[0])
			return;

		var nrows = now[mac][np[0]], brows = before[mac][bp[0]];
		out.moved.push({
			mac: mac,
			from: bp[0],
			to: np[0],
			fromVlans: vlanSet(brows),
			toVlans: vlanSet(nrows),
			weak: brows.concat(nrows).some(function(r) {
				return r.derived?.vlan_source == 'pvid';
			})
		});
	});

	out.visibleAppeared = out.primitiveAppeared.filter(function(r) {
		return !out.moved.some(function(m) { return moveAccountsFor(r, m, true); });
	});
	out.visibleVanished = out.primitiveVanished.filter(function(r) {
		return !out.moved.some(function(m) { return moveAccountsFor(r, m, false); });
	});

	return out;
}

return baseclass.extend({
	collectionFingerprint: collectionFingerprint,
	readerFingerprint: readerFingerprint,
	scopeCompatible: scopeCompatible,
	diff: diff
});
