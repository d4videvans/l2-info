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

**Decision.** Strong FDB diffs require compatible acquisition scope for every
collection that can affect FDB identity or movement interpretation. That is now
`bridges`, `ports` and `fdb`: bridge and port addresses both participate in
`derived.local`, and port PVID participates in VLAN resolution. Annotation-only
changes in names/neighbours do not block an FDB diff.

**Implemented.** Commits `9b4b5ea` and `630300c` originally scoped compatibility
to the load-bearing FDB inputs and pinned the annotation distinction in tests.
D47 made bridge addresses load-bearing too; commits `f206576` and `5e60d15`
therefore add bridge collection and bridge-reader coverage to the same guard.

## Phase 2 — source and data-contract portability

### R4 — Detect bridge devices independently of membership (P1) — done; multi-platform hardware-verified

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
with zero ports and `derived.port_count: 0`. A populated software bridge and a
VLAN-filtering software bridge also report one bridge/one port correctly. With
VLAN filtering enabled and VLAN 10 added, the production snapshot carried both
VLAN 1 and VLAN 10 through `topo.vlans` and `derived.vlans_observed`.

On the GS1920-24 v1 (rtl839x, kernel 6.18.44), generic RTM_GETLINK reported
`switch` with `master: null` and `linkinfo.type == "bridge"`; the AF_BRIDGE view
reported the same bridge self-mastered with `linkinfo: null`, and sysfs agreed
it is a bridge.

The GS1900-8HP B1 (rtl838x, kernel 6.12.94) adds a different DSA representation:
`switch` is directly `type: "bridge"`; user ports are `type: "dsa"` with nested
`slave.type: "bridge"`; and the operator-configured management child
`switch.20` is `type: "vlan"`. Only `switch` becomes a bridge and AF_BRIDGE
provides the eight actual members.

The Cudy WR3000P v1 (`mediatek/filogic`, kernel 6.12.94) adds another shape:
`br-lan` is directly `type: "bridge"`, DSA LAN ports may be `type: "dsa"`, but
other real bridge members such as `wan` and Wi-Fi AP interfaces can have no
top-level link kind at all and only nested `slave.type: "bridge"`. They are
still correctly reported as ports because membership comes from AF_BRIDGE,
while VLAN children such as `br-lan.20` remain outside the port set.

### R5 — Preserve valid partial observations (P1, evidence-gated)

**Problem.** A collection-level non-`ok` status currently forbids all rows for
that collection. One unreadable `vlan_filtering` attribute can therefore
discard bridge identities which were read successfully. D47 also means that
losing a bridge row can lose a reported `br.address` used by `derived.local`.

This is real but needs a schema decision rather than a quick refactor. Do not
move it ahead of hardware validation merely because it is easy to describe.

**Evidence so far.** The x86 sweep, GS1920, GS1900 and Cudy captures have not
produced a real partial-attribute case: whenever the reader was usable, the
live collections in question were wholly `ok`. The first GS1900 attempt did
show a missing runtime dependency, but that correctly made the rtnl collections
unavailable as a whole and is not partial entity evidence.

**Decision work required.** The leading model remains to retain successfully
read entity evidence while attaching explicit coverage evidence naming the
subject, attribute and failure reason. Simply omitting the unreadable attribute
would reintroduce P1's ambiguity and is not acceptable.

**Work.** Keep this evidence-gated through the remaining router sweep. If no
real case appears, defer the schema expansion rather than adding complexity for
a hypothetical failure mode.

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

### R6a — Stop treating FDB row shape as hardware/software provenance (P0/P1) — done

**Finding.** An ordinary software-only Linux bridge, with no switch ASIC
involved, produced many `self` FDB rows with no `fdb.bridge`. Development
snapshots nevertheless called those `entries_switch_reported`: the
VLAN-filtered software bridge produced a 13/3 split, and after adding VLAN 10 a
13/5 split. The field names and their claimed meaning were therefore false.

**Decision (D47).** Do not infer hardware/software origin from `NTF_SELF`,
master presence or absence, or `fdb.bridge` presence or absence. Preserve those
reported fields, but remove the derived scope split. `scope.fdb.count` remains
a raw pre-merge observation count.

