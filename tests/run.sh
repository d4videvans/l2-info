#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Runs every fixture of both kinds, then the mechanical checks that enforce
# the principles. Fixtures are discovered, never listed: adding a device class
# or a reader means adding a directory (docs/decisions.md D14, D26).
#
#   sh tests/run.sh                          everything
#   sh tests/run.sh devices/sw-bridge-novlan one device fixture
#   sh tests/run.sh sources/rtnl             every case for one reader
#   sh tests/run.sh checks                   the mechanical checks only

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
UCODE=${UCODE:-ucode}
FILTER=${1:-}

# A locally built ucode needs its module directory naming; the ucode shipped on
# a device finds fs and rtnl on the default search path, so UCODE_LIB is a
# development convenience only.
UCARGS="-R"
[ -n "${UCODE_LIB:-}" ] && UCARGS="$UCARGS -L $UCODE_LIB"

fail=0
ran=0

if ! command -v "$UCODE" >/dev/null 2>&1; then
	echo "ucode not found; set UCODE=/path/to/ucode" >&2
	exit 2
fi

run_source() {
	dir=$1
	ran=$((ran + 1))
	# shellcheck disable=SC2086
	"$UCODE" $UCARGS "$ROOT/tests/replay-source.uc" "$dir" "$ROOT" || fail=1
}

run_device() {
	dir=$1
	ran=$((ran + 1))
	# shellcheck disable=SC2086
	"$UCODE" $UCARGS "$ROOT/tests/replay-device.uc" "$dir" "$ROOT" || fail=1
}

run_discovery() {
	dir=$1
	ran=$((ran + 1))
	# shellcheck disable=SC2086
	"$UCODE" $UCARGS "$ROOT/tests/replay-discovery.uc" "$dir" "$ROOT" || fail=1
}

matches() {
	[ -z "$FILTER" ] && return 0
	case "$1" in
		*"$FILTER"*) return 0 ;;
		*) return 1 ;;
	esac
}

