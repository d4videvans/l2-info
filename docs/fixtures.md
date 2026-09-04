# Fixtures

**Document class:** canonical mechanism for P8. This document owns the device
class list, the on-disk layout, and the capture and redaction path.

Fixtures are the *only* mechanism by which this project's device-agnosticism is
more than a claim. There is no CI on a LuCI app and no lab of switches here, so
a replayable capture per L2 arrangement, asserting on declarations rather than
only on rows, is what makes "handles that case" checkable.

## Three seams

Fixtures sit at two different boundaries because they test two different
things, and conflating them is why "easy to add a class later" usually turns
out to be false (`docs/decisions.md` D26).

```
fixtures/
├── sources/<reader>/<case>/     raw source input  →  that reader's output
│   ├── NOTES.md
│   ├── input.json               whatever the source emits, in its own shape
│   └── expect.json              the reader's normalised rows and statuses
├── devices/<class>/             normalised reader output  →  snapshot
│   ├── NOTES.md
│   ├── readers/<id>.json        one file per reader present, its read() result
│   └── expect.json              scope, conflicts, hints, derived values, rows
└── discovery/<case>/            a directory of reader files  →  what loaded
    ├── NOTES.md
    ├── readers/*.uc             valid and invalid manifests
    └── expect.json              which loaded, and why each rejection happened
```

**Source fixtures** are reader-specific and owned by whoever wrote the reader.
They test parsing and status derivation: given this raw netlink dump, or this
`arl_table` text, does the reader produce these rows and declare these
statuses.

**Discovery fixtures** are a directory of real reader files, valid and invalid.
They exist because the other two harnesses start *after* discovery, so without
them manifest validation and api-version rejection would be untested — and
those are the paths that decide whether an unusable reader is visible or
silently absent.

**Device fixtures** are source-independent. Their input is normalised reader
output, so a swconfig device and a DSA device produce fixtures in *the same
shape* for *the same harness*, with no per-source stub. They test the
assembler: merging, scope declaration, derivation, hint firing.

The second property is the important one. It means a device class can be
contributed for hardware whose reader already exists without touching reader
code, and that adding a reader does not require touching the device harness.

A missing input means that read is absent, which is itself a case worth
testing — a device fixture with no `readers/lldp.json` asserts that
LLDP-provided attributes are declared unclaimed rather than rendered blank.
A device fixture may deliberately include a reader whose result is an
exception, asserting that one failing reader does not prevent a snapshot
(`docs/readers.md` §5).

## Expectations assert declarations first

```json
{
  "scope": {
    "fdb": { "status": "indeterminate" },
    "bridge_vlans": { "status": "ok" },
    "readers": { "rtnl": { "status": "ok" } },
    "conflicts": []
  },
  "hints": {
    "fire": ["fdb_empty_indeterminate"],
    "silent": ["no_vlan_filtering"]
  },
  "rows": {
    "fdb_count": 0,
    "ports_count": 9,
    "vlan_source_pvid_count": 0
  }
}
```

The ordering is deliberate. A fixture whose expectations name only `rows` fails
as incomplete, because row parsing is the part least likely to be wrong and
scope declaration is the part this project exists to get right. `hints.silent`
matters as much as `hints.fire`: a hint firing on the wrong class is the P5
failure mode that a fire-only assertion cannot catch. `conflicts` is asserted
even when empty, because an unexpected conflict and an unnoticed one are the
same bug.

## Starting device classes

Five, from `docs/architecture.md`. A starting set, not a closed one.

| Directory | Class | Asserts, distinctively |
|---|---|---|
| `dsa-switch-fdb` | DSA, driver reports its hardware table | `entries_switch_reported` non-zero; bridge joined from links, since hardware rows carry no master |
| `dsa-no-fdb-dump` | DSA, driver omits `port_fdb_dump` | `fdb.status = indeterminate`, **not** `unavailable`, and no boolean capability claim (P4) |
| `sw-bridge-vlan` | software bridge, VLAN filtering on | VLAN ids present in rows; PVID fallback exercised on untagged arrivals |
| `sw-bridge-novlan` | software bridge, filtering off | `bridge_vlans.status = not_applicable` with reason; every `vlan_source` null; VLAN column not rendered as empty |
| `bridge-per-vlan` | one bridge per VLAN, netdev-layer tagging | per-port VLAN data present but content-free; not presented as segment membership |

