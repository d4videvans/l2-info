# Upstream remediation plan

**Status:** active work plan following the September 2026 architecture and
OpenWrt/LuCI review.

The aim is not to make `l2-info` more ambitious. It is to make the existing
narrow design more truthful, portable and straightforward to review upstream.
The existing principles remain the default: observation over classification,
explicit uncertainty, one user-triggered snapshot, read-only behaviour and a
small ubus surface.

## Priority classes

- **P0 — correctness / trust model:** fix before expanding coverage.
- **P1 — portability / data-contract hardening:** fix before upstream review.
- **P2 — integration / UI / packaging:** fix before submission where practical.
- **P3 — later polish:** useful, but not an upstream blocker.

## Phase 1 — correctness and trust model

### R1 — Describe readers as trusted package code (P0)

**Problem.** Readers are loaded as ucode into the rpcd process. Passing a
context containing `nl`, `fs` and `ubus` makes fixture replay and dependency
injection clean, but it is not a sandbox: a reader can import modules itself,
and the raw rtnetlink and generic ubus handles are not capability-restricted.
The current documentation overstates this as making a reader structurally
incapable of writing.

**Decision.** Treat installed readers as trusted package code. `read(ctx)` is a
contract and a testability seam, not a security boundary. A conforming reader
uses the supplied observational primitives only. Actual sandboxing would need a
separate process / privilege boundary and is out of scope unless a future
threat model justifies that machinery.

**Work.** Amend D34, `docs/readers.md`, `CONVENTIONS.md`, architecture comments
and source comments so no sandbox claim remains. Keep the read-only LuCI ACL,
no-write application behaviour and P7 unchanged.

**Done when.** A repository search contains no claim that readers are
structurally unable to write, and the trust boundary is stated explicitly.

### R2 — Make snapshot movement inference unambiguous (P0)

**Problem.** One MAC may legitimately have several simultaneous FDB
observations. The current view pairs every appeared observation with every
vanished observation sharing a MAC, which can produce Cartesian-product
"moves" and then suppress the raw evidence.

**Decision.** Report `moved` only when exactly one vanished and exactly one
appeared observation exist for a MAC. Otherwise show the primitive appeared /
vanished evidence and make no movement inference. Local and non-unicast
addresses should not receive a movement inference.

**Work.** Rewrite `diff()` grouping by MAC; add unit tests for 1→1, 1→N, N→1,
N→N, local and multicast cases.

**Done when.** Ambiguous changes can never be rendered as an unqualified move.

### R3 — Compare acquisition scope, not only rolled-up status (P1)

**Problem.** Two snapshots can both have `scope.fdb.status == ok` while the set
of successful readers changed. Diffing them can therefore compare different
observation coverage and present that as network change.

**Decision.** Define a comparison fingerprint from snapshot format/version,
collection statuses and successful reader coverage. Strong diffs require equal
fingerprints. Reader diagnostics which do not affect contributed coverage may
be ignored.

**Work.** Add a pure compatibility function and fixture/unit coverage for a
reader disappearing while another keeps the collection `ok`.

**Done when.** A changed observation surface prevents a normal diff and is
explained to the user.

## Phase 2 — source and data-contract portability

### R4 — Detect bridge devices independently of membership (P1)

**Problem.** Current bridge discovery is primarily based on names observed as
`master`, including self-master behaviour observed on rtl839x. That is not a
sufficiently broad basis for empty bridges or differing kernel/driver shapes.

**Decision.** Establish bridge identity from an authoritative link property
(e.g. rtnetlink link kind) independently of port membership. AF_BRIDGE data
continues to provide bridge-port and VLAN information.

**Work.** Confirm the shape exposed by current `ucode-mod-rtnl`; add an empty
software bridge source fixture and real x86 capture before changing the reader
if necessary.

**Done when.** An empty bridge is reported as a bridge with zero ports on at
least generic x86 Linux/OpenWrt, and existing switch fixtures remain stable.

### R5 — Preserve valid partial observations (P1)

**Problem.** A collection-level non-`ok` status currently forbids all rows for
that collection. One unreadable bridge attribute can therefore discard other
bridge facts which were read successfully.

**Decision work required.** Settle the smallest schema change that preserves
P1/P9 while allowing partial evidence. Candidate model: collection acquisition
can remain `ok` when entity identity was read, while unreadable optional
attributes are omitted and an attributed coverage note records what could not
be read. Reserve non-`ok` for failure to establish the collection itself.

**Work.** Add a decision record before changing schema semantics; add mixed
bridge-state fixtures; update snapshot documentation and validation together.

**Done when.** Failure to read one optional bridge property cannot erase known
bridge identities, without making an omitted value ambiguous.

