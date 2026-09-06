# l2-info v0.1.0-rc2 — release notes

**Status:** second public pre-upstream test release.

RC2 supersedes RC1 for new testing. It keeps the same backend snapshot contract
and package shape, but fixes a correctness problem in the LuCI comparison view
for a MAC that moves ports while being observed in more than one effective VLAN.

## Why RC2 exists

RC1 correctly changed movement inference to use complete remote-unicast port
presence rather than raw FDB row counts. A follow-up review found that the move
row then collapsed two different VLAN states into the same `null` presentation:

- no effective VLAN could be resolved; and
- several effective VLANs were observed on the moving port.

For example, a host observed on `lan1` in VLANs 5 and 10 and then on `lan2` in
VLAN 5 could be shown as if the old side had no VLAN. The primitive change rows
for the same MAC were also suppressed by a MAC-wide presentation filter, so the
missing VLAN evidence was not otherwise visible.

That violates the project's central rule that uncertainty or multiplicity must
not silently become a definite claim, so RC2 is a correctness release rather
than a documentation-only update.

## What changed

The comparison logic now keeps three identities explicitly separate:

1. **raw observation identity** — MAC + port + reported `fdb.vlan`;
2. **visible placement identity** — MAC + port + effective `derived.vlan`;
3. **port presence** — MAC + port for deciding whether an unambiguous move
   occurred.

A moved record now retains the complete distinct effective-VLAN set on the old
and new port. An unresolved VLAN remains an explicit `null` member of that set,
so it cannot be confused with several resolved VLANs. The LuCI view renders the
whole set for a move.

Primitive appeared/gone placements are filtered in the pure diff module rather
than by a MAC-wide renderer rule. A primitive placement is suppressed only when
the moved row actually represents that MAC, side, port and effective VLAN;
anything else remains visible evidence.

The obsolete `presenceAppeared` / `presenceVanished` diff outputs were removed.
They were intermediate test artefacts and were no longer consumed by the view.

## Regression coverage

The diff tests now cover:

- ordinary one-port-to-one-port movement;
- one-to-many, many-to-one and many-to-many cases remaining primitive evidence;
- VLAN-only changes on one port;
- explicit-VLAN plus PVID dual reports;
- partial raw disappearance without a false move;
- raw identity churn with unchanged visible placement;
- a move from VLANs 5 and 10 to VLAN 5;
- mixed resolved and unresolved VLAN evidence on a moved port;
- unresolved-only VLAN evidence remaining distinct from a multi-VLAN set.

The current decision register and architecture documentation also spell out the
three diff identities and their separate purposes.

## What did not change

RC2 does **not** change:

- `l2-info.snapshot` format/version 1;
- backend FDB identity or merging;
- rtnetlink acquisition;
- port aggregate semantics;
- install/uninstall behaviour;
- the read-only/no-polling model;
- package dependencies or intended upstream destinations.

The existing hardware validation therefore remains relevant. RC2 changes the
browser-side interpretation/presentation of two already acquired snapshots,
not how the device is read.

## Installation

Use the tagged RC2 checkout and the same reversible test-install path:

```sh
cd /tmp/l2-info
sh tools/install-test.sh
```

Then refresh LuCI and open **Status → MAC & VLAN Lookup**. If an existing LuCI
login does not reflect newly installed menu files, log out and back in.

For full installation, uninstall, privacy and troubleshooting guidance, see
`docs/getting-started.md`.

## Feedback

For new testing, please report against `v0.1.0-rc2` rather than RC1. Useful
feedback remains the OpenWrt version, device model/target, exact tag/revision,
snapshot duration, relevant **Device and data-source details**, and what looked
wrong or confusing.
