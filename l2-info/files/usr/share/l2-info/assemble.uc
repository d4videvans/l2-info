// SPDX-License-Identifier: Apache-2.0
//
// l2-info - the assembler.
//
// Discovers readers, calls each once, validates each against its own
// manifest, merges rows by subject, declares what was and was not seen,
// derives once over the merged set, and stamps provenance.
//
// This is a library. The ubus surface is /usr/share/rpcd/ucode/l2-info; the
// fixture harnesses load this file directly, which is why discovery and the
// reader context are parameters rather than globals.
//
// Contracts: docs/readers.md for the reader interface, docs/snapshot-format.md
// for what comes out. Rules: docs/principles.md.

'use strict';

import { readfile, access, lsdir } from 'fs';

const READER_DIR = '/usr/share/l2-info/readers';
const SUPPORTED_API = [ 1 ];
const FORMAT = 'l2-info.snapshot';
const FORMAT_VERSION = 1;

const COLLECTIONS = [ 'bridges', 'ports', 'fdb', 'neighbours', 'names' ];
const STATUSES = [ 'ok', 'unavailable', 'not_applicable', 'indeterminate' ];
const SUBJECT_KINDS = [ 'mac', 'port', 'bridge', 'self' ];

const ATTRS = {
	'br.name': true, 'br.vlan_filtering': true,
	'topo.port': true, 'topo.bridge': true, 'topo.carrier': true,
	'topo.address': true, 'topo.vlans': true, 'topo.vlan_flags': true,
	'topo.vlan_pvid': true, 'topo.vlan_untagged': true,
	'fdb.port': true, 'fdb.vlan': true, 'fdb.bridge': true, 'fdb.flags': true,
	'neigh.ips': true,
	'name.hostname': true
};

// A subject is not always one observation. One MAC is legitimately present on
// several ports at once - every multicast group address is on all of them -
// and those are distinct observations, not a disagreement about one. So each
// collection declares which attributes distinguish observations of the same
// subject; the merge key is the subject plus those values (D40).
const DISCRIMINATORS = {
	fdb: [ 'fdb.port', 'fdb.vlan' ]
};

// Set-valued attributes accumulate across rows rather than conflicting. Two
// rows reporting membership are not two sources disagreeing: the bridge FDB
// reports one forwarding entry twice on a DSA switch with assisted learning on
// the CPU port, once as `self` from the hardware table and once as `master`
// from the software bridge, and the honest flag set is the union of both.
const SET_VALUED = {
	'fdb.flags': true,
	'neigh.ips': true
};

// Addresses that identify a protocol rather than a host. The two exact values
// at the end were observed as bridge-FDB self entries across an entire fleet
// without their registering protocol being identified; they are classified
// against a published constant, never dropped (P2).
const PROTOCOL_EXACT = {
	'ff:ff:ff:ff:ff:ff': true, '00:00:00:00:00:00': true,
	'01:00:81:00:01:00': true, '01:e0:52:cc:cc:cc': true
};

const PROTOCOL_PREFIXES = [ '01:00:5e', '33:33', '01:80:c2', '01:00:0c', '09:00:2b' ];

// ------------------------------------------------------------------ discovery

function validate_manifest(m, id) {
	if (type(m) != 'object')
		return 'module did not return an object';

	if (m.id != id)
		return `manifest id '${m.id}' does not match filename '${id}'`;

	if (type(m.api) != 'int')
		return 'manifest api is missing or not an integer';

	if (type(m.describe) != 'string' || m.describe == '')
		return 'manifest describe is missing';

	if (type(m.provides) != 'array' || length(m.provides) == 0)
		return 'manifest provides is missing or empty';

	for (let c in m.provides)
		if (!(c in COLLECTIONS))
			return `manifest provides unregistered collection '${c}'`;

	if (m.cost != 'software' && m.cost != 'hardware-walk')
		return `manifest cost '${m.cost}' is not software or hardware-walk`;

	if (type(m.read) != 'function')
		return 'manifest read is missing or not a function';

	return null;
}

