# Fixtures and hardware evidence

**Document class:** canonical mechanism for P8. This document owns the fixture
layout, the distinction between replayable fixtures and live hardware evidence,
and the privacy/redaction rules for material that may enter the repository.

A passing fixture is evidence about parsing, merging and presentation logic. It
is not evidence that an unseen physical driver behaves the same way. The
project therefore keeps two kinds of evidence deliberately separate:

- **fixtures** are synthetic/redacted data replayed in tests and CI;
- **live validation** is a read-only run on real OpenWrt hardware, recorded in
  `docs/remediation.md` when it materially changes or validates the design.

CI now runs every fixture, the browser-side unit tests, current LuCI lint/i18n,
and official OpenWrt SDK package builds. There is still no physical switch lab
in CI, so hardware behaviour and read cost remain live-validation questions.

## Three fixture seams

The tree has three independent replay seams because they test different
boundaries:

```text
fixtures/
├── sources/<reader>/<case>/     recorded source input -> reader output
│   ├── NOTES.md
│   ├── input.json
│   └── expect.json
├── devices/<class>/             recorded reader output -> assembled snapshot
│   ├── NOTES.md
│   ├── readers/<id>.json
│   └── expect.json
└── discovery/<case>/            reader files -> discovery result
    ├── NOTES.md
    ├── readers/*.uc
    └── expect.json
```

### Source fixtures

A source fixture is owned by one reader. It feeds recorded source data through
the real reader and asserts the reader's normalised rows and collection
statuses. Examples currently cover successful and empty rtnetlink dumps,
netlink errors, missing rtnl support, generic/AF_BRIDGE link-shape variations,
empty bridges, Realtek/Filogic DSA shapes, and the all-zero FDB placeholder case.

This is where a source-specific parser or kernel-shape rule is tested.

### Device fixtures

A device fixture starts **after** source parsing. Its `readers/*.json` files are
normalised `read()` results, so the same assembler harness works for every
source. These fixtures test:

- collection-status rollup and declarations;
- observation identity and merging;
- conflicts and disputed values;
- derived joins/counts/classifications;
- hint firing and silence through the Node tests.

Current classes include software bridges with and without VLAN filtering,
DSA-style FDB cases, bridge-per-VLAN, one MAC on several ports, duplicate
reported observations, an empty bridge with its own local address, no readers,
a throwing reader, and a reader conflict.

A new hardware arrangement whose source reader already exists should normally
be representable by adding a directory, not by changing the harness.

### Discovery fixtures

Discovery tests start before `read()`. They use real reader files with valid and
invalid manifests to assert loading, manifest validation, API-version handling
and declared skip reasons. Without this seam, source/device replay would leave
the mechanism that decides whether a reader exists effectively untested.

## Expectations assert declarations, not just rows

A useful fixture does not merely say how many rows came out. It asserts the
parts of the contract that make an empty or partial-looking result honest.
A device expectation therefore covers, as applicable:

- collection statuses and important reasons/notes;
- `scope.readers` health/coverage;
- `scope.conflicts`, including the expected empty case;
- significant derived values or negative assertions;
- hints that must fire **and** hints that must remain silent.

The exact expectation schema is enforced by the replay/test code. A deliberately
supplied input field should have a corresponding assertion; otherwise it only
looks like coverage.

## Running the fixtures

Run the complete local suite with:

```sh
sh tests/run.sh
```

Useful focused forms are:

```sh
sh tests/run.sh devices/dsa-no-fdb-dump
sh tests/run.sh sources/rtnl
sh tests/run.sh checks
```

With a locally built host ucode:

```sh
UCODE=~/ucode/build/ucode UCODE_LIB=~/ucode/build sh tests/run.sh
```

When Node is present, `tests/run.sh` also runs the hint, export, query/filter and
diff/scope unit tests. A target device without Node reports those tests as
skipped; CI always supplies Node, so they are mandatory in repository
validation.

The runner discovers fixture directories rather than maintaining a hard-coded
list. Adding a fixture therefore makes it part of the normal test run without a
runner edit.

## Live hardware validation

For a new or unusual device, use the copied-checkout validation helper after the
backend has been installed:

```sh
cd /tmp/l2-info
sh tools/collect-validation.sh
```

By default it creates `/tmp/l2-info-validation-<timestamp>/` containing:

- `ubus call system board` output;
- runtime ucode-module checks;
- one production `l2-info` snapshot;
- a safe rtnetlink link probe;
- optional `bridge -j` link/VLAN/FDB cross-checks when the `bridge` command is
  installed;
- `sh tests/run.sh` output;
- hashes of copied/installed files when `sha256sum` is available.

The collector deliberately performs only one production snapshot because some
switch drivers make an FDB dump a relatively expensive hardware walk. It does
not alter bridge, VLAN, interface or forwarding configuration.

The detailed hardware-validation matrix belongs in `docs/remediation.md` rather
than here.

## Raw validation data is private until reviewed

`tools/collect-validation.sh` records **raw evidence**. Its output can contain
real:

- MAC addresses;
- IP addresses;
- hostnames;
- interface/bridge names;
- board/target/kernel information.

Do **not** attach a raw bundle to a public forum post, issue, pull request or
fixture directory. Copy it off the device for private analysis first.

The LuCI **Download JSON** export also describes a real network and should be
reviewed before public sharing.

## Redaction for committed fixtures

D15 uses positive rewrite rather than a deny-list. Material committed under
`fixtures/` must satisfy these rules:

- MAC addresses are deterministically remapped into the project's documented
  synthetic ranges while preserving relationships within the fixture;
- IP addresses and hostnames are removed when they are merely local annotation;
- conventional structural interface names may remain; unusual site-specific
  names are replaced with synthetic names;
- board, target and kernel may remain because they are the hardware evidence
  the fixture exists to record.

`tests/run.sh` includes a guardrail over committed fixtures for non-synthetic
MAC addresses. Redaction still requires human review: a mechanical MAC check is
not a general privacy scrubber.

## There is no `capture` ubus method yet

D21 records a possible future contributor-oriented capture/redaction facility.
It is **open design work**, not current functionality. In particular this does
not work today:

```text
ubus call l2-info capture
```

If D21 is implemented later, it must preserve both fixture seams established by
D26: raw source-shape evidence for source fixtures and normalised reader output
for device fixtures. Until then, `tools/collect-validation.sh` is the supported
way to gather live evidence, and its output must be treated as raw/private.

## What fixtures and CI do not prove

They do not prove:

- that a driver on hardware we have never seen exposes the same rtnetlink
  shapes;
- that a device's forwarding table is visible rather than merely empty;
- how long a hardware FDB walk will take;
- that arbitrary third-party reader code is sandboxed (readers are trusted
  package code).

Those boundaries are intentional. Passing tests should be described as passing
tests, and live hardware validation as live hardware validation.
