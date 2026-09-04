# Upstream remediation plan

**Status:** active work plan following the September 2026 architecture and
OpenWrt/LuCI review, refined after review by the original implementation agent.

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

### R1 — Describe readers as trusted package code (P0) — done

**Problem.** Readers are loaded as ucode into the rpcd process. Passing a
context containing `nl`, `fs` and `ubus` makes fixture replay and dependency
injection clean, but it is not a sandbox: a reader can import modules itself,
and the raw rtnetlink and generic ubus handles are not capability-restricted.
The former documentation overstated this as making a reader structurally
incapable of writing. A test reader importing `writefile` from `fs` proved the
claim false by successfully writing a file.

**Decision.** Installed readers are trusted package code. `read(ctx)` is a
contract and a testability seam, not a security boundary. A conforming reader
uses the supplied observational primitives only. Actual sandboxing would need a
separate process / privilege boundary and is out of scope unless a future
threat model justifies that machinery.

**Implemented.** Commit `6df99fa` corrects D34, `docs/readers.md`,
`CONVENTIONS.md` and the assembler source comment. The read-only LuCI ACL,
no-write application behaviour and P7 remain unchanged.

### R2 — Make snapshot movement inference unambiguous (P0)

**Problem.** One MAC may legitimately have several simultaneous FDB
observations. The current view pairs every appeared observation with every
vanished observation sharing a MAC, which can produce Cartesian-product
"moves" and then suppress the raw evidence. This became a practical bug after
D40 made one MAC capable of representing several observations.

**Decision.** Report `moved` only when exactly one vanished and exactly one
appeared observation exist for a MAC. Otherwise show the primitive appeared /
vanished evidence and make no movement inference. Local and non-unicast
addresses do not receive a movement inference. A VLAN-only change on the same
port is not a port move.

**Work.** Extract comparison into a pure module and add unit tests for 1→1,
1→N, N→1, N→N, local, multicast/protocol and VLAN-only cases.

**Done when.** Ambiguous changes can never be rendered as an unqualified move,
and every movement rule has a direct unit test.

### R2a — Put all non-rendering view logic under tests (P0/P1)

**Problem.** `filterRows()`, `scopeCompatible()` and `diff()` are the material
view-side logic which currently have no direct tests. The first review-found
logic bug was in that exact untested set. Coverage of hints and export does not
cover them indirectly.

**Decision.** Pure policy/comparison logic should live in small modules that can
be loaded with the same Node/LuCI shim approach as `hints.js`. Rendering remains
in `main.js`.

**Work.** Test filtering (port, VLAN, partial MAC, non-unicast visibility and
invalid inputs), scope compatibility, and diff independently of DOM rendering.
Make these Node tests mandatory in CI even if the developer convenience runner
continues to skip them when Node is absent.

### R3 — Compare acquisition scope, not only rolled-up status (P1)

**Problem.** Two snapshots can both have `scope.fdb.status == ok` while the set
of successful readers changed. Diffing them can therefore compare different
observation coverage and present that as network change. This is cheap to fix
now even though it becomes reachable only once a second reader exists.

**Decision.** Define a comparison fingerprint from snapshot format/version,
collection statuses and successful reader coverage. Strong diffs require equal
fingerprints. Reader diagnostics which do not affect contributed coverage may
be ignored.

**Work.** Add a pure compatibility function and unit coverage for a reader
disappearing while another keeps the collection `ok`.

**Done when.** A changed observation surface prevents a normal diff and is
explained to the user.

## Phase 2 — source and data-contract portability

### R4 — Detect bridge devices independently of membership (P1)

**Problem.** Current bridge discovery is primarily based on names observed as
`master`, including self-master behaviour observed on rtl839x. An empty bridge
has no member referencing it and is therefore invisible today.

**Known implementation path.** Current `ucode-mod-rtnl` exposes
`IFLA_LINKINFO` as `linkinfo` including `IFLA_INFO_KIND`, so bridge identity can
come from the device's own link kind rather than from membership. The existing
`/sys/class/net/<dev>/bridge` read path is a possible fallback, not a reason to
guess at the netlink representation.

**Decision.** Establish bridge identity from an authoritative link property
independently of port membership. AF_BRIDGE data continues to provide
bridge-port and VLAN information.

**Work.** Capture an empty and populated software bridge on x86 first, then
implement against the observed ucode-rtnl shape. Add an empty software bridge
source fixture and retain the rtl839x self-master regression fixture.

**Done when.** An empty bridge is reported as a bridge with zero ports on
generic x86 OpenWrt and existing switch fixtures remain stable.

### R5 — Preserve valid partial observations (P1, evidence-gated)

**Problem.** A collection-level non-`ok` status currently forbids all rows for
that collection. One unreadable `vlan_filtering` attribute can therefore
discard bridge identities which were read successfully.

This is real but appears rarer than R2/R4 and needs a schema decision rather
than a quick refactor. Do not move it ahead of hardware validation merely
because it is easy to describe.

**Decision work required.** The leading model is to retain successfully read
entity evidence while attaching explicit coverage evidence naming the subject,
attribute and failure reason. Simply omitting the unreadable attribute would
reintroduce P1's ambiguity and is not acceptable.

**Work.** Let the hardware sweep tell us whether this occurs in practice, then
add a decision record before changing schema semantics. Add mixed bridge-state
fixtures and update snapshot documentation and validation together.

### R6 — Declare FDB not applicable when topology positively proves it (P1)

**Problem.** A successful empty AF_BRIDGE FDB dump is currently
`indeterminate`. That is correct when a bridge exists: an idle bridge/switch and
a driver which does not expose its hardware table are indistinguishable from
one sample. It is unnecessarily vague when positive topology evidence says
there is no bridge at all.

