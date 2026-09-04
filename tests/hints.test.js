/* SPDX-License-Identifier: Apache-2.0 */
/* Hint unit tests.
 *
 * Hints live in the view (P5), so they are not reachable from the ucode
 * harnesses. They are pure functions of displayed values (H4), so they are
 * tested here against the same device fixtures the assembler is tested with:
 * the fixture's recorded reader output is assembled into the shape the page
 * receives, and each fixture declares which hints must fire and which must
 * stay silent.
 *
 * A hint tested only for firing is half tested — a hint that fires on the
 * wrong device is the P5 failure a fire-only assertion cannot catch — so
 * `silent` is asserted too.
 *
 * Node is a development convenience, never a device dependency. When it is
 * absent tests/run.sh reports these as unrun rather than as passed.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = process.argv[2] || path.join(__dirname, '..');
const HINTS = path.join(root, 'luci-app-l2-info/htdocs/luci-static/resources/l2-info/hints.js');
const FIXTURES = path.join(root, 'fixtures/devices');

/* Minimal LuCI shims: enough to load a baseclass module outside a browser. */
function loadHints() {
	const src = fs.readFileSync(HINTS, 'utf8')
		.replace(/^\s*'use strict';\s*$/m, '')
		.replace(/^\s*'require [^']*';\s*$/gm, '');

	const baseclass = { extend: (o) => o };
	const _ = (s) => Object.assign(String(s), {});

	String.prototype.format = function () {
		const args = arguments;
		let i = 0;
		return this.replace(/%[sd]/g, () => String(args[i++]));
	};

	const fn = new Function('baseclass', '_', `${src}`);

	return fn(baseclass, (s) => s);
}

/* Assemble a fixture the same way the backend does, by running the real
 * assembler through the device harness rather than reimplementing it here. */
function snapshotFor(dir) {
	const ucode = process.env.UCODE || 'ucode';
	const args = [ '-R' ];

	if (process.env.UCODE_LIB)
		args.push('-L', process.env.UCODE_LIB);

	args.push(path.join(root, 'tests/emit-snapshot.uc'), dir, root);

	return JSON.parse(execFileSync(ucode, args, { encoding: 'utf8' }));
}

const hints = loadHints();

let failures = 0, checks = 0, ran = 0;

for (const name of fs.readdirSync(FIXTURES).sort()) {
	const dir = path.join(FIXTURES, name);
	const expectPath = path.join(dir, 'expect.json');

	if (!fs.existsSync(expectPath))
		continue;

	const expect = JSON.parse(fs.readFileSync(expectPath, 'utf8'));

	if (!expect.hints)
		continue;

	ran++;

	let snap;

	try {
		snap = snapshotFor(dir);
	} catch (e) {
		console.log(`  FAIL hints/${name}: could not assemble fixture: ${e.message}`);
		failures++;
		continue;
	}

	/* The page shows every unicast row by default, which is what the hint
	 * rules see (H2). */
	const rows = (snap.fdb || []).filter((r) => r.derived.mac_class === 'unicast');
	const view = { rows, port: expect.hints.port || '' };

	const fired = hints.evaluate(snap, view).map((h) => h.id);
	const problems = [];

	for (const id of expect.hints.fire || []) {
		checks++;
		if (!fired.includes(id))
			problems.push(`expected hint ${id} to fire`);
	}

	for (const id of expect.hints.silent || []) {
		checks++;
		if (fired.includes(id))
			problems.push(`expected hint ${id} to stay silent`);
	}

	/* Every 'likely' hint must offer the reader more than one explanation. */
	for (const h of hints.evaluate(snap, view)) {
		if (h.kind !== 'likely')
			continue;

		checks++;

		const alternatives = /\bor\b/.test(h.text);

		if (!alternatives)
			problems.push(`H3: likely hint ${h.id} names only one cause`);
	}

	if (problems.length) {
		console.log(`  FAIL hints/${name}`);
		problems.forEach((p) => console.log(`       - ${p}`));
		failures++;
	} else {
		console.log(`  ok   hints/${name} (${fired.length} fired)`);
	}
}

if (!ran)
	console.log('  SKIP hint tests (no fixture declares hints)');

process.exit(failures ? 1 : 0);
