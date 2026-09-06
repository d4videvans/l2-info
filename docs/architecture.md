# Architecture

**Document class:** canonical structure/mechanism. Rules live in
`docs/principles.md`; the snapshot contract lives in
`docs/snapshot-format.md`; this document owns components, boundaries, source
interfaces and the cost model.

## Components

```text
                         browser
  ┌────────────────────────────────────────────────┐
  │ luci-app-l2-info                               │
  │ current + previous snapshot in memory          │
  │ filter · diff · hints · export                 │
  └───────────────────┬────────────────────────────┘
                      │ LuCI RPC / read-only ACL
  ┌───────────────────▼────────────────────────────┐
  │ l2-info: rpcd ucode object                     │
  │  assembler                                      │
  │   discover readers · call read(ctx)            │
  │   validate · merge · declare scope · derive    │
  │        │                                        │
  │        ├── reader: rtnl (bundled)              │
  │        └── reader: optional third party        │
  └────────┼───────────────────────────────────────┘
           │ source primitives
  ┌────────▼───────────────────────────────────────┐
  │ local kernel/files/ubus state                  │
  └────────────────────────────────────────────────┘
```

The backend is loaded in-process by rpcd. It has no LuCI dependency and is
independently usable with:

```sh
ubus call l2-info snapshot
```

There is no daemon of its own and no recurring work when nobody asks for a
snapshot.

## Boundaries

### Readers report; the assembler derives

Readers return source-level `subject`/`attrs` plus collection statuses. They do
not join, count, classify, infer or stamp their own provenance.

The assembler validates/merges all surviving reader evidence, then computes the
closed set of `derived` values once. This prevents separate readers from growing
separate implementations of the same inference.

### Derivation is backend; filtering is presentation

Anything that changes the factual meaning of a row belongs in the backend so
all consumers receive the same answer. Anything that decides what a user wants
to see — port/VLAN/MAC filters, hiding multicast/protocol addresses, hints — is
view policy.

That is why `snapshot()` has no query arguments. Two filtered backend reads
would be two different acquisition moments and could disagree for reasons a
user could not distinguish from a bug.

### Trusted reader code, not sandboxed plugins

Readers run as ucode inside rpcd. `read(ctx)` is a conformance/test seam, not a
security boundary. An installed reader is trusted on the same basis as any
other installed package code.

## One method

The public ubus surface has one method:

```text
l2-info.snapshot()
```

It takes no arguments and returns `l2-info.snapshot` v1. D21 records a possible
future contributor/capture facility, but no second ubus method exists today.

## Reads performed per snapshot

The snapshot combines core self-description with the bundled reader's local
observations:

| Owner | Source | Interface | Purpose |
|---|---|---|---|
| assembler/core | board metadata | `ubus call system board` | board/model/target/kernel self-description |
| `rtnl` reader | generic link identity | RTM_GETLINK | bridge identity and bridge link address |
| `rtnl` reader | bridge membership/VLANs | RTM_GETLINK + `AF_BRIDGE` | member ports, carrier, bridge/VLAN membership, PVID/untagged flags |
| `rtnl` reader | forwarding database | RTM_GETNEIGH + `AF_BRIDGE` | MAC, port, reported VLAN, flags/state, master where reported |
| `rtnl` reader | neighbours | RTM_GETNEIGH + IPv4/IPv6 families | MAC-to-IP annotation |
| `rtnl` reader | local naming files | `/tmp/dhcp.leases`, `/var/dhcp.leases`, `/etc/ethers` | MAC-to-hostname annotation |

The board metadata does **not** decide collection success or FDB identity; it
makes the resulting snapshot self-describing. The link/FDB reads are the
load-bearing topology/forwarding evidence. Neighbour/name data is annotation.

Every rtnetlink dump uses one wrapper that checks the independent error channel.
Current `ucode-mod-rtnl` can represent a successful zero-row multipart dump as
`null` with no `nl.error()`; that pair is normalised to an empty successful row
set before collection semantics are applied.

## Why rtnetlink is the bundled source

The core reader uses the kernel interfaces directly rather than shelling out to
`bridge`/`ip-bridge` or reading vendor debugfs.

- `bridge -j ...` would add a runtime binary dependency for information the
  kernel already exposes.
- vendor debugfs tables can be cheaper on one chipset but are unstable,
  vendor-specific and make core behaviour depend on the hardware family.

The reader architecture allows a separately packaged source where real evidence
justifies one, but the core does not branch on target/device id. A device lacking
a source gets an explicit scope declaration, not a silent alternate path.

## Bridge identity and membership are different facts

Two link views are intentionally used:

1. generic RTM_GETLINK identifies a bridge from its own
   `linkinfo.type == "bridge"` and reports its link address;
2. AF_BRIDGE RTM_GETLINK supplies bridge-port membership and live bridge-VLAN
   membership.

This split is required for portability. Live systems have shown bridge devices
that are self-mastered in AF_BRIDGE, bridges whose members have top-level
`type: "dsa"`, Wi-Fi/other members with no useful top-level kind, and VLAN child
interfaces that must not become bridge ports. An empty bridge has no member
reference at all, so membership cannot define bridge existence.

If AF_BRIDGE names a master that generic link identity did not identify as a
bridge, the read is declared inconsistent rather than promoting the reference
into a guessed bridge.

## FDB shape is evidence, not provenance

`self`, missing/present master and missing/present `fdb.bridge` are retained as
reported fields. They are **not** classified as hardware-versus-software origin.

