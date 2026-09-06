/* SPDX-License-Identifier: Apache-2.0 */
/* Export shape test.
 *
 * The export is the file a user keeps and another tool ingests, so it is the
 * one artefact whose shape has to be exactly the documented format: reported
 * facts and declared scope, no derivation (P3), no interpretation (P5), and
 * nothing the view happened to attach to its own copy.
 *
 * That last one is why this test exists. The first version of `exportable()`
 * copied the snapshot and deleted `derived`, which let the view's receive
 * timestamp into the file — a denylist removing only what it already knows
 * about (D45).
 *
 * `exportable()` lives inside the view module, so it is extracted here the
 * same way the hint rules are: by evaluating the file with LuCI shimmed.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = process.argv[2] || path.join(__dirname, '..');
const VIEW = path.join(root, 'luci-app-l2-info/htdocs/luci-static/resources/view/l2-info/main.js');
const FIXTURES = path.join(root, 'fixtures/devices');

/* Registered top-level keys, from docs/snapshot-format.md. */
const ALLOWED = new Set([
	'format', 'version', 'captured_at', 'duration_ms', 'cost', 'device', 'scope',
	'bridges', 'ports', 'fdb', 'neighbours', 'names'
]);

const ROW_KEYS = new Set([ 'subject', 'attrs', 'source', 'disputed' ]);

/* Pull exportable() out of the view without a browser.
 *
 * This shim intentionally depends on LuCI's current one-line `require ...;`
 * wrapper shape. If that wrapper/list changes, update this loader rather than
 * treating the resulting parse failure as an export-policy regression.
 */
function loadExportable() {
	const src = fs.readFileSync(VIEW, 'utf8')
		.replace(/^\s*'use strict';\s*$/m, '')
		.replace(/^\s*'require [^']*';\s*$/gm, '')
		.replace(/^return view\.extend\(/m, 'var __view = (');

	const fn = new Function(
		'view', 'rpc', 'ui', 'dom', 'hints', 'E', '_', 'cbi_update_table',
		`${src}\nreturn exportable;`
	);

	const stub = () => ({});

	return fn(
		{ extend: stub }, { declare: stub }, { addNotification: stub, createHandlerFn: stub },
		{ content: stub }, { evaluate: () => [] }, stub, (s) => s, stub
	);
}

function snapshotFor(dir) {
	const ucode = process.env.UCODE || 'ucode';
	const args = [ '-R' ];

	if (process.env.UCODE_LIB)
		args.push('-L', process.env.UCODE_LIB);

	args.push(path.join(root, 'tests/emit-snapshot.uc'), dir, root);

	return JSON.parse(execFileSync(ucode, args, { encoding: 'utf8' }));
}

const exportable = loadExportable();

let failures = 0, ran = 0;

for (const name of fs.readdirSync(FIXTURES).sort()) {
	const dir = path.join(FIXTURES, name);

	if (!fs.existsSync(path.join(dir, 'expect.json')))
		continue;

	ran++;

	const snap = snapshotFor(dir);

	/* Anything the view might have attached to its own copy must not survive. */
	snap._t = Date.now();
	snap._scratch = { note: 'view internal' };

	const out = exportable(snap);
	const problems = [];

	for (const k of Object.keys(out))
		if (!ALLOWED.has(k))
			problems.push(`unregistered top-level key '${k}'`);

	if (out.captured_at === undefined)
		problems.push('captured_at missing');

	if (!out.scope || out.scope.conflicts === undefined)
		problems.push('scope.conflicts missing');

	for (const c of [ 'bridges', 'ports', 'fdb', 'neighbours', 'names' ]) {
		for (const e of out[c] || []) {
			if (e.derived !== undefined)
				problems.push(`${c} row carries derived`);

			for (const k of Object.keys(e))
				if (!ROW_KEYS.has(k))
					problems.push(`${c} row carries unregistered key '${k}'`);
		}
	}

	if (problems.length) {
		console.log(`  FAIL export/${name}`);
		[ ...new Set(problems) ].forEach((p) => console.log(`       - ${p}`));
		failures++;
	} else {
		console.log(`  ok   export/${name}`);
	}
}

if (!ran)
	console.log('  SKIP export tests (no device fixtures)');

process.exit(failures ? 1 : 0);