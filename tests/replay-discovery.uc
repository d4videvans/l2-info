// SPDX-License-Identifier: Apache-2.0
//
// Discovery-fixture harness. Runs the assembler's real discovery against a
// directory of reader files and checks what it loaded and what it rejected.
//
//   ucode -R tests/replay-discovery.uc <fixtures/discovery/case> <repo-root>
//
// The other two harnesses start after discovery, so without this one the
// validation and api-version paths would be unexercised — and those are
// exactly the paths that decide whether an unusable reader is visible or
// silently absent (P9, docs/readers.md §6).

'use strict';

import { readfile } from 'fs';

let dir  = ARGV[0];
let root = ARGV[1];

if (!dir || !root) {
	warn('usage: replay-discovery.uc <fixture-dir> <repo-root>\n');
	exit(2);
}

const A = loadfile(`${root}/tests/lib/assert.uc`)();
const lib = loadfile(`${root}/l2-info/files/usr/share/l2-info/assemble.uc`)();

function leaf(path) {
	let parts = split(path, '/');

	return parts[length(parts) - 1];
}

let raw = readfile(`${dir}/expect.json`);

if (raw == null) {
	warn(`${dir}: missing expect.json\n`);
	exit(2);
}

let expect = json(raw);
let disco = lib.discover(`${dir}/readers`);

let loaded = map(disco.readers, (m) => m.id);

A.eq(sort(loaded), sort(expect.loaded ?? []), 'readers loaded');

if (expect.report)
	A.subset(disco.report, expect.report, 'report');

// A file that does not compile must still be reported. The message comes from
// the interpreter, so it is not asserted verbatim — only that it exists and
// that the reader was skipped rather than dropped.
for (let id in expect.skipped_with_reason ?? []) {
	A.eq(disco.report[id]?.status, 'skipped', `${id} is skipped`);
	A.ok(disco.report[id]?.reason != null && disco.report[id].reason != '',
	     `${id} skip has a reason`);
}

// Nothing may be rejected without a reason, whatever the fixture names.
for (let id, entry in disco.report)
	if (entry.status != 'ok')
		A.ok(entry.reason != null && entry.reason != '',
		     `${id} is ${entry.status} with a reason`);

exit(A.report(`discovery/${leaf(dir)}`) ? 0 : 1);