A sixth class is a directory and a `NOTES.md`. A class that needs a harness
change is a bug in the harness.

Two further device fixtures exist for the reader mechanism itself rather than
for hardware: one with no readers at all, asserting that every collection is
declared `not_applicable` with a reason naming the absence (P9); and one whose
reader throws, asserting the snapshot still assembles.

## Capture

Coverage cannot grow past the hardware in one person's house unless people can
contribute captures from devices neither maintainer owns — which upstreaming
makes a certainty rather than a hope. So the backend can emit its own raw
netlink responses in the fixture layout:

```sh
ubus call l2-info capture > l2-info-fixture.json
```

One command on the device, one file to send. The output carries **both** seams:
each reader's raw source input, and that reader's normalised output. Raw input
keeps the source fixture testing parsing rather than freezing whatever the
parser did on the day; normalised output gives the device fixture its input and
lets the pair be cross-checked against each other (`docs/decisions.md` D26).

This is the one place a second ubus method is justified, and it needs a
decision record before it is built (`docs/decisions.md` D21, open). The
alternative — asking contributors to run several `ubus`/`ip` commands and paste
the output — produces inconsistent captures and gets the redaction wrong.

## Redaction

A real capture is full of real MAC addresses, hostnames and IPs. Contributors
will send them to a public repository. The related fleet project's experience
here is instructive: its first anonymiser was a deny-list, and a deny-list can
only catch what it already knows about — it missed 574 long-form DHCP
client-ids because nobody had thought of that shape.

So redaction is a **positive rewrite**, not a filter:

- **MACs** are mapped deterministically into a documented synthetic range. The
  mapping is stable within a capture, so a MAC appearing on two ports still
  appears on two ports and the topology relationships that make the fixture
  interesting survive intact.
- **Hostnames and IPs are dropped**, not remapped. They are annotation, not
  structure, and nothing in a fixture's value depends on them. Attempting to
  remap them is how you end up needing a deny-list.
- **Bridge and interface names** are kept — `br-lan`, `lan5`, `eth0.10` are
  conventional and structural. A name that is not conventional (`br-Rico`) is
  site information; names are matched against a permitted pattern and replaced
  with an indexed synthetic name when they do not match.
- **Board, target and kernel are kept.** They are product facts, not site
  facts, and they are the whole point of the fixture.

Rewriting happens in the capture command on the device, before anything is
written, so an unredacted capture never exists as a file to be sent by
accident.

The guardrail is that a fixture directory must contain no identifier outside
the synthetic space and the permitted-name patterns, checked by the test runner
over every fixture rather than at capture time — because the check has to hold
for fixtures contributed by people who did not run the current version of the
capture command.

## Running

```sh
tests/run.sh                          # every fixture, plus the checks
tests/run.sh devices/dsa-no-fdb-dump
tests/run.sh sources/rtnl
tests/run.sh checks                   # mechanical checks only

# with a locally built ucode rather than a device's:
UCODE=~/ucode/build/ucode UCODE_LIB=~/ucode/build tests/run.sh
```

`replay-source.uc` builds a reader context from the fixture and runs that
reader unmodified; because readers are handed their primitives rather than
importing them (D34), stubbing needs no hook in the reader itself.
`replay-device.uc` substitutes recorded `read()` results for discovery and runs
the assembler unmodified. `replay-discovery.uc` runs the real discovery against
a directory of reader files.

Hints live in the view, so they are not reachable from the ucode harnesses.
`hints.test.js` tests them against the same device fixtures, assembling each
through `emit-snapshot.uc` so the rules see the real assembler's output rather
than a hand-written snapshot. Node is a development convenience: when it is
absent the runner reports the hint checks unrun rather than passed.

Both require that every read sits behind a single seam: one wrapper inside each
reader, and the discovery call inside the assembler. Stubbing is then total,
and no test can accidentally reach a real kernel (`docs/decisions.md` D18).

## What a fixture cannot do

Fixtures prove parsing, joining, declaration and hint logic. They cannot prove
that a real driver behaves as its fixture claims, and they say nothing about
cost — the register-walk expense described in `docs/architecture.md` is
invisible to a replay, and a reader's declared `cost` is a claim no fixture can
check. Both need real hardware, and both should be recorded as such rather than
implied by a passing test suite.
