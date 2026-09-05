# Upstream remediation plan

**Status:** active work plan following the September 2026 architecture and
OpenWrt/LuCI review, refined after implementation review and live hardware
validation.

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

### R2 — Make snapshot movement inference unambiguous (P0) — done

**Problem.** One MAC may legitimately have several simultaneous FDB
observations. The old view paired every appeared observation with every
vanished observation sharing a MAC, which could produce Cartesian-product
"moves" and then suppress the raw evidence. This became a practical bug after
D40 made one MAC capable of representing several observations.

**Decision.** Report `moved` only when exactly one vanished and exactly one
appeared observation exist for a MAC. Otherwise show the primitive appeared /
vanished evidence and make no movement inference. Local and non-unicast
addresses do not receive a movement inference. A VLAN-only change on the same
port is not a port move.

**Implemented.** Commit `0680525` extracted comparison into
`luci-static/resources/l2-info/diff.js` and added direct unit tests covering
1→1, 1→N, N→1, N→N, local, multicast/protocol and VLAN-only cases.

### R2a — Put all non-rendering view logic under tests (P0/P1) — done locally

`filterRows()`, `scopeCompatible()` and `diff()` now live in pure modules with
Node tests (`query.test.js`, `diff.test.js`) rather than being buried in DOM
rendering. The local developer runner intentionally skips these when Node is
absent; R11 still needs to make them mandatory in CI.

### R3 — Compare acquisition scope, not only rolled-up status (P1) — done

**Problem.** Two snapshots can both have `scope.fdb.status == ok` while the set
of successful readers changed. Diffing them can therefore compare different
observation coverage and present that as network change.

**Decision.** Strong FDB diffs require compatible FDB acquisition scope: the
snapshot format/version, relevant collection statuses and successful reader
coverage must match. Annotation-only changes in names/neighbours do not block
an FDB diff.

**Implemented.** Commits `9b4b5ea` and `630300c` scope compatibility to the
load-bearing FDB inputs and pin the annotation distinction in tests.

## Phase 2 — source and data-contract portability

### R4 — Detect bridge devices independently of membership (P1) — done; x86 hardware-verified

**Problem.** Bridge discovery used AF_BRIDGE `master` references, including the
self-master behaviour observed on rtl839x. An empty bridge has no member
referencing it and could therefore disappear.

**Decision (D46).** Bridge identity comes from generic RTM_GETLINK
`linkinfo.type == "bridge"`; AF_BRIDGE RTM_GETLINK remains the membership/VLAN
view. An AF_BRIDGE master absent from the generic bridge set is an inconsistency,
not permission to infer a bridge.

**Implemented.** Commit `2d02b20` changes the rtnl reader; source replay now
distinguishes generic and AF_BRIDGE link reads and includes explicit empty
bridge and mismatch fixtures.

**Live validation.** On x86/64 OpenWrt 25.12.5, kernel 6.12.94, a deliberately
empty `l2probe0` bridge was reported by the production backend as one bridge
with zero ports and `derived.port_count: 0`. The same fixture/source suite
passed on that OpenWrt runtime (28 groups; browser-side Node tests skipped
because Node was not installed). A populated software bridge and a
VLAN-filtering software bridge also report one bridge/one port correctly. With
VLAN filtering enabled and VLAN 10 added, the production snapshot carried both
VLAN 1 and VLAN 10 through `topo.vlans` and `derived.vlans_observed`.

**Remaining regression check.** Run the generic-link probe on the GS1920-24 v1
to replace the synthetic D46 companion row in its source fixture with live
confirmation that `switch` exposes `linkinfo.type == "bridge"` there too.

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

### R6 — No-bridge FDB special case (P1) — rejected by hardware evidence

The proposed change was to declare an empty FDB `not_applicable` when topology
positively proved that no Linux bridge existed. The x86 experiment disproved
the premise behind that shortcut: after stopping OpenWrt networking, generic
RTM_GETLINK showed only plain `lo`/`eth0`, and both `bridge -j link` and
`bridge -j vlan show` were empty, yet the AF_BRIDGE FDB dump still returned a
permanent `self` protocol entry on plain `eth0`.

