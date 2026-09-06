#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

MAIN=${1:-}
[ -n "$MAIN" ] && [ -f "$MAIN" ] || {
	echo "check-screenshot-demo: production main.js not found: $MAIN" >&2
	exit 1
}

check_one() {
	label=$1
	pattern=$2
	count=$(grep -F -c "$pattern" "$MAIN" || true)
	[ "$count" -eq 1 ] || {
		echo "check-screenshot-demo: expected exactly one $label in $MAIN; found $count" >&2
		exit 1
	}
}

check_one "l2-info rpc object declaration" "object: 'l2-info'"
check_one "production page title" "_('MAC & VLAN Lookup')"
check_one "production introduction" "Take one read-only snapshot"
check_one "production VLAN legend" "Read from the kernel, not from configuration."
check_one "production filter description" "This does not read the hardware again."
