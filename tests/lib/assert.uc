// SPDX-License-Identifier: Apache-2.0
// Assertion helpers shared by both fixture harnesses.

'use strict';

let failures = [];
let checks = 0;

function ok(cond, what) {
	checks++;

	if (!cond)
		push(failures, what);

	return !!cond;
}

function eq(got, want, what) {
	checks++;

	let a = sprintf('%J', got), b = sprintf('%J', want);

	if (a != b)
		push(failures, `${what}\n      want: ${b}\n      got:  ${a}`);

	return a == b;
}

function report(label) {
	if (length(failures) == 0) {
		printf('  ok   %s (%d checks)\n', label, checks);
		checks = 0;
		return true;
	}

	printf('  FAIL %s\n', label);

	for (let f in failures)
		printf('       - %s\n', f);

	failures = [];
	checks = 0;

	return false;
}

// Walk an expectation object against a value, comparing only the keys the
// expectation names. A fixture asserts what it cares about; it does not have
// to restate the whole snapshot.
function subset(got, want, path) {
	path ??= '';

	if (type(want) == 'object' && type(got) == 'object') {
		let all = true;

		for (let k, v in want)
			if (!subset(got[k], v, path ? `${path}.${k}` : k))
				all = false;

		return all;
	}

	return eq(got, want, `${path} mismatch`);
}

return { ok, eq, report, subset };