if [ "$FILTER" != "checks" ]; then
	echo "source fixtures"
	for d in "$ROOT"/fixtures/sources/*/*/; do
		[ -f "$d/input.json" ] || continue
		rel=${d#"$ROOT"/fixtures/}
		matches "${rel%/}" && run_source "${d%/}"
	done

	echo "discovery fixtures"
	for d in "$ROOT"/fixtures/discovery/*/; do
		[ -d "$d/readers" ] || continue
		rel=${d#"$ROOT"/fixtures/}
		matches "${rel%/}" && run_discovery "${d%/}"
	done

	echo "device fixtures"
	for d in "$ROOT"/fixtures/devices/*/; do
		[ -f "$d/expect.json" ] || continue
		rel=${d#"$ROOT"/fixtures/}
		matches "${rel%/}" && run_device "${d%/}"
	done
fi

# ---------------------------------------------------------------------------
# Mechanical checks. Each one exists because a principle does not hold on
# prose alone; CONVENTIONS.md maps them to the principles they enforce.
# ---------------------------------------------------------------------------

if [ -z "$FILTER" ] || [ "$FILTER" = "checks" ]; then
	echo "mechanical checks"

	check() {
		ran=$((ran + 1))
		if [ "$2" -eq 0 ]; then
			echo "  ok   $1"
		else
			echo "  FAIL $1"
			fail=1
		fi
	}

	BACKEND="$ROOT/l2-info/files"
	VIEW="$ROOT/luci-app-l2-info"
	SRC="$BACKEND $VIEW"

	# P2, D7: no role vocabulary anywhere in shipped code.
	hits=$(grep -rnE '\b(at_or_beyond|"beyond"|'"'"'beyond'"'"'|"uplink"|'"'"'uplink'"'"')' $SRC 2>/dev/null | wc -l)
	check "P2: no classification vocabulary in code" "$([ "$hits" -eq 0 ] && echo 0 || echo 1)"

	# D28: rtnl has no special case; the abstraction is real or deleted.
	hits=$(grep -rn "rtnl" "$BACKEND/usr/share/rpcd" "$BACKEND/usr/share/l2-info/assemble.uc" 2>/dev/null \
		| grep -v "require('rtnl')" | grep -v "ucode-mod-rtnl" | wc -l)
	check "D28: no reader-id literal in the core" "$([ "$hits" -eq 0 ] && echo 0 || echo 1)"

	# P6: nothing polls.
	hits=$(grep -rn "poll\.add\|require *'poll'\|require poll" "$VIEW" 2>/dev/null | wc -l)
	check "P6: view does not poll" "$([ "$hits" -eq 0 ] && echo 0 || echo 1)"

	# P7: read-only, no persistence.
	hits=$(grep -rn "localStorage\|sessionStorage" "$VIEW" 2>/dev/null | wc -l)
	check "P7: no browser persistence" "$([ "$hits" -eq 0 ] && echo 0 || echo 1)"

	hits=$(grep -rn '"write"' "$VIEW/root/usr/share/rpcd/acl.d" 2>/dev/null | wc -l)
	check "P7: ACL grants no write" "$([ "$hits" -eq 0 ] && echo 0 || echo 1)"

	hits=$(find "$BACKEND" "$VIEW" -path '*etc/config*' 2>/dev/null | wc -l)
	check "P7: no uci schema shipped" "$([ "$hits" -eq 0 ] && echo 0 || echo 1)"

	# P8, D24: every reader has at least one source fixture.
	missing=0
	for r in "$BACKEND"/usr/share/l2-info/readers/*.uc; do
		[ -f "$r" ] || continue
		id=$(basename "$r" .uc)
		[ -d "$ROOT/fixtures/sources/$id" ] || missing=1
	done
	check "P8: every reader has source fixtures" "$missing"

	# D15: no identifier outside the synthetic space in fixtures. Synthetic
	# unicast MACs use 02:, aa:, de:ad:; protocol addresses are published
	# constants and are permitted verbatim.
	hits=$(grep -rhoE '\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b' "$ROOT/fixtures" 2>/dev/null \
		| sort -u \
		| grep -vE '^(02|aa|de):' \
		| grep -vE '^(01:00:5e|33:33|01:80:c2|01:00:0c|09:00:2b|ff:ff:ff|00:00:00|01:00:81|01:e0:52)' \
		| wc -l)
	check "D15: fixtures contain no non-synthetic MAC" "$([ "$hits" -eq 0 ] && echo 0 || echo 1)"

	# D17: translation literals must not carry boundary whitespace. LuCI's
	# scanner trims it, so runtime lookup would otherwise miss the POT key.
	I18N_BOUNDARY_RE="_\\(['\"]([[:space:]][^'\"]*|[^'\"]*[[:space:]])['\"]\\)"
	hits=$(grep -rnE "$I18N_BOUNDARY_RE" \
		"$VIEW/htdocs/luci-static/resources" --include='*.js' 2>/dev/null | wc -l)
	check "D17: translation literals have no boundary whitespace" "$([ "$hits" -eq 0 ] && echo 0 || echo 1)"

	# Mutation-probe the guard itself: both leading and trailing boundary
	# whitespace, including multi-word strings, must be detectable.
	probe=$(printf '%s\n' \
		"_('text ')" \
		"_(' text')" \
		"_('two words ')" \
		"_(' leading words')" \
		| grep -Ec "$I18N_BOUNDARY_RE")
	check "D17: boundary-whitespace guard catches leading and trailing mutations" "$([ "$probe" -eq 4 ] && echo 0 || echo 1)"

	# Demo rewrites share one authoritative precondition checker with install.
	if sh "$ROOT/tools/check-screenshot-demo.sh" \
		"$VIEW/htdocs/luci-static/resources/view/l2-info/main.js"; then
		demo_status=0
	else
		demo_status=1
	fi
	check "demo: production rewrite preconditions hold" "$demo_status"

	# Presentation policy is pure and unit tested outside the browser. Node is
	# a development convenience, not a device dependency; CI must provide it.
	if command -v node >/dev/null 2>&1; then
		for t in hints export query diff; do
			ran=$((ran + 1))
			node "$ROOT/tests/$t.test.js" "$ROOT" || fail=1
		done
	else
		echo "  SKIP hint, export, query and diff unit tests (node not present; all unchecked)"
	fi
fi

echo
if [ "$fail" -eq 0 ]; then
	echo "PASS ($ran groups)"
else
	echo "FAIL"
fi

exit $fail