That rule was forced by live x86 software-bridge evidence: ordinary software
bridges can produce the same `self`/no-master shapes that initially looked like
switch-hardware reporting on Realtek DSA.

`scope.fdb.count` therefore means raw valid FDB observations before merge, not
"hardware entries" or "bridge entries".

All-zero lladdrs are rejected as unusable FDB identities. A Qualcomm target
produced large unstable runs of `00:00:00:00:00:00` rows with placeholder VLANs;
removing only the zero identity left a stable one-for-one match with the
non-zero `bridge -j fdb show` identities.

## Local-address derivation

`derived.local` is an exact join against addresses reported about this device:

- `topo.address` on port rows;
- `br.address` on bridge rows.

It is not inferred from the FDB `self` flag or from an observation occurring on
a bridge device. This matters both for correctness and for suppressing
irrelevant "this host may have moved/fanned out" hints about the device's own
addresses.

## The one permitted inference

An untagged FDB observation can omit a VLAN id. When the reporting port has a
reported PVID, the assembler resolves the row's derived VLAN from that PVID and
sets:

```text
vlan_source = pvid
```

A kernel-reported VLAN uses `vlan_source = fdb`. If neither exists the derived
VLAN/source are null. The inferred value is never used to decide raw observation
identity.

## Merging

Readers are merged without priority:

1. validate every reader result before accepting rows;
2. identify observations using the contract's subject/discriminator rules;
3. collapse equal ordinary claims and union registered set-valued fields;
4. withdraw disputed ordinary values and record all claims/conflicts;
5. derive once over the merged evidence;
6. stamp source attribution.

A single reader can legitimately report the same MAC on several ports. That is
several FDB observations, not a conflict.

## Snapshot lifecycle in LuCI

```text
press Update -> acquire snapshot -> current
                               old current -> previous
```

Only two snapshots are retained, both in browser memory. Queries/filtering do
not re-read hardware. The age label ticks locally without polling.

Diffing first checks compatible acquisition scope for `bridges`, `ports` and
`fdb`, including successful reader coverage. These are load-bearing because FDB
is the evidence being compared, port PVID can change resolved VLAN identity,
and bridge/port addresses can change `derived.local`. Names/neighbours are
annotation and do not block a forwarding diff.

The diff then keeps three identities separate. Raw appeared/vanished evidence
uses MAC + port + reported `fdb.vlan`, matching the backend observation
contract. Primitive user-visible placement uses MAC + port + effective
`derived.vlan`; this can collapse dual raw reports that resolve to the same
placement without changing raw identity. Movement inference uses the complete
qualifying remote-unicast MAC + port presence set.

A strong `moved` interpretation is produced only when the before presence set
contains exactly one port and the after set exactly one different port. The move
record retains every distinct effective VLAN observed on each side, including
an unresolved/null member where present. Primitive placements fully represented
by that move may be hidden to avoid duplication; any placement not represented
by it remains appeared/vanished evidence. A VLAN-only change on one port is
therefore never turned into a port move.

## Cost model

The potentially expensive operation is the AF_BRIDGE FDB dump on drivers that
walk switch hardware per port. Realtek DSA validation showed roughly
1.2–1.3-second complete snapshots on a Zyxel GS1920-24 rtl839x device. OpenWrt
exposed 28 DSA interfaces on that 24-port model, including its four additional
combo/SFP interfaces; other validated router targets were substantially faster.

The design accepts that cost because:

- acquisition happens once per explicit user action;
- the duration is measured/displayed;
- every query and comparison reuses the snapshot;
- nothing polls.

A future device where the duration looks broken is evidence to revisit snapshot
scope/UI, not a reason to silently introduce a different target-specific core
path.

## Current physical validation

The portability sweep has exercised:

- x86 software bridging (including no/empty/VLAN-filtered bridge cases);
- Realtek rtl839x and rtl838x DSA switches;
- Mediatek Filogic mixed wired/Wi-Fi/router bridging;
- Qualcomm ipq50xx and ipq40xx DSA/Wi-Fi targets.

The exact evidence and measurements belong in `docs/remediation.md`; replayable
cases belong in `docs/fixtures.md`.

## Repository layout

```text
l2-info/
├── README.md
├── CONTRIBUTING.md
├── CONVENTIONS.md
├── LICENSE
├── docs/
│   ├── getting-started.md
│   ├── principles.md
│   ├── architecture.md
│   ├── readers.md
│   ├── snapshot-format.md
│   ├── fixtures.md
│   ├── decisions.md
│   └── remediation.md
├── l2-info/                      backend package tree
├── luci-app-l2-info/             LuCI package tree
├── fixtures/                     replay evidence
├── tests/                        replay/unit/mechanical tests
├── tools/                        test install + hardware validation helpers
└── .github/workflows/ci.yml      mandatory repository integration checks
```

The monorepo is a development/review convenience. The intended upstream result
is two independent package contributions: backend to `openwrt/packages` and
view to `openwrt/luci`.


## Synchronous snapshot cost and transport ceiling

The snapshot request executes synchronously inside rpcd. `duration_ms` is therefore also the approximate rpcd event-loop blocking time for that request; measured rtl839x hardware FDB walks have taken about 1.2–1.3 seconds. The explicit/manual snapshot model and no-polling rule are intentional safeguards against multiplying that cost.

ubus/blobmsg has a finite message-size ceiling. The project does not invent truncation semantics before measuring a practical limit. Pre-upstream measurement is device-side: grow a bounded synthetic snapshot and verify both `ubus call l2-info snapshot` and the LuCI request through uhttpd/ubus, recording the largest successful payload and target/software versions.