// Scan, load, validate, api-check. Every rejection is recorded with a reason:
// an installed but unusable reader is visible, not absent (P9).
function discover(dir) {
	let found = [], report = {};

	dir ??= READER_DIR;

	let names = lsdir(dir) ?? [];

	for (let file in sort(names)) {
		if (!match(file, /^([a-z0-9-]+)\.uc$/))
			continue;

		let id = replace(file, /\.uc$/, '');
		let path = `${dir}/${file}`;
		let m;

		try {
			let fn = loadfile(path);
			m = fn();
		}
		catch (e) {
			report[id] = { status: 'skipped', reason: `load failed: ${e.message ?? e}` };
			continue;
		}

		let bad = validate_manifest(m, id);

		if (bad) {
			report[id] = { status: 'skipped', reason: bad };
			continue;
		}

		if (!(m.api in SUPPORTED_API)) {
			report[id] = {
				status: 'skipped',
				reason: `manifest api ${m.api} is not supported (this core supports ${join(', ', SUPPORTED_API)})`
			};
			continue;
		}

		push(found, m);
		report[id] = {
			status: 'ok', api: m.api, cost: m.cost,
			describe: m.describe, provides: m.provides
		};
	}

	return { readers: found, report };
}

// Readers are handed source primitives for dependency injection and total
// fixture replay. This is a contract, not a sandbox: reader modules are trusted
// package code running in-process with rpcd and can ignore ctx (D34).
function make_context() {
	let nl = null;

	try {
		nl = require('rtnl');
	}
	catch (e) {
		nl = null;
	}

	return {
		api: 1,
		nl,
		fs: {
			readfile: (path) => {
				try { return readfile(path); } catch (e) { return null; }
			},
			access: (path, mode) => {
				try { return !!access(path, mode ?? 'r'); } catch (e) { return false; }
			}
		},
		ubus: {
			call: (object, method, args) => {
				try {
					let b = require('ubus').connect();
					let r = b.call(object, method, args);
					b.disconnect();
					return r;
				}
				catch (e) {
					return null;
				}
			}
		}
	};
}

// ------------------------------------------------------------------- validate

// A row's collection follows from its attribute namespace, so a reader never
// has to label rows and cannot mislabel them.
function collection_of(row) {
	for (let a in keys(row.attrs ?? {})) {
		let ns = split(a, '.')[0];

		if (ns == 'br')    return 'bridges';
		if (ns == 'topo')  return 'ports';
		if (ns == 'fdb')   return 'fdb';
		if (ns == 'neigh') return 'neighbours';
		if (ns == 'name')  return 'names';
	}

	return null;
}


// A reader's return is checked against its own manifest before anything is
// merged, so a contract violation is attributed to the reader that committed
// it rather than surfacing later as strange data (P9).
function validate_result(m, res) {
	if (type(res) != 'object')
		return 'read() did not return an object';

	if (type(res.collections) != 'object')
		return 'read() returned no collections';

	if (res.rows != null && type(res.rows) != 'array')
		return 'read() returned rows that are not an array';

	for (let c in m.provides)
		if (res.collections[c] == null)
			return `read() omitted claimed collection '${c}'`;

	for (let c, st in res.collections) {
		if (!(c in m.provides))
			return `read() reported unclaimed collection '${c}'`;

		if (!(st.status in STATUSES))
			return `collection '${c}' has unknown status '${st.status}'`;

		if (st.status != 'ok' && (type(st.reason) != 'string' || st.reason == ''))
			return `collection '${c}' is ${st.status} without a reason`;
	}

	for (let r in res.rows ?? []) {
		if (type(r) != 'object' || type(r.subject) != 'object')
			return 'a row has no subject';

		if (r.derived != null)
			return 'a row carries derived, which only the assembler may set';

		if (r.source != null)
			return 'a row carries source, which only the assembler may set';

		let sk = keys(r.subject);

		if (length(sk) != 1 || !(sk[0] in SUBJECT_KINDS))
			return `a row subject is not exactly one of ${join(', ', SUBJECT_KINDS)}`;

		for (let a, v in r.attrs ?? {}) {
			if (!ATTRS[a])
				return `a row carries unregistered attribute '${a}'`;

			if (v == null)
				return `attribute '${a}' is null; omit it instead`;
		}

		let coll = collection_of(r);

		if (coll == null)
			return 'a row carries no attribute identifying its collection';

		if (res.collections[coll]?.status != 'ok')
			return `a row belongs to collection '${coll}', which is not ok`;
	}

	return null;
}

