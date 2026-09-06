# Conventions

For contributors, human and otherwise. `docs/principles.md` says what the rules
are; this document says where facts live and how changes are checked.

## Before changing behaviour

Read `docs/principles.md` and `docs/decisions.md`. A change conflicting with a
settled decision needs an explicit new/superseding decision in the same change,
not a hidden exception in code.

Detailed historical rationale through D49 is preserved in
`docs/decisions-history.md`.

## Documentation ownership

One fact has one current home:

| Fact | Home |
|---|---|
| user/test installation, update, uninstall, troubleshooting, privacy | `docs/getting-started.md` |
| normative design rule/enforcement boundary | `docs/principles.md` |
| component, data flow, kernel/source interface or cost model | `docs/architecture.md` |
| snapshot field/status/version contract | `docs/snapshot-format.md` |
| reader manifest/discovery/read/merge contract | `docs/readers.md` |
| fixture layout, live-evidence boundary and redaction | `docs/fixtures.md` |
| current architectural/project decisions | `docs/decisions.md` |
| original detailed decision evidence/history | `docs/decisions-history.md` |
| remediation/readiness/hardware matrix | `docs/remediation.md` |
| contribution workflow | `CONTRIBUTING.md` |

README is the front door and navigation/summary, not an independent contract.
Where a repeated statement disagrees with its owner, the repeated statement is
the bug.

## Adding/changing snapshot vocabulary

1. **Using an existing registered reported attribute** needs no new vocabulary
   decision; emit it in `attrs` only when the source actually reports it.
2. **Adding a new attribute/collection/subject kind** changes the closed
   contract: decision + `docs/snapshot-format.md` first, then implementation and
   fixtures.
3. **Adding a derived value** requires it to fit the permitted categories in
   the snapshot contract (join, count, published-constant classification, or an
   explicitly approved inference) and requires a decision update.
4. A new inference carries explicit provenance and visible UI distinction.

Do not smuggle classification into a field because it is convenient to render.

## Adding a reader

Readers are trusted package code loaded in rpcd. `read(ctx)` is the conformance
and testability seam, not a security boundary.

- file: `/usr/share/l2-info/readers/<id>.uc`;
- manifest id equals filename stem;
- use supplied `ctx` source primitives;
- emit registered `subject`/`attrs` only;
- declare `provides`, `cost`, `api` and return status for every claimed
  collection;
- package every runtime prerequisite as a dependency;
- add source fixtures and relevant device interaction fixtures.

No registration/config/core special case should be required.

## Adding a device fixture

Create `fixtures/devices/<class>/` with `NOTES.md`, normalised reader result
files and `expect.json`. Assert declaration/conflict/hint behaviour as well as
interesting rows/derived values. The runner discovers the directory.

Live hardware evidence and fixture data are different: never copy a raw
validation bundle directly into `fixtures/` without applying D15 review/redaction.

## Adding a hint

Hints live in `luci-app-l2-info/htdocs/luci-static/resources/l2-info/hints.js`.
They satisfy P5 H1-H4, use kind `likely` only for causal interpretation and
`note` for explanation, and have both positive and negative test coverage.

## Mechanical/CI checks

`sh tests/run.sh` enforces the repository-level invariants it can check,
including:

- collection/reader contracts through replay;
- no shipped classification-role vocabulary;
- no core reader-id special case;
- no LuCI polling;
- read-only ACL/no browser persistence/no UCI schema;
- every shipped reader has source fixtures;
- committed fixture MACs are synthetic/permitted constants;
- browser hint/export/query/diff tests when Node is available.

CI makes Node tests mandatory, validates all fixture JSON, runs current LuCI
ESLint/i18n/POT drift checks, checks shell syntax for repository shell helpers,
and builds both package trees in the official OpenWrt SDK.

Checks do **not** prove physical driver behaviour, measured hardware cost or a
security sandbox around arbitrary reader code. Say that limitation explicitly
rather than upgrading test evidence into a stronger claim.

## Claims

Do not write that a target works because a similar fixture passes. Hardware
claims name the real device/target/kernel run that supports them and belong in
the hardware/readiness record.

Numbers in normative/architectural prose should be either measured evidence or
refer to a source; avoid decorative precision.

## Style

Follow surrounding OpenWrt/LuCI conventions: tabs in shipped ucode/JS where the
project already uses them, `'use strict'`, simple POSIX `sh` for target helpers,
and comments that explain why a non-obvious rule exists.

User-facing docs should lead with tasks/outcomes rather than internal decision
numbers. Deep rationale can link to decisions instead of making ordinary users
read the design history before installing the tool.