Therefore bridge existence is not the applicability boundary for the AF_BRIDGE
FDB read. Do **not** special-case the no-bridge topology. The existing rule
stands: a successful zero-row FDB dump remains `indeterminate` when one sample
cannot distinguish true emptiness from an observation gap; non-zero rows are
reported as observed.

### R6a — Stop treating FDB row shape as hardware/software provenance (P0/P1) — open

**New finding from x86 validation.** An ordinary software-only Linux bridge,
with no switch ASIC involved, produced many `self` FDB rows with no
`fdb.bridge`. The current scope calculation calls these
`entries_switch_reported` and treats a non-zero count as positive evidence of a
hardware table. That inference is false: the VLAN-filtered software bridge
reported 13 such rows and 3 rows in the complementary bucket; after adding
VLAN 10, it reported 13 and 5.

The same assumption had leaked into the `duplicate_reports` presentation hint.
Commit `a7bdc76` removes the hardware/bridge provenance claim from that hint and
keeps only the observable fact that several kernel FDB observations exist for
the same address/port.

The underlying structural distinction is still observable, but no demonstrated
consumer needs it. The leading resolution is therefore to remove the two split
scope fields rather than rename an implementation-shaped distinction into the
public contract. Record that as a decision and update the format/tests before
making the change.

Do not infer hardware/software origin solely from `NTF_SELF`/master shape.
Fixtures must include a pure software bridge case that would fail any such
claim.

### R6b — Bridge-device own MAC and `derived.local` (P1, evidence-gated) — open

The empty software bridge exposed its own unicast FDB address on `l2probe0`, but
`derived.local` was false because D44 currently joins only against
`topo.address` values from port rows. An empty bridge has no port row. Once
`eth0` was attached, the member interface's own MAC was correctly marked local,
including its VLAN 1 and VLAN 10 FDB observations, so the existing join works
for members; the gap is bridge-device addresses.

Do not fix this by declaring every address on a bridge device local. Capture
the generic link address for bridge devices first and decide whether bridge
rows should report their own MAC as an attribute, then let `local` remain a
reported-value join.

### R6c — Successful zero-row rtnetlink dumps return null (P0/P1) — code fixed; regression pending on new fixture

**Finding.** On the populated x86 software bridge, the neighbour collection was
once reported `unavailable` with `netlink dump returned no result and no error`.
Inspection of current `ucode-mod-rtnl` confirmed the representation: for a
multipart dump, the result array is allocated only when a valid row arrives. A
successful dump with zero rows therefore returns `null` while `nl.error()`
remains clear. The old wrapper treated that successful-empty representation as
failure, violating D18/P1.

**Fix.** Commit `2e55c7a` normalises `rows == null` with no rtnl error to an
empty array. A real rtnl error remains `unavailable`. Collection semantics then
apply normally: an empty neighbour read is `ok`; an empty FDB read remains
`indeterminate` under P4. Commits `eb6c61f`, `b723db9`, `93ad20b` and `f7aefd3`
extend source replay and add a `null-empty-dump` fixture.

**Live regression.** The production fix was applied manually to the older
v2-branch ZIP on x86/64 OpenWrt 25.12.5 and all 28 existing ucode/mechanical
groups passed. Node tests were skipped because Node is absent. This proves the
reader change does not regress those existing groups; it does **not** claim the
new `null-empty-dump` fixture passed on the VM, because that fixture is not in
the offline ZIP. Run the updated branch's fixture suite in an environment that
contains the new fixture before closing the regression-test part of this item.

## Phase 3 — LuCI and API integration

### R7 — Clean up the age timer lifecycle (P2) — done

Commits `678f5b1` and `0a2cdab` stop the scheduler on navigation and ensure one
age-update chain per view. P6 remains unchanged: there is still no data polling.

### R8 — Localise stable status labels; defer reason-code machinery (P2) — code done, POT pending