// ---------------------------------------------------------------------- merge

// Printable separators: a NUL inside a template literal is truncated when the
// result is used as an object key, which silently collapses every subject of
// one kind into one entity.
function subject_key(s) {
	let k = keys(s)[0];

	return `${k}=${s[k]}`;
}

// Identity of an observation: its subject, plus whatever its collection uses
// to tell one observation of that subject from another.
function observation_key(coll, row) {
	let parts = [ coll, subject_key(row.subject) ];

	for (let a in DISCRIMINATORS[coll] ?? [])
		push(parts, `${a}=${sprintf('%J', row.attrs?.[a] ?? null)}`);

	return join('#', parts);
}

function union(a, b) {
	let out = [ ...(type(a) == 'array' ? a : [ a ]) ];

	for (let v in (type(b) == 'array' ? b : [ b ]))
		if (!(v in out))
			push(out, v);

	return out;
}

function same(a, b) {
	return sprintf('%J', a) == sprintf('%J', b);
}

// Rows with equal subjects describe one entity (D30). Equal values from two
// readers collapse with both sources recorded; unequal values are disputed and
// neither wins (D27, D37).
function merge(all) {
	let byKey = {}, order = [];

	for (let item in all) {
		let row = item.row, src = item.source;
		let coll = collection_of(row);
		let key = observation_key(coll, row);

		if (!byKey[key]) {
			byKey[key] = {
				collection: coll,
				subject: row.subject,
				attrs: {},
				sources: [],
				disputed: {},
				_seen: {}
			};
			push(order, key);
		}

		let e = byKey[key];

		if (!(src in e.sources))
			push(e.sources, src);

		for (let a, v in row.attrs ?? {}) {
			if (SET_VALUED[a]) {
				e.attrs[a] = (e.attrs[a] == null) ? v : union(e.attrs[a], v);
				e._seen[a] ??= src;
				continue;
			}

			if (e.disputed[a]) {
				push(e.disputed[a], { source: src, value: v });
				continue;
			}

			if (e._seen[a] == null) {
				e._seen[a] = src;
				e.attrs[a] = v;
				continue;
			}

			if (same(e.attrs[a], v))
				continue;

			// First disagreement: withdraw the value from attrs so nothing
			// silently wins, and record every claim.
			e.disputed[a] = [
				{ source: e._seen[a], value: e.attrs[a] },
				{ source: src, value: v }
			];
			delete e.attrs[a];
		}
	}

	let out = [], conflicts = [];

	for (let key in order) {
		let e = byKey[key];

		delete e._seen;

		for (let a, claims in e.disputed)
			push(conflicts, { subject: e.subject, attr: a, values: claims });

		if (length(keys(e.disputed)) == 0)
			delete e.disputed;

		push(out, e);
	}

	return { entities: out, conflicts };
}

// ---------------------------------------------------------------------- scope

// Rollup across readers claiming one collection: any ok means we have data;
// otherwise the least conclusive honest answer wins.
function rollup(states) {
	if ('ok' in states)             return 'ok';
	if ('indeterminate' in states)  return 'indeterminate';
	if ('unavailable' in states)    return 'unavailable';

	return 'not_applicable';
}

// Counts are reported over the rows as read, before merging: they describe
// what the device said, not what the assembler made of it. The switch/bridge
// split is the positive evidence P4 needs - a non-zero switch count means this
// device does report a hardware table. Zero is not evidence of the converse,
// which is why there is no boolean here.
function count_rows(all) {
	let counts = {};

	for (let item in all) {
		let coll = collection_of(item.row);

		counts[coll] ??= { count: 0 };
		counts[coll].count++;

		if (coll != 'fdb')
			continue;

		let flags = item.row.attrs?.['fdb.flags'] ?? [];

		if ('self' in flags && item.row.attrs?.['fdb.bridge'] == null) {
			counts.fdb.entries_switch_reported ??= 0;
			counts.fdb.entries_switch_reported++;
		}
		else {
			counts.fdb.entries_bridge_reported ??= 0;
			counts.fdb.entries_bridge_reported++;
		}
	}

	return counts;
}

