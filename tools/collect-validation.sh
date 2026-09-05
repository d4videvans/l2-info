#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Collect a read-only hardware-validation bundle from an OpenWrt target.
# Designed for copied/archive checkouts: git is neither required nor consulted.
#
# Usage:
#   sh tools/collect-validation.sh [output-directory]
#
# The output is intentionally raw evidence. It may contain real MAC addresses,
# IP addresses and host names. Do not commit it as a fixture without applying
# the D15 redaction rules in docs/fixtures.md.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STAMP=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%Y%m%dT%H%M%S)
OUT=${1:-/tmp/l2-info-validation-$STAMP}

mkdir -p "$OUT" || exit 1

STATUS="$OUT/status.txt"
COMMANDS="$OUT/commands.txt"
: >"$STATUS"
: >"$COMMANDS"

cat >"$OUT/README.txt" <<'EOF'
This directory contains RAW l2-info hardware-validation evidence.

It may contain real MAC addresses, IP addresses and host names. It is suitable
for private transfer for analysis, but MUST NOT be committed as a fixture until
D15 redaction has been applied (see docs/fixtures.md in the source checkout).

The collection script is read-only. It does not change interface, bridge, VLAN
or forwarding state.
EOF

record() {
	printf '%s\n' "$*" >>"$COMMANDS"
}

capture() {
	name=$1
	shift
	stdout="$OUT/$name"
	stderr="$OUT/$name.stderr"

	record "$*"
	"$@" >"$stdout" 2>"$stderr"
	rc=$?

	if [ ! -s "$stderr" ]; then
		rm -f "$stderr"
	fi

	if [ "$rc" -eq 0 ]; then
		printf 'ok   %s\n' "$name" >>"$STATUS"
	else
		printf 'FAIL %s (exit %s)\n' "$name" "$rc" >>"$STATUS"
	fi

	return "$rc"
}

printf 'l2-info validation capture\n' >"$OUT/meta.txt"
printf 'captured_utc=%s\n' "$STAMP" >>"$OUT/meta.txt"
printf 'checkout_root=%s\n' "$ROOT" >>"$OUT/meta.txt"
printf 'git_required=no\n' >>"$OUT/meta.txt"

if command -v ubus >/dev/null 2>&1; then
	capture board.json ubus call system board || true
	# One production snapshot. On switch hardware this may perform the expensive
	# hardware FDB walk, so deliberately do not call it a second time.
	capture snapshot.json ubus call l2-info snapshot || true
else
	printf 'SKIP board.json (ubus not found)\n' >>"$STATUS"
	printf 'SKIP snapshot.json (ubus not found)\n' >>"$STATUS"
fi

if command -v ucode >/dev/null 2>&1 && [ -f "$ROOT/tools/probe-rtnl-links.uc" ]; then
	capture rtnl-links.json ucode "$ROOT/tools/probe-rtnl-links.uc" || true
else
	printf 'SKIP rtnl-links.json (ucode or probe script not found)\n' >>"$STATUS"
fi

if command -v bridge >/dev/null 2>&1; then
	capture bridge-link.json bridge -j link show || true
	capture bridge-vlan.json bridge -j vlan show || true
	capture bridge-fdb.json bridge -j fdb show || true
else
	printf 'SKIP bridge cross-checks (bridge command not installed)\n' >>"$STATUS"
fi

if [ -f "$ROOT/tests/run.sh" ]; then
	record "sh $ROOT/tests/run.sh"
	sh "$ROOT/tests/run.sh" >"$OUT/tests.txt" 2>"$OUT/tests.stderr"
	rc=$?
	if [ ! -s "$OUT/tests.stderr" ]; then
		rm -f "$OUT/tests.stderr"
	fi
	if [ "$rc" -eq 0 ]; then
		printf 'ok   tests.txt\n' >>"$STATUS"
	else
		printf 'FAIL tests.txt (exit %s)\n' "$rc" >>"$STATUS"
	fi
else
	printf 'SKIP tests.txt (tests/run.sh not found)\n' >>"$STATUS"
fi

printf '\nValidation bundle: %s\n' "$OUT"
printf 'Copy that directory off the device (for example with WinSCP).\n'
printf 'Review README.txt before committing any captured data.\n'

cat "$STATUS"