**Implemented.** Commit `a7bdc76` first removed the provenance claim from the
`duplicate_reports` hint. Commit `e3ab4c6` removes the two scope fields from the
assembler. `docs/snapshot-format.md` and D42/D47 now state the neutral contract.
`fixtures/devices/dual-reported-entries` and `empty-bridge-local` negatively
assert that `entries_switch_reported` and `entries_bridge_reported` stay absent.

The format remains version 1 because the disproved fields existed only in
unreleased development drafts. D47 records that this is a pre-release
correction, not precedent for changing a released v1 in place.

**Live regressions.** The GS1920 current backend keeps the obsolete scope fields
absent. On the Cudy, three remote client observations were each reported twice
with the same MAC/port/VLAN identity but differing flags; D40 merged each pair
and unioned the flags, including `self`, while `derived.local` remained false.
That is direct live evidence that `self` is neither a locality nor a portable
provenance test.

### R6b — Bridge/device own MAC and `derived.local` (P1) — done; multi-platform hardware-verified

**Finding.** An empty software bridge exposed its own unicast FDB address on
`l2probe0`, but D44 joined locality only against `topo.address` on port rows, so
that observation was `local: false`.

**Decision (D47).** A bridge's own link address is a reported fact, not a
heuristic. Generic RTM_GETLINK already used for D46 reports it, so register it
as `br.address` and let `derived.local` join against both `topo.address` and
`br.address`. Do not mark an FDB row local merely because it is on a bridge or
carries `self`.

**Implemented.** Commit `f7b81d9` reports bridge addresses from the generic link
dump. Commit `e3ab4c6` registers `br.address` and extends the existing exact
address join. `fixtures/sources/rtnl/empty-bridge-generic` pins the source fact;
new device fixture `empty-bridge-local` pins `local: true` with zero ports.
Because `br.address` is now load-bearing for movement interpretation, commits
`f206576` and `5e60d15` also make bridge acquisition scope part of diff
compatibility.

**Live regressions.** On the GS1920, the bridge address equals the DSA-port
address and eight FDB observations were local. On the GS1900, the eight DSA user
ports instead expose distinct sequential addresses; those per-port own-address
observations are also recognised as local. The Cudy preserves the same exact
reported-value rule while demonstrating that an FDB row carrying `self` can
still be non-local.

### R6c — Successful zero-row rtnetlink dumps return null (P0/P1) — done

**Finding.** On the populated x86 software bridge, the neighbour collection was
once reported `unavailable` with `netlink dump returned no result and no error`.
Inspection of current `ucode-mod-rtnl` confirmed the representation: for a
multipart dump, the result array is allocated only when a valid row arrives. A
successful dump with zero rows therefore returns `null` while `nl.error()`
remains clear. The old wrapper treated that successful-empty representation as
failure, violating D18/P1.

**Fix (D48).** Commit `2e55c7a` normalises `rows == null` with no rtnl error to
an empty array. A real rtnl error remains `unavailable`. Collection semantics
then apply normally: an empty neighbour read is `ok`; an empty FDB read remains
`indeterminate` under P4. Commits `eb6c61f`, `b723db9`, `93ad20b` and `f7aefd3`
extend source replay and add a `null-empty-dump` fixture.

**Live regression.** The current v2 checkout ran on the GS1920 with all 30
then-existing ucode/mechanical groups passing, including `null-empty-dump` and
`empty-bridge-local`. The same 30 groups passed on the GS1900 before the new
RTL838x fixture was added. Node tests were skipped on these OpenWrt targets
because Node was not installed. The D48 regression-test gap itself is closed;
browser-side tests remain an R11 CI concern.

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

For development installs from a copied checkout, `tools/install-dev-backend.sh`
now verifies the required ucode modules before changing files, then
installs/reloads the ubus plugin and assembler before replacing the dynamically
loaded reader. The module check was added after the first GS1900 run showed that
manual copying can bypass the package manager's otherwise-correct
`ucode-mod-rtnl` dependency. The install order avoids the transient
new-reader/old-assembler mismatch seen when `br.address` was introduced.

LuCI (`openwrt/luci`):

- set/confirm maintainer metadata;
- regenerate the POT with LuCI tooling;
- run LuCI JS/style checks used by current CI;
- verify menu/ACL naming and install paths after splitting from this monorepo.