function build_scope(readers, results, report, conflicts, all) {
	let scope = { readers: report, conflicts };
	let counts = count_rows(all ?? []);

	for (let c in COLLECTIONS) {
		let states = [], reasons = [], notes = [], claimed = false;

		for (let m in readers) {
			let st = results[m.id]?.collections?.[c];

			if (st == null)
				continue;

			claimed = true;
			push(states, st.status);

			if (st.reason)
				push(reasons, `${m.id}: ${st.reason}`);

			// A reader may attach a note to a collection it read
			// successfully - most usefully to explain an `ok` with no rows,
			// which is a real answer that is illegible without evidence
			// (D43). Carried through attributed, like a reason.
			if (st.note)
				push(notes, `${m.id}: ${st.note}`);
		}

		if (!claimed) {
			scope[c] = {
				status: 'not_applicable',
				reason: `no installed reader provides ${c} on this device`
			};
			continue;
		}

		let status = rollup(states);
		let entry = { status };

		for (let k, v in counts[c] ?? {})
			entry[k] = v;

		entry.count ??= 0;

		if (status != 'ok' && length(reasons) > 0)
			entry.reason = join('; ', reasons);
		else if (length(reasons) > 0)
			// One reader failed alongside another that succeeded: the
			// collection is ok, and the failure is still worth seeing.
			notes = [ ...notes, ...reasons ];

		if (length(notes) > 0)
			entry.note = join('; ', notes);

		scope[c] = entry;
	}

	return scope;
}

// -------------------------------------------------------------------- derive

function mac_class(mac) {
	if (PROTOCOL_EXACT[mac])
		return 'protocol';

	for (let p in PROTOCOL_PREFIXES)
		if (substr(mac, 0, length(p)) == p)
			return 'protocol';

	if (hex(substr(mac, 0, 2)) & 0x01)
		return 'multicast';

	return 'unicast';
}

// Every derived value is a join, a count, or a classification against a
// published constant - plus exactly one inference, which carries its
// provenance (P3). Computed once, here, never by a reader (D32).
function derive(entities) {
	let ports = {}, bridges = {}, ips = {}, names = {}, own = {};

	for (let e in entities) {
		if (e.collection == 'ports') {
			ports[e.subject.port] = e;

			// A switch installs its own address as a permanent entry on every
			// port and every VLAN, so without this join it looks exactly like
			// a host that has appeared everywhere at once.
			let a = e.attrs['topo.address'];

			if (a != null)
				own[a] = true;
		}
		else if (e.collection == 'bridges')
			bridges[e.subject.bridge] = e;
		else if (e.collection == 'neighbours')
			ips[e.subject.mac] = e.attrs['neigh.ips'];
		else if (e.collection == 'names')
			names[e.subject.mac] = e.attrs['name.hostname'];
	}

	let fdb_by_port = {};

	for (let e in entities) {
		if (e.collection != 'fdb')
			continue;

		let mac = e.subject.mac;
		let port = e.attrs['fdb.port'];
		let reported = e.attrs['fdb.vlan'];
		let pvid = (port != null) ? ports[port]?.attrs?.['topo.vlan_pvid'] : null;

		let d = { mac_class: mac_class(mac), local: !!own[mac] };

		// The single permitted inference: an untagged arrival carries no VLAN
		// id, and a VLAN query filtering on the reported id alone silently
		// misses every untagged host on a matching port (D13).
		if (reported != null) {
			d.vlan = reported;
			d.vlan_source = 'fdb';
		}
		else if (pvid != null) {
			d.vlan = pvid;
			d.vlan_source = 'pvid';
		}
		else {
			d.vlan = null;
			d.vlan_source = null;
		}

		d.bridge = e.attrs['fdb.bridge'] ?? ports[port]?.attrs?.['topo.bridge'] ?? null;
		d.on_bridge_device = (port != null && bridges[port] != null);

		if (ips[mac] != null)
			d.ips = ips[mac];

		if (names[mac] != null)
			d.hostname = names[mac];

		e.derived = d;

		if (port != null && !d.on_bridge_device) {
			fdb_by_port[port] ??= { macs: {}, vlans: {} };
			fdb_by_port[port].macs[mac] = true;

			if (d.vlan != null)
				fdb_by_port[port].vlans[d.vlan] = true;
		}
	}

	for (let name, e in ports) {
		let seen = fdb_by_port[name];

		e.derived = {
			mac_count: seen ? length(keys(seen.macs)) : 0,
			vlans_observed: seen ? sort(map(keys(seen.vlans), (v) => int(v))) : []
		};
	}

	for (let name, e in bridges) {
		let n = 0;

		for (let pn, pe in ports)
			if (pe.attrs['topo.bridge'] == name)
				n++;

		e.derived = { port_count: n };
	}

	return entities;
}

