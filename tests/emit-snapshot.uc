// SPDX-License-Identifier: Apache-2.0
//
// Emits the assembled snapshot for a device fixture as JSON on stdout.
//
//   ucode -R tests/emit-snapshot.uc <fixtures/devices/class> <repo-root>
//
// Exists so the hint tests consume the real assembler's output rather than a
// JavaScript reimplementation of it: a hint asserted against a hand-written
// snapshot would test the fixture, not the page.

'use strict';

import { readfile, lsdir } from 'fs';

let dir  = ARGV[0];
let root = ARGV[1];

if (!dir || !root) {
	warn('usage: emit-snapshot.uc <fixture-dir> <repo-root>\n');
	exit(2);
}

const lib = loadfile(`${root}/l2-info/files/usr/share/l2-info/assemble.uc`)();

function readjson(path) {
	let raw = readfile(path);

	return (raw != null) ? json(raw) : null;
}

let expect = readjson(`${dir}/expect.json`) ?? {};
let readers = [], report = {};

for (let file in sort(lsdir(`${dir}/readers`) ?? [])) {
	if (!match(file, /\.json$/))
		continue;

	let id = replace(file, /\.json$/, '');
	let rec = readjson(`${dir}/readers/${file}`);

	push(readers, {
		id,
		api: rec.api ?? 1,
		describe: rec.describe ?? `recorded reader ${id}`,
		provides: rec.provides,
		cost: rec.cost ?? 'software',
		read: rec.throws
			? function() { die(rec.throws); }
			: function() { return { collections: rec.collections, rows: rec.rows ?? [] }; }
	});

	report[id] = {
		status: 'ok', api: rec.api ?? 1, cost: rec.cost ?? 'software',
		describe: rec.describe ?? `recorded reader ${id}`, provides: rec.provides
	};
}

let ctx = {
	api: 1,
	nl: null,
	fs: { readfile: () => null, access: () => false },
	ubus: { call: (o, m) => (expect.board != null && o == 'system' && m == 'board')
		? expect.board : null }
};

print(sprintf('%J', lib.snapshot(ctx, { readers, report })));