### R11 — Add reproducible CI/build checks (P2)

CI should make currently optional checks mandatory and distinguish unit logic
from upstream integration:

1. ucode source/discovery/device fixture suite, including `null-empty-dump`,
   `empty-bridge-local`, `rtl838x-dsa-link-shape` and
   `filogic-router-link-shape`;
2. Node hint/export/filter/diff/scope tests;
3. shell/static checks, including parse validation for fixture JSON;
4. backend package build against a pinned/current OpenWrt tree;
5. LuCI package build/check against a pinned/current LuCI tree.

The Cudy copied checkout exposed why this matters: its live production
validation succeeded, but the then-new RTL838x source fixture contained malformed
JSON and made `tests/run.sh` fail. The fixture has been corrected; the failure
was a repository-test defect, not a router/runtime defect. Until full CI/build
jobs exist, do not describe repository tests as proving feed integration.

### R12 — Make the test runner invocation unambiguous (P3) — done

`CONTRIBUTING.md` documents `sh tests/run.sh`, which survives archive round
trips where the executable bit does not. README/manual install paths were also
brought up to date in `547f97a`.

## Hardware validation matrix

The available devices give useful diversity rather than merely more samples of
one switch.

| Device | State | Primary purpose / evidence |
|---|---|---|
| x86 OpenWrt 25.12.5 / 6.12.94 | **software-bridge sweep complete for current questions** | no-bridge, empty bridge, populated bridge, VLAN-filtering and VLAN-10 bridge; verified R4 and exposed/corrected R6, D47 and D48 assumptions |
| Zyxel GS1920-24 v1 | **rtl839x validation complete for current questions** | generic bridge identity/address live-verified; 28 ports; bridge/device locality; ~1.2–1.3 s hardware walk; current 30-group ucode/mechanical suite passed |
| Zyxel GS1900-8HP B1 | **rtl838x validation complete for current questions** | one bridge/eight ports; distinct per-port addresses; nested DSA slave bridge metadata does not create false bridges; operator management VLAN child stays outside port set; 141 raw FDB rows matched `bridge` exactly; 1.187 s; no R5 case |
| Cudy WR3000P v1 | **Filogic/router validation complete for current questions** | one bridge/eight mixed wired/Wi-Fi ports; members without top-level generic kind still discovered via AF_BRIDGE; VLAN children excluded; 130 raw FDB rows matched `bridge`, three flag-only duplicate pairs merged to 127; 233 ms; no R5 case |
| Linksys Atlas Pro 6 MX5600 / SPNMX56 | pending | materially different router/DSA platform |
| Linksys EA8300 | pending | older router/DSA compatibility |

For each device, record:

- `ubus call system board`;
- snapshot duration and collection statuses;
- `bridge -j link`, `bridge -j vlan show`, `bridge -j fdb show` where available
  for cross-checking only (not as the product data path);
- the rtnetlink representation needed to explain bridge identity and, where
  useful, bridge link address;
- raw FDB row shapes without assigning hardware/software provenance unless
  independently evidenced;
- whether bridge devices identify cleanly when empty;
- any collection which is partial, empty or unavailable and why.

Raw captures must follow D15 redaction before being committed as fixtures.

## Suggested execution order

1. R1–R4, R6a–R6c, R7–R9 and R12 — implemented; D46–D48 now have live evidence
   across x86 software bridging, two Realtek switch generations and Filogic.
2. On the next copied checkout, execute the corrected
   `rtl838x-dsa-link-shape` fixture and new `filogic-router-link-shape` fixture;
   neither has yet had a successful current-branch ucode replay after creation.
3. MX5600/SPNMX56 and EA8300 router/DSA sweep.
4. Revisit R5 after the remaining router cases; implement it only if real
   partial-attribute evidence appears.
5. R10 packaging/POT work and R11 CI/build integration.
6. Final current-master OpenWrt/LuCI review before upstream PRs.

The plan is deliberately evidence-led. The x86 sweep invalidated several
plausible-looking assumptions, the two Realtek devices then validated the
corrected mechanisms across different switch generations, and the Cudy added a
router topology in which not every bridge member has a useful top-level generic
link kind. Preserve the same discipline for the remaining portability work
rather than filling gaps by inference.
