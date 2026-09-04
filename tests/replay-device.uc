// SPDX-License-Identifier: Apache-2.0
//
// Device-fixture harness. Substitutes recorded reader results for discovery
// and runs the real assembler, then compares the resulting snapshot against
// expect.json.
//
//   ucode -R tests/replay-device.uc <fixtures/devices/class> <repo-root>
//
// Input is normalised reader output, so this harness is source-independent: a
// swconfig device and a DSA device are the same shape here and need no
// per-source stub (docs/decisions.md D26). That is what makes adding a device
// class free of harness changes.

'use strict';

import { readfile, lsdir } from 'fs';

let dir  = ARGV[0];
let root = ARGV[1];

if (!dir || !root) {
	warn('usage: replay-device.uc <fixture-dir> <repo-root>\n');
	exit(2);
}

const A = loadfile(`${root}/tests/lib/assert.uc`)();
const lib = loadfile(`${root}/l2-info/files/usr/share/l2-info/assemble.uc`)();

function leaf(path) {
	let parts = split(path, '/');

	return parts[length(parts) - 1];
}

function readjson(path) {
	let raw = readfile(path);

	return (raw != null) ? json(raw) : null;
}

let expect = readjson(`${dir}/expect.json`);

if (expect == null) {
	warn(`${dir}: missing expect.json\n`);
	exit(2);
}

// Each readers/<id>.json is one reader: its manifest fields, and either the
// read() result it returns or the exception it throws.
let readers = [], report = {};

for (let file in sort(lsdir(`${dir}/readers`) ?? [])) {
	if (!match(file, /\.json$/))
		continue;

	let id = replace(file, /\.json$/, '');
	let rec = readjson(`${dir}/readers/${file}`);

	let manifest = {
		id,
		api: rec.api ?? 1,
		describe: rec.describe ?? `recorded reader ${id}`,
		provides: rec.provides,
		cost: rec.cost ?? 'software',

		read: rec.throws
			? function() { die(rec.throws); }
			: function() { return { collections: rec.collections, rows: rec.rows ?? [] }; }
	};

	// Recorded results are validated against their own manifest exactly as a
	// live reader's would be, so a fixture cannot encode an impossible reader.
	if (!rec.expect_skip) {
		let bad = lib.validate_manifest(manifest, id);

		A.eq(bad, null, `recorded reader ${id} has a valid manifest`);
	}

	push(readers, manifest);
	report[id] = {
		status: 'ok', api: manifest.api, cost: manifest.cost,
		describe: manifest.describe, provides: manifest.provides
	};
}

// A context with nothing in it: a device fixture is above the source seam, so
// no reader here touches a primitive.
let ctx = {
	api: 1,
	nl: null,
	fs: { readfile: () => null, access: () => false },
	ubus: { call: (o, m) => (expect.board != null && o == 'system' && m == 'board')
		? expect.board : null }
};

let snap = lib.snapshot(ctx, { readers, report });

A.eq(snap.format, 'l2-info.snapshot', 'format identifier');
A.eq(snap.version, 1, 'format version');
A.ok(snap.captured_at != null && snap.captured_at != '', 'captured_at present');
A.ok(snap.scope.conflicts != null, 'scope.conflicts always present');

// Every collection must be accounted for, whether or not a reader claimed it:
// no field may be empty for two different reasons (P1, P9).
for (let c in lib.COLLECTIONS) {
	if (!A.ok(snap.scope[c] != null, `scope declares ${c}`))
		continue;

	A.ok(snap.scope[c].status in lib.STATUSES,
	     `scope.${c}.status is in the closed vocabulary`);

	if (snap.scope[c].status != 'ok')
		A.ok(snap.scope[c].reason != null && snap.scope[c].reason != '',
		     `scope.${c} is ${snap.scope[c].status} with a reason`);
}

// No row may carry a value the assembler did not compute or stamp.
for (let c in lib.COLLECTIONS) {
	for (let e in snap[c] ?? []) {
		A.ok(e.source != null, `${c} row carries a stamped source`);
		A.ok(e.derived != null || c == 'neighbours' || c == 'names',
		     `${c} row carries derived`);
	}
}

if (expect.scope)
	A.subset(snap.scope, expect.scope, 'scope');

if (expect.counts) {
	let counts = {};

	for (let c in lib.COLLECTIONS)
		counts[c] = length(snap[c] ?? []);

	A.subset(counts, expect.counts, 'counts');
}

if (expect.conflicts != null)
	A.eq(length(snap.scope.conflicts), expect.conflicts, 'conflict count');

// Named expectations about individual entities, matched on subject plus an
// optional discriminator so one MAC on two ports can be asserted separately.
for (let want in expect.entities ?? []) {
	let list = snap[want.collection] ?? [];
	let found = null;

	for (let e in list) {
		if (sprintf('%J', e.subject) != sprintf('%J', want.subject))
			continue;

		if (want.where != null) {
			let mismatch = false;

			for (let k, v in want.where)
				if (sprintf('%J', e.attrs[k]) != sprintf('%J', v))
					mismatch = true;

			if (mismatch)
				continue;
		}

		found = e;
		break;
	}

	let label = `${want.collection} ${sprintf('%J', want.subject)}`;

	if (want.absent) {
		A.ok(found == null, `${label} absent`);
		continue;
	}

	if (!A.ok(found != null, `${label} present`))
		continue;

	if (want.attrs)
		A.subset(found.attrs, want.attrs, `${label} attrs`);

	if (want.derived)
		A.subset(found.derived, want.derived, `${label} derived`);

	if (want.source != null)
		A.eq(found.source, want.source, `${label} source`);

	if (want.disputed)
		A.subset(found.disputed, want.disputed, `${label} disputed`);

	for (let a in want.attrs_absent ?? [])
		A.ok(found.attrs[a] == null, `${label} omits ${a}`);
}

exit(A.report(`devices/${leaf(dir)}`) ? 0 : 1);
