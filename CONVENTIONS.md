# Conventions

For contributors, human and otherwise. `docs/principles.md` says what the rules
are; this says how to work within them and which checks enforce them.

## Before changing anything

Read `docs/principles.md`, then the decision register. A change that conflicts
with a settled decision needs that decision superseded in
`docs/decisions.md` — in the same change — not worked around in code.

## Documentation ownership

One fact has one home:

| Fact | Home |
|---|---|
| A rule, and how it is enforced | `docs/principles.md` |
| A component, boundary, kernel interface, or cost | `docs/architecture.md` |
| A field, status value, or version rule | `docs/snapshot-format.md` |
| The reader contract, manifest, discovery, or merging | `docs/readers.md` |
| A device class, fixture layout, or redaction rule | `docs/fixtures.md` |
| Why a choice was made, and what it cost | `docs/decisions.md` |

Repetition elsewhere is navigation and must not contradict the owner. If two
documents disagree, the owner wins and the other is the bug.

## Adding a field to the snapshot

1. If it is a value the kernel reported, it goes in `attrs` under the C2
   vocabulary and needs no decision record.
2. If it is a join, a count, or a classification against a published constant,
   it goes in `derived`, gets added to the closed list in
   `docs/snapshot-format.md`, and the decision record states which of the three
   it is.
3. If it is none of those, it is a classification and P2 forbids it. If it
   seems necessary anyway, the argument belongs in a decision record and has to
   overturn D7.

An inference additionally needs a provenance sibling and a visible marker in
the view (D13's pattern).

## Adding a reader

1. One file returning a manifest, at `/usr/share/l2-info/readers/<id>.uc`, with
   `id` equal to the filename stem. Contract: `docs/readers.md`. `read(ctx)`
   uses only the primitives it is handed — it imports no source module, which
   is what keeps fixture replay total (D34).
2. Emit `subject` and `attrs` only. No `derived`, no `source` — the assembler
   owns both, and a reader that derives is the start of a second
   implementation of the same inference.
3. Registered attribute names only. Needing a new one is a decision record and
   a `docs/snapshot-format.md` entry *first*.
4. Declare `provides`, `cost` and `api`. Return a status for every collection
   claimed, and rows only for collections declared `ok`.
5. A source fixture under `fixtures/sources/<id>/`. A reader without one is
   unmergeable.
6. Its package declares every runtime prerequisite as a dependency, so the
   reader cannot be installed without what it needs.

No registration step, no config entry, no core change. If a core change is
needed to make a reader work, that is a bug in the seam.

## Adding a device class

A directory under `fixtures/devices/` with `NOTES.md`, one `readers/<id>.json`
per reader present, and an `expect.json` asserting scope, conflicts, hints
fired, hints silent, and rows — in that order of importance. Its input is
normalised reader output, so it is source-independent and needs no per-source
stub. No harness change; if one is needed, that is a bug in the harness
(D14, D26).

## Adding a hint

In the view only, in `resources/l2-info/hints.js`. Must satisfy H1–H4: not a
field, only displayed values, pure function, and — if its kind is `likely` —
at least two plausible causes. Use kind `note` for anything that explains the
screen rather than asserting a cause (D39). Add its identifier to the relevant
fixtures' `hints.fire` **and** to `hints.silent` in at least one class where it
must not appear. A hint tested only for firing is half tested.

## Mechanical checks

These run in `tests/run.sh` and are the enforcement referred to throughout
`docs/principles.md`. Each exists because prose alone does not hold.

| Check | Enforces |
|---|---|
| Every snapshot collection has a sibling status from the closed vocabulary; every non-`ok` status has a reason | P1 |
| Banned tokens `uplink`, `access`, `beyond`, `at_or_beyond`, `direct` absent as values, field names or enum members | P2, D7 |
| Export of a fixture snapshot contains no `derived` key and no hint text | P3, P5 |
| Render path does not read `attrs` directly | P3 |
| No boolean capability field computed from an empty single dump; `dsa-no-fdb-dump` asserts `indeterminate` | P4 |
| No use of LuCI's `poll` module; `captured_at` present in every snapshot | P6 |
| ACL contains no `write` section; no `localStorage`/`sessionStorage`; no file under `/etc/config` | P7 |
| Fixture directories discovered, not listed | P8, D14 |
| No identifier in `fixtures/` outside the synthetic space or permitted name patterns | D15 |
| Every user-facing string wrapped in `_()`; no untranslated markup text | D17 |
| Every `likely` hint names more than one cause | P5, D39 |
| Recorded fixture readers validate against their own manifests | P9 |
| No reader emits `derived` or `source`; assembler stamps `source` from the manifest | P3, D32 |
| Reader `provides` matches the collections its `read()` returns; rows only on `ok` collections | P9 |
| No reader-id literal anywhere outside `readers/`; `rtnl` has no special case in the core | D28 |
| A reader whose `read()` throws is recorded and does not prevent a snapshot | P9, D28 |
| Every collection unclaimed by a surviving reader is declared with a reason | P9 |
| `scope.conflicts` present in every snapshot, asserted even when empty | D27 |
| Every reader has at least one source fixture | P8, D24 |

A check that cannot be automated is not enforcement; say so plainly rather than
implying coverage. In particular: nothing here proves a real driver behaves as
its fixture claims, nothing here measures cost on real hardware, and a reader's
declared `cost` is a claim no fixture can verify.

## Claims

Do not write that something works on hardware it has not run on. The README's
status section is the honest summary; keep it current, including when that
means saying a thing is untested. A passing fixture suite proves parsing,
joining, declaration and hint logic, and nothing beyond that
(`docs/fixtures.md`, final section).

Where a number appears in documentation — a table size, a threshold, an entry
count — it carries its source. A number without provenance is a guess in
formal dress.

## Style

ucode and JavaScript follow the surrounding OpenWrt and LuCI conventions: tabs,
`'use strict'`, no semicolon-free experiments. Comments explain why, not what,
and a comment recording a kernel behaviour cites the source file it was
verified against.

Commit messages name the principle or decision a change serves where one
applies.
