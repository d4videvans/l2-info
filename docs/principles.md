# Principles

**Document class:** normative. These are design rules, not aspirations. A change
that weakens or conflicts with one needs a decision record rather than a local
exception in code.

Ordering reflects how strongly each rule constrains the rest of the design.

## P1 — No field is empty for two different reasons

An empty result must say why it is empty. Every collection therefore has an
adjacent status in `scope`: `ok`, `unavailable`, `not_applicable` or
`indeterminate`, with a reason for every non-`ok` status.

This prevents the UI or another consumer from confusing "nothing observed",
"could not read", "does not apply" and "one sample cannot tell".

**Mechanical evidence:** snapshot/fixture validation checks the status
vocabulary and reasons; device fixtures assert declarations as well as rows.

## P2 — Report, don't classify

The data layer reports observations, counts, sets and reported topology. It does
not assign semantic port/network roles such as uplink/access/downstream based on
thresholds or guesses.

A single OpenWrt device can report that three MAC addresses were observed on a
port. It cannot, from that fact alone, truthfully decide whether the cause is an
unmanaged switch, a hypervisor, a phone passthrough, a bridge loop or something
else.

The one explicit exception is P3's necessary VLAN inference, with provenance.
Interpretive help belongs in P5's presentation hints.

**Mechanical evidence:** banned classification vocabulary is checked in shipped
code; derived fields are a closed list in `docs/snapshot-format.md`.

## P3 — Provenance travels with the value

Reported facts and derived facts are separate. Readers emit only `subject` and
`attrs`; the assembler stamps `source` and computes `derived` once over merged
evidence.

The necessary PVID fallback for an untagged FDB observation carries both the
resolved VLAN and `vlan_source`, so a consumer can distinguish a kernel-reported
VLAN from one inferred from port PVID.

The LuCI JSON export is built from an allowlist and deliberately omits
`derived`/hints, leaving reported facts, declared scope and source attribution.

**Mechanical evidence:** reader validation rejects reader-emitted
`derived`/`source`; export tests assert the projection; derived vocabulary is
closed.

## P4 — Absence is declared, never inferred from one sample

A single empty read does not prove a capability or table is absent. If an empty
sample cannot distinguish a genuinely idle device from an observation gap, the
status is `indeterminate`.

This is why a successful zero-row FDB dump is not turned into a boolean
"hardware FDB: no" claim. Positive facts such as bridge VLAN-filtering state are
read directly from the relevant kernel state rather than inferred from missing
rows.

**Mechanical evidence:** empty-FDB/source fixtures pin `indeterminate`; no
boolean capability field is derived from a zero-row dump.

## P5 — Interpretation is presentation

The UI may explain what evidence could mean. The snapshot may not turn that
interpretation into a data field.

Hints follow four rules:

- **H1:** removing every hint leaves the underlying data complete/correct;
- **H2:** a hint uses only values the user can see;
- **H3:** a causal `likely` hint names at least two plausible causes; a `note`
  may simply explain what is on screen;
- **H4:** hint logic is pure/testable.

A hint must also be relevant to the rows on which it fires. Local device
addresses, for example, must not receive remote-host fan-out explanations.

**Mechanical evidence:** Node tests exercise hint firing/silence against fixture
snapshots; hint text is absent from exports.

## P6 — Freshness is explicit

A snapshot is read only when the user asks for one. There is no background data
polling or auto-refresh.

The snapshot carries `captured_at` and measured `duration_ms`; LuCI shows both
the timestamp and a continuously aging label. The timer only updates the age
text — it does not read the device again.

**Mechanical evidence:** shipped LuCI code is checked for the poll module;
fixtures/snapshot validation require capture time.

## P7 — Read-only and stateless

The diagnostic does not change bridge, VLAN, interface or forwarding state. It
ships no UCI configuration, no daemon of its own, no persistent snapshot cache,
and the LuCI ACL grants no write method.

Current/previous snapshots live in browser memory only and disappear on
navigation/reload. Users who need a retained artefact explicitly download JSON.

Readers are trusted installed code. This principle is a design/conformance rule,
not a claim that arbitrary third-party reader code is sandboxed.

**Mechanical evidence:** ACL write sections, UCI config files and browser
storage APIs are mechanically checked. Runtime hardware validation checks the
actual installed path.

## P8 — Device coverage is evidence, not prose

A claim about an L2 arrangement should be backed by replayable fixtures and,
where it depends on physical driver behaviour or cost, by recorded live hardware
validation.

The repository has three fixture seams — source, discovery and device — because
parsing, reader loading and assembled-device behaviour are distinct contracts.
CI runs those fixtures plus browser-side unit tests, current LuCI lint/i18n and
an official OpenWrt SDK build.

What CI **cannot** provide is a physical switch lab. It cannot prove how an
unseen driver behaves or how long its hardware read takes. Those remain live
validation and are recorded separately rather than implied by green CI.

**Mechanical evidence:** fixture directories are discovered automatically;
every shipped reader needs source fixtures; CI makes the complete repository
suite mandatory.

## P9 — A source declares what it can see

Every reader manifest declares the collections it can provide. `read(ctx)` then
returns a status for every claimed collection, and rows only for collections
that are `ok`.

The assembler derives collection absence from the surviving reader manifests.
If no reader provides a registered collection, it is explicitly
`not_applicable` with a reason naming that fact rather than rendered as a blank
column.

A load/manifest/API failure is represented under `scope.readers`. A throwing
reader is isolated and does not prevent other readers from producing a
snapshot. There is no reader-id special case or priority order in the core.

**Mechanical evidence:** manifest/result validation, discovery fixtures,
throwing-reader/no-reader fixtures and grep checks enforce the seam.

## Precedence

Where principles appear to conflict, the earlier-numbered rule wins until a
new decision explicitly changes the design.

The important recurring tension is usefulness versus inference: P2 keeps the
data factual; P5 recovers human explanation in the view without weakening the
snapshot contract.