// ------------------------------------------------------------------ assemble

function assemble(ctx, disco) {
	let results = {}, all = [], report = disco.report;

	for (let m in disco.readers) {
		let res;

		try {
			res = m.read(ctx);
		}
		catch (e) {
			// One reader must never take down a snapshot (D28).
			report[m.id] = {
				...report[m.id],
				status: 'unavailable',
				reason: `read() threw: ${e.message ?? e}`
			};
			continue;
		}

		let bad = validate_result(m, res);

		if (bad) {
			report[m.id] = {
				...report[m.id],
				status: 'unavailable',
				reason: `contract violation: ${bad}`
			};
			continue;
		}

		results[m.id] = res;

		for (let row in res.rows ?? [])
			push(all, { row, source: m.id });
	}

	let ran = filter(disco.readers, (m) => results[m.id] != null);
	let m = merge(all);

	derive(m.entities);

	let by = { bridges: [], ports: [], fdb: [], neighbours: [], names: [] };

	for (let e in m.entities) {
		let coll = e.collection;

		delete e.collection;

		e.source = (length(e.sources) == 1) ? e.sources[0] : e.sources;
		delete e.sources;

		push(by[coll], e);
	}

	return {
		scope: build_scope(ran, results, report, m.conflicts, all),
		by
	};
}

function device_info(ctx) {
	let b = ctx.ubus.call('system', 'board', {}) ?? {};

	return {
		board: b.board_name ?? null,
		model: b.model ?? null,
		target: b.release?.target ?? null,
		kernel: b.kernel ?? null
	};
}

// ucode core has no strftime; gmtime() gives the fields.
function iso8601() {
	let t = gmtime();

	return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
	               t.year, t.mon, t.mday, t.hour, t.min, t.sec);
}

function snapshot(ctx, disco) {
	let t0 = clock(true);

	ctx ??= make_context();
	disco ??= discover();

	let a = assemble(ctx, disco);
	let t1 = clock(true);

	return {
		format: FORMAT,
		version: FORMAT_VERSION,
		captured_at: iso8601(),
		duration_ms: (t1[0] - t0[0]) * 1000 + int((t1[1] - t0[1]) / 1000000),
		cost: (length(filter(disco.readers, (m) => m.cost == 'hardware-walk')) > 0)
			? 'hardware-walk' : 'software',
		device: device_info(ctx),
		scope: a.scope,
		bridges: a.by.bridges,
		ports: a.by.ports,
		fdb: a.by.fdb,
		neighbours: a.by.neighbours,
		names: a.by.names
	};
}

return {
	COLLECTIONS, STATUSES, SUBJECT_KINDS, ATTRS,
	DISCRIMINATORS, SET_VALUED,
	SUPPORTED_API, FORMAT, FORMAT_VERSION, READER_DIR,
	validate_manifest, validate_result, collection_of,
	discover, make_context, merge, derive, assemble, snapshot,
	mac_class
};