Stable collection/status labels are translated in the LuCI view and reader
collection notes are displayed (`678f5b1`). Reason-code machinery remains
deferred. Regenerating the POT with LuCI tooling is still part of R10.

### R9 — Strictly validate query inputs (P2) — done

Commit `0680525` adds strict whole-string VLAN parsing (1–4094), validates MAC
search input, visibly rejects invalid queries and covers the behaviour in
`query.test.js`.

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
re-exec and rescans plugins, so the existing postinst reload is valid. The x86
test also confirmed that the object registers and `snapshot()` works after
manual installation; an immediately-following `ubus -v list` once raced the
reload, while a later list showed the object normally.

LuCI (`openwrt/luci`):

- set/confirm maintainer metadata;
- regenerate the POT with LuCI tooling;
- run LuCI JS/style checks used by current CI;
- verify menu/ACL naming and install paths after splitting from this monorepo.

### R11 — Add reproducible CI/build checks (P2)

CI should make currently optional checks mandatory and distinguish unit logic
from upstream integration:

1. ucode source/discovery/device fixture suite, including `null-empty-dump`;
2. Node hint/export/filter/diff/scope tests;
3. shell/static checks;
4. backend package build against a pinned/current OpenWrt tree;
5. LuCI package build/check against a pinned/current LuCI tree.

Until a full build job exists, do not describe the repository tests as proving
feed integration.

### R12 — Make the test runner invocation unambiguous (P3) — done

`CONTRIBUTING.md` documents `sh tests/run.sh`, which survives archive round
trips where the executable bit does not. README/manual install paths were also
brought up to date in `547f97a`.

## Hardware validation matrix

The available devices give useful diversity rather than merely more samples of
one switch.

| Device | State | Primary purpose / evidence |
|---|---|---|
| x86 OpenWrt 25.12.5 / 6.12.94 | **R4 verified; software bridge sweep substantially complete** | no-bridge, empty bridge, populated bridge, VLAN-filtering and VLAN-10 bridge; exposed R6, provenance and null-empty assumptions |
| Zyxel GS1920-24 v1 | baseline captured; D46 generic-link recheck pending | rtl839x regression, FDB duplication and scan cost |
| Zyxel GS1900-8 | pending | second Realtek switch case: bridge/FDB representation, VLAN flags, hardware dump behaviour, timing |
| Cudy WR3000P v1 | pending | contemporary router/DSA case |
| Linksys Atlas Pro 6 MX5600 / SPNMX56 | pending | materially different router/DSA platform |
| Linksys EA8300 | pending | older router/DSA compatibility |

For each device, record:

- `ubus call system board`;
- snapshot duration and collection statuses;
- `bridge -j link`, `bridge -j vlan show`, `bridge -j fdb show` where available
  for cross-checking only (not as the product data path);
- the rtnetlink representation needed to explain bridge identity;
- the raw FDB row shapes without assigning hardware/software provenance unless
  independently evidenced;
- whether bridge devices identify cleanly when empty;
- any collection which is partial, empty or unavailable and why.

Raw captures must follow D15 redaction before being committed as fixtures.

## Suggested execution order

1. R1–R4, R7–R9 and R12 — implemented; R4 live-x86 verified.
2. Resolve R6a's false hardware/software provenance claim before relying on the
   current scope split anywhere else; leading option is to remove the split.
3. Capture bridge-device link addresses needed to decide R6b without guessing.
4. Run the updated `null-empty-dump` source fixture in a current-branch ucode
   environment; the production fix already passes the older 28-group VM suite.
5. Re-probe GS1920 generic RTM_GETLINK to live-verify D46 on rtl839x.
6. GS1900-8 and router hardware sweep.
7. Revisit R5 only if captured hardware produces a real partial-attribute case.
8. R10 packaging/POT work and R11 CI/build integration.
9. Final current-master OpenWrt/LuCI review before upstream PRs.

The plan is deliberately evidence-led. The x86 sweep both verified R4 and
invalidated several plausible-looking assumptions; that is a reason to preserve
the same discipline for the remaining portability work rather than filling gaps
by inference.
