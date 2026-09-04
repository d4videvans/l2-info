// SPDX-License-Identifier: Apache-2.0
//
// Source-fixture harness. Stubs one reader's source primitives from a fixture
// directory and runs that reader unmodified, then compares its normalised
// output against expect.json.
//
//   ucode -R tests/replay-source.uc <fixtures/sources/rtnl/case> <readers-dir>
//
// The reader binds nothing at load time and imports no source module: it is
// handed its primitives by the assembler (docs/decisions.md D34). That is what
// makes stubbing total here, with no test hook anywhere in the reader.

'use strict';

import { readfile, access } from 'fs';

// Paths come from the runner rather than being discovered here: the harness
// should be runnable from any working directory.
let dir  = ARGV[0];
let root = ARGV[1];

if (!dir || !root) {
	warn('usage: replay-source.uc <fixture-dir> <repo-root>\n');
	exit(2);
}

const A = loadfile(`${root}/tests/lib/assert.uc`)();
const READERS = `${root}/l2-info/files/usr/share/l2-info/readers`;
const LIB = `${root}/l2-info/files/usr/share/l2-info/assemble.uc`;

function leaf(path) {
	let parts = split(path, '/');

	return parts[length(parts) - 1];
}

function readjson(path) {
	let raw = readfile(path);

	return (raw != null) ? json(raw) : null;
}

// Real kernel constant values, so a fixture records what the kernel actually
// emits rather than what a stub happens to agree with.
const NL = {
	RTM_GETLINK: 18, RTM_GETNEIGH: 30, NLM_F_DUMP: 0x300,
	AF_BRIDGE: 7, AF_INET: 2, AF_INET6: 10,
	NUD_INCOMPLETE: 0x01, NUD_REACHABLE: 0x02, NUD_STALE: 0x04,
	NUD_NOARP: 0x40, NUD_PERMANENT: 0x80,
	NTF_SELF: 0x02, NTF_MASTER: 0x04, NTF_EXT_LEARNED: 0x10,
	NTF_OFFLOADED: 0x20, NTF_STICKY: 0x40, NTF_ROUTER: 0x80
};

// Fixture input keys, so a fixture is readable as a description of a device
// rather than as a sequence of syscalls. D46 makes the two GETLINK views
// separate inputs: generic links establish device kind, AF_BRIDGE establishes
// membership and VLAN state.
function request_key(cmd, payload) {
	if (cmd == NL.RTM_GETLINK) {
		if (payload.family == NL.AF_BRIDGE)
			return 'link_bridge';

		return 'link_generic';
	}

	if (cmd == NL.RTM_GETNEIGH) {
		if (payload.family == NL.AF_BRIDGE) return 'neigh_bridge';
		if (payload.family == NL.AF_INET)   return 'neigh_inet';
		if (payload.family == NL.AF_INET6)  return 'neigh_inet6';
	}

	return sprintf('unknown_%d', cmd);
}

function make_stub(input) {
	let last_error = null;

	let nl = input.no_rtnl ? null : {
		const: NL,

		request: function(cmd, flags, payload) {
			let key = request_key(cmd, payload);
			let entry = input[key];

			last_error = null;

			if (entry == null)
				return [];

			if (entry.error != null) {
				last_error = entry.error;
				return null;
			}

			return entry.rows ?? [];
		},

		error: () => {
			let e = last_error;
			last_error = null;
			return e;
		}
	};

	let files = input.files ?? {};

	return {
		api: 1,
		nl,
		fs: {
			readfile: (path) => (files[path] != null) ? files[path] : null,
			access: (path, mode) => (files[path] != null)
		},
		ubus: {
			call: (object, method) => (input.ubus ?? {})[`${object}.${method}`] ?? null
		}
	};
}

let input = readjson(`${dir}/input.json`);
let expect = readjson(`${dir}/expect.json`);

if (input == null || expect == null) {
	warn(`${dir}: missing input.json or expect.json\n`);
	exit(2);
}

// The assembler library is loaded for its validators and its collection
// mapping: a source fixture proves the reader honours the same contract the
// assembler will hold it to, rather than a restatement of it.
let lib = loadfile(LIB)();

let id = expect.reader ?? 'rtnl';
let manifest = loadfile(`${READERS}/${id}.uc`)();
let result = manifest.read(make_stub(input));

A.eq(lib.validate_manifest(manifest, id), null, 'manifest is valid');
A.eq(lib.validate_result(manifest, result), null, 'read() honours the contract');

if (expect.collections)
	A.subset(result.collections, expect.collections, 'collections');

if (expect.row_counts) {
	let counts = {};

	// Seed every collection the reader claimed, so "declared and empty" is
	// distinguishable from "not claimed" in an expectation.
	for (let c in manifest.provides)
		counts[c] = 0;

	for (let r in result.rows ?? []) {
		let c = lib.collection_of(r);
		counts[c] = (counts[c] ?? 0) + 1;
	}

	A.subset(counts, expect.row_counts, 'row_counts');
}

for (let want in expect.rows ?? []) {
	let found = null;

	for (let r in result.rows ?? []) {
		if (sprintf('%J', r.subject) != sprintf('%J', want.subject))
			continue;

		// A subject legitimately appears in more than one collection (a MAC
		// is an FDB subject and a neighbour subject) and more than once
		// within one (a MAC on two ports), so an expectation may name the
		// collection and any attribute as a discriminator.
		if (want.collection != null && lib.collection_of(r) != want.collection)
			continue;

		if (want.where != null) {
			let mismatch = false;

			for (let k, v in want.where)
				if (sprintf('%J', r.attrs[k]) != sprintf('%J', v))
					mismatch = true;

			if (mismatch)
				continue;
		}

		found = r;
		break;
	}

	// An expectation may assert a row is *not* produced: the reader dropping
	// something is as much a behaviour as emitting it.
	if (want.absent_row) {
		A.ok(found == null, `row ${sprintf('%J', want.subject)} not emitted`);
		continue;
	}

	if (!A.ok(found != null, `row ${sprintf('%J', want.subject)} present`))
		continue;

	A.subset(found.attrs, want.attrs ?? {}, `row ${sprintf('%J', want.subject)} attrs`);

	for (let a in want.absent ?? [])
		A.ok(found.attrs[a] == null, `row ${sprintf('%J', want.subject)} omits ${a}`);
}

exit(A.report(`sources/${id}/${leaf(dir)}`) ? 0 : 1);