**Decision.** In the no-bridge case the honest status is `not_applicable`, not
`ok` with zero rows. Preserve `indeterminate` for an empty dump where a bridge
exists. Never infer lack of hardware offload from the absence of rows.

**Work.** Pin the no-bridge behaviour with the x86 fixture before changing the
reader.

## Phase 3 — LuCI and API integration

### R7 — Clean up the age timer lifecycle (P2)

Retain and cancel the `setInterval()` created by the view so navigating in and
out cannot accumulate timers holding old DOM nodes. This does not change P6:
there is still no data polling or automatic refresh.

### R8 — Localise stable status labels; defer reason-code machinery (P2)

**Do now.** Backend status values are already stable codes. The LuCI view should
map `ok`, `unavailable`, `not_applicable` and `indeterminate` to translated
human labels instead of printing the raw tokens.

**Deferred.** Do not introduce a reason-code vocabulary merely in anticipation
of another consumer. The current human reasons are often the useful diagnostic
content, and coding them would add a maintenance/versioning surface. Reopen if
a second consumer needs machine-readable reason classes or translation of the
reason prose becomes a demonstrated problem.

### R9 — Strictly validate query inputs (P2)

Re-verified against the current source: the VLAN control is a text input and
`filterRows()` calls `parseInt()` directly. There is no explicit whole-string
validation in that path, so `12abc` silently becomes VLAN 12 and a non-number
becomes `NaN` rather than producing useful feedback.

Use strict whole-string VLAN parsing and enforce 1–4094. Keep partial MAC
matching, but reject or visibly mark a non-empty input which normalises to an
empty or otherwise misleading search. Cover both in the new filter tests.

## Phase 4 — upstream packaging and CI

### R10 — Make the two feed packages independently clean (P2)

Backend (`openwrt/packages`):

- set a real maintainer;
- fix/remove `PKG_LICENSE_FILES` so it refers to a file actually present in the
  package contribution;
- review the category/submenu for best fit. `Routing and Redirection` is not a
  standards violation — current OpenWrt packages including `lldpd` use it — but
  a diagnostic may have a better home;
- verify dependencies on current OpenWrt master.

The rpcd install/reload question is settled: current rpcd's reload path causes a
re-exec and rescans plugins, so the existing postinst reload is valid.

LuCI (`openwrt/luci`):

- set/confirm maintainer metadata;
- regenerate the POT with LuCI tooling;
- run LuCI JS/style checks used by current CI;
- verify menu/ACL naming and install paths after splitting from this monorepo.

### R11 — Add reproducible CI/build checks (P2)

CI should make currently optional checks mandatory and distinguish unit logic
from upstream integration:

1. ucode source/discovery/device fixture suite;
2. Node hint/export/filter/diff/scope tests;
3. shell/static checks;
4. backend package build against a pinned/current OpenWrt tree;
5. LuCI package build/check against a pinned/current LuCI tree.

Until a full build job exists, do not describe the repository tests as proving
feed integration.

### R12 — Make the test runner invocation unambiguous (P3)

Document `sh tests/run.sh` consistently. This survives zip/archive round-trips
where an executable bit may not, and avoids making the bit itself part of the
user contract.

## Hardware validation matrix

The immediate available devices give useful diversity rather than merely more
samples of one switch.

| Device | Primary purpose | Evidence to capture |
|---|---|---|
| x86 OpenWrt box | Generic software bridge baseline | empty bridge, populated bridge, VLAN-filtered and non-filtered bridge, no-bridge case if practical |
| Zyxel GS1920-24 v1 | Existing rtl839x reference | regression baseline; hardware/software FDB duplication and scan cost |
| Zyxel GS1900-8 | Second Realtek switch case | bridge/FDB representation, VLAN flags, hardware dump behaviour, timing |
| Cudy WR3000P v1 | Contemporary router/DSA case | router topology, CPU/user ports, VLAN handling, neighbour/name behaviour |
| Linksys Atlas Pro 6 MX5600 / SPNMX56 | Different router/DSA platform | same checks on a materially different target/driver stack |
| Linksys EA8300 | Older router/DSA platform | compatibility across older hardware/driver assumptions |

For each device, record:

- `ubus call system board`;
- snapshot duration and collection statuses;
- `bridge -j link`, `bridge -j vlan show`, `bridge -j fdb show` where available
  for cross-checking only (not as the product data path);
- the rtnetlink representation needed to explain bridge identity;
- whether FDB rows expose hardware/software duplicates;
- whether bridge devices identify cleanly when empty;
- any collection which is partial, empty or unavailable and why.

Raw captures must follow D15 redaction before being committed as fixtures.

## Suggested execution order

1. R1 reader trust wording — **done** (`6df99fa`).
2. R2 + R2a: extract/test filter/diff/scope logic and fix movement inference.
3. R3 comparison fingerprint while the comparison module is already open.
4. x86 capture to settle R4 and pin R6 rather than guessing about rtnetlink.
5. R4 bridge detection implementation.
6. GS1900-8 and router hardware sweep; keep the GS1920 as regression reference.
7. R5/R6 data-contract changes only where the captured evidence supports them.
8. R7–R9 LuCI/API polish.
9. R10–R12 packaging and CI.
10. Final current-master OpenWrt/LuCI review before upstream PRs.

The plan is deliberately ordered so hardware evidence settles portability
questions before the data contract is made more complicated. Do not implement
R4–R6 merely to satisfy this document if a real capture disproves the premise.