### R6 — Revisit genuinely-empty FDB semantics with positive context (P1)

**Problem.** Any successful empty FDB dump is currently `indeterminate`. That
is conservative for a live bridge/switch, but may be unnecessarily weak when
positive topology evidence shows that no bridge exists.

**Decision work required.** Preserve P4. Permit `ok` + zero rows only where
other positive evidence makes the empty result determinate; never infer lack of
hardware offload from the empty dump itself.

## Phase 3 — LuCI and API integration

### R7 — Clean up the age timer lifecycle (P2)

Retain and cancel the `setInterval()` created by the view so navigating in and
out cannot accumulate timers holding old DOM nodes. This does not change P6:
there is still no data polling or automatic refresh.

### R8 — Make status/reason presentation localisable and machine-stable (P2)

Backend status values are stable codes and should be translated in LuCI.
Backend reasons which are currently English prose should evolve toward a
stable reason code plus optional technical detail, so clients do not have to
interpret human text and the UI can localise the explanation.

Do this without making version 1 exports silently change meaning: either add
backwards-compatible fields or make the format-version consequence explicit in
a decision record.

### R9 — Validate query inputs (P2)

Use explicit VLAN validation (1–4094 where a VLAN ID is intended) rather than
permissive `parseInt()`. Keep partial MAC matching, but reject/visibly mark
inputs which normalise to something misleading.

## Phase 4 — upstream packaging and CI

### R10 — Make the two feed packages independently clean (P2)

Backend (`openwrt/packages`):

- set a real maintainer;
- fix/remove `PKG_LICENSE_FILES` so it refers to a file actually present in the
  package contribution;
- verify category/submenu choice against the target feed;
- verify dependencies on current OpenWrt master;
- verify rpcd reload/install behaviour.

LuCI (`openwrt/luci`):

- set/confirm maintainer metadata;
- regenerate the POT with LuCI tooling;
- run LuCI JS/style checks used by current CI;
- verify menu/ACL naming and install paths after splitting from this monorepo.

### R11 — Add reproducible CI/build checks (P2)

CI should make currently optional checks mandatory and distinguish unit logic
from upstream integration:

1. ucode source/discovery/device fixture suite;
2. Node hint/export/diff tests;
3. shell/static checks;
4. backend package build against a pinned/current OpenWrt tree;
5. LuCI package build/check against a pinned/current LuCI tree.

Until a full build job exists, do not describe the repository tests as proving
feed integration.

### R12 — Make the test runner invocation unambiguous (P3)

Either mark `tests/run.sh` executable in git or document `sh tests/run.sh`
consistently.

## Hardware validation matrix

The immediate available devices give useful diversity rather than merely more
samples of one switch.

| Device | Primary purpose | Evidence to capture |
|---|---|---|
| x86 OpenWrt box | Generic software bridge baseline | empty bridge, populated bridge, VLAN-filtered and non-filtered bridge, no-bridge case if practical |
| Zyxel GS1920-24 v1 | Existing rtl839x reference | regression baseline; hardware/software FDB duplication and scan cost |
| Zyxel GS1900-8 | Second Realtek switch family | bridge/FDB representation, VLAN flags, hardware dump behaviour, timing |
| Cudy WR3000P v1 | Contemporary router/DSA case | router topology, CPU/user ports, VLAN handling, neighbour/name behaviour |
| Linksys Atlas Pro 6 MX5600 / SPNMX56 | Different router/DSA platform | same checks on a materially different target/driver stack |
| Linksys EA8300 | Older router/DSA platform | compatibility across older hardware/driver assumptions |

For each device, record:

- `ubus call system board`;
- snapshot duration and collection statuses;
- `bridge -j link`, `bridge -j vlan show`, `bridge -j fdb show` where available
  for cross-checking only (not as the product data path);
- whether FDB rows expose hardware/software duplicates;
- whether bridge devices identify cleanly when empty;
- any collection which is partial, empty or unavailable and why.

Raw captures must follow D15 redaction before being committed as fixtures.

## Suggested execution order

1. R1 reader trust wording.
2. R2 movement correctness + tests.
3. R3 comparison fingerprint + tests.
4. x86 capture to settle R4 rather than guessing about rtnetlink shape.
5. R4 bridge detection implementation.
6. R5/R6 partial/empty semantics decisions and implementation.
7. Router/switch hardware sweep and fixtures.
8. R7–R9 LuCI/API polish.
9. R10–R12 packaging and CI.
10. Final current-master OpenWrt/LuCI review before upstream PRs.

The plan is deliberately ordered so hardware evidence settles portability
questions before the data contract is made more complicated. Do not implement
R4–R6 merely to satisfy this document if a real capture disproves the premise.
