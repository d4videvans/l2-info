# Architecture

**Document class:** canonical structure and mechanism. Rules live in
`docs/principles.md`; the data contract lives in `docs/snapshot-format.md`;
this document owns components, boundaries, kernel interfaces, and cost.

## Components

```
                        browser
  ┌───────────────────────────────────────────────┐
  │ luci-app-l2-info    view (JS)                 │
  │   current + previous snapshot in memory       │
  │   filtering · diff · hints · export           │
  └───────────────────┬───────────────────────────┘
                      │ ubus over LuCI RPC, read-only ACL
  ┌───────────────────▼───────────────────────────┐
  │ l2-info             rpcd ucode plugin         │
  │  ┌─────────────────────────────────────────┐  │
  │  │ assembler                               │  │
  │  │   discover readers · call read()        │  │
  │  │   merge by subject · declare scope      │  │
  │  │   derive once · stamp source            │  │
  │  └───────┬──────────────────┬──────────────┘  │
  │          │                  │                 │
  │  ┌───────▼───────┐  ┌───────▼───────────────┐ │
  │  │ reader: rtnl  │  │ reader: <third party> │ │
  │  │ (core)        │  │ optional, packaged    │ │
  │  └───────┬───────┘  └───────┬───────────────┘ │
  └──────────┼──────────────────┼─────────────────┘
             │ netlink          │ its own source
  ┌──────────▼──────────────────▼─────────────────┐
  │ kernel: bridge FDB · bridge VLANs · links     │
  │         neighbour tables        · other       │
  └───────────────────────────────────────────────┘
```

`l2-info` is loaded in-process by rpcd, so there is no fork per call and no
cost at all when nothing is querying it. It has no LuCI dependency and is
independently useful: `ubus call l2-info snapshot`.

## The one boundary that matters

**Derivation is backend. Filtering is view.**

Anything that computes a fact about the network — a join, a count, an address
classification, the single permitted inference — happens in ucode and lands in
the snapshot, so that every consumer (the view, a shell, a script, another
tool) gets identical answers. Anything that decides what to *show* — the port
filter, the MAC substring match, hiding multicast, hint text — happens in the
view.

The failure this prevents is a snapshot whose meaning depends on which client
rendered it. It is also why `snapshot()` takes no arguments: a filtered read
would put view policy in the backend and, worse, make two queries return
mutually inconsistent data.

There is a second boundary of the same kind one layer down: **readers report,
the assembler derives.** A reader emits `subject` and `attrs` only; joins,
counts, classification and the single inference happen once, in the assembler,
over the merged row set. Without that rule a plugin architecture becomes N
implementations of one inference, drifting — the same failure that removed the
role vocabulary, relocated inside this codebase where it would be harder to
spot. The contract is in `docs/readers.md`; the reasoning is
`docs/decisions.md` D32.

## Method surface

One method. `snapshot()`, no arguments, returns the structure defined in
`docs/snapshot-format.md`.

Everything the tool answers is a question about one snapshot, so a second
method would either duplicate a subset of the first or reintroduce per-query
reads. Adding a method requires a decision record.

## Reads performed by the `rtnl` reader

| # | Source | Interface | Yields |
|---|---|---|---|
| 1 | Board | `ubus call system board` | board name, target, kernel — makes the snapshot self-describing |
| 2 | Link identity | generic `RTM_GETLINK` | interface kind; bridge identity from `linkinfo.type == "bridge"`; bridge link address |
| 3 | Bridge links | `RTM_GETLINK`, `family=AF_BRIDGE`, `ext_mask` | ports, bridge membership, carrier, per-port VLAN membership with PVID and untagged flags |
| 4 | FDB | `RTM_GETNEIGH`, `family=AF_BRIDGE` | MAC, port, VLAN id, state and flags, master where reported |
| 5 | Neighbours | `RTM_GETNEIGH`, `family=AF_INET` / `AF_INET6` | MAC → IP, for recognisability |
| 6 | Names | `/tmp/dhcp.leases`, `/var/dhcp.leases`, `/etc/ethers` | MAC → hostname |

These are the core reader's reads, not the tool's: a third-party reader has its
own list and declares which collections it covers. Reads 1–4 are load-bearing.
Reads 5–6 are annotation: on a pure L2 switch they are legitimately near-empty,
which is a declared `ok`-with-zero-rows or `unavailable`, never a blank column
(P1).

Every netlink read goes through one wrapper that checks `rtnl.error()` and
returns either rows or an error. `ucode-mod-rtnl` represents a successful
zero-row multipart dump as `null` with no error, so the wrapper normalises that
specific pair to an empty array (D48). A failure and an empty result therefore
remain distinguishable.

The two link dumps are deliberately coupled for the `bridges` and `ports`
collections: if generic link identity and AF_BRIDGE membership cannot both be
read consistently, those collections are declared unavailable rather than one
view being promoted into a substitute for the other (D46).

Read 6's presence is probed per call rather than cached, because a lease file
only exists once a first lease has been issued and that can happen after this
process started.

## Why netlink, and only netlink

`ucode-mod-rtnl` covers the Linux bridge and neighbour interfaces this core
reader needs. Two alternatives were considered and rejected
(`docs/decisions.md` D3):

- **`bridge -j fdb show`** requires the `ip-bridge` package, which is not
  installed by default. In the related fleet project its absence silently
  emptied an entire capture channel for two capture rounds. A dependency that
  can be missing is a P1 violation waiting to happen, and shelling out buys
  nothing netlink does not already provide.
- **debugfs (`/sys/kernel/debug/rtl83xx/l2_table`)** would walk one vendor's
  hardware table in a single pass rather than once per port, which is
  genuinely cheaper on that hardware. It is rejected on principle: a
  single-vendor, unstable-format, root-only debug interface makes behaviour
  depend on which switch you are standing in front of, which is the opposite
  of the design goal. Not "not yet" — out.

Device-agnosticism is therefore achieved by *declaring* rather than by
branching. There is one code path in the core; what varies is what that path
can see, and the snapshot says which.

D3 as amended narrows this to *undeclared, unconditional, core* dependence
(`docs/decisions.md` D3, D24). A separately packaged reader with a manifest is
permitted, because the core's behaviour still does not vary by device — a
device without a given reader gets a declaration, not silence. Debugfs remains
out on its own merits rather than by category.

## What actually varies between devices

Five arrangements, all of which produce correct-but-different snapshots. These
are useful fixture classes (`docs/fixtures.md`).

1. **DSA where the driver exposes switch FDB entries through the kernel.** The
   device/driver may make additional forwarding observations visible.
2. **DSA where it does not.** Relevant forwarding entries may be absent from a
   single dump, with nothing in that empty sample proving why. This is the case
   P4 exists for.
3. **Software bridge, VLAN filtering on.** No switch hardware is involved, but
   the AF_BRIDGE FDB can still contain `self` rows and rows without a master.
4. **Software bridge, filtering off.** VLAN ids may be absent from forwarding
   observations; the filtering flag is the positive topology fact that tells
   the view what the bridge is configured to do.
5. **Bridge-per-VLAN.** Tagging happens at the netdev layer, one bridge per
   VLAN. Per-port bridge-VLAN data alone must not be promoted into a claim
   about an external segment without matching reported evidence.

### FDB row shape is not a hardware/software discriminator

The GS1920 cross-check originally suggested a convenient structural split:
`self` with no master appeared on the switch-oriented path, while rows carrying
a master appeared through the bridge-oriented path. That observation remains
useful for that device and driver, but the generalisation is false.

On x86/64 OpenWrt 25.12.5 with a pure software Linux bridge and no switch ASIC,
many FDB rows also carried `self` and no `fdb.bridge`. The development build's
old `entries_switch_reported` / `entries_bridge_reported` counters therefore
reported a supposed "switch" population on a system where no switch hardware
existed. D47 removes those fields.

The architecture keeps the raw facts — `fdb.flags`, `fdb.bridge`, port, VLAN —
and refuses the provenance classification. `scope.fdb.count` is simply the
number of raw FDB observations before merging. An empty successful FDB dump
remains `indeterminate` when one sample cannot establish whether the table is
truly empty or observation coverage is incomplete (P4).

Classes 3–5 remain readable from the link dumps and bridge state without using
FDB row shape as provenance. Bridge existence comes from the generic link kind,
independently of whether the bridge has members (D46).

## Kernel behaviour this design depends on

Verified against current sources and hardware observations, and worth
restating because several are counter-intuitive.

- **Bridge identity and address are in the generic link view, not AF_BRIDGE
  membership.** `ucode-mod-rtnl` decodes `IFLA_INFO_KIND` as `linkinfo.type`.
  On x86/64 OpenWrt 25.12.5 (kernel 6.12.94), software bridges appeared as
  `linkinfo.type: "bridge"` in generic RTM_GETLINK; the same bridge devices in
  AF_BRIDGE could expose `linkinfo: null` and appear self-mastered. The
  production backend was then installed and a deliberately empty `l2probe0`
  was reported as one bridge with zero ports. Generic RTM_GETLINK also provides
  the bridge link address, now emitted as `br.address` (D46, D47).
- **`rtnl_fdb_dump()` filters by ifindex.** Setting the request header's
  ifindex causes the kernel to skip every other netdev, so a port-scoped dump
  can avoid a full-device walk. This tool does not use that path — consistency
  requires one whole snapshot — but it remains the fallback if measured cost
  ever makes the current model unusable (`docs/decisions.md` D20).
- **DSA can emit FDB observations without `NDA_MASTER`.** That is a fact about
  those driver paths, not a portable provenance classifier for arbitrary FDB
  rows. Where an FDB observation has no `fdb.bridge`, `derived.bridge` may join
  from the reporting port's topology.
- **`NDA_VLAN` may be omitted when no VLAN id is reported**, including the
  untagged/non-filtering cases that motivated the single permitted PVID
  inference (P3).
- **Duplicate observations are legitimate.** One address may be reported more
  than once with different raw VLAN/master/flag fields. Distinct
  `(mac, port, vlan)` observations are never collapsed on the strength of an
  inferred VLAN; exact observation identity and set-valued merge rules are D40.
- **`RTEXT_FILTER_*` is not exported by `ucode-mod-rtnl`**, so the ext_mask
  value is a numeric literal with a reference to `linux/if_link.h`.

## Local-address derivation

`derived.local` is an exact join against addresses reported about this device.
Originally only `topo.address` on port rows participated. The x86 empty-bridge
case exposed the missing half: an empty bridge has its own link address and FDB
observations but no member port whose `topo.address` can carry that value.

D47 therefore registers `br.address` from the generic RTM_GETLINK row and adds
it to the same join. This does **not** say that every FDB row whose port is a
bridge is local, and it does not interpret `self` as locality. A matching
reported device address is required.

That distinction matters to the view: local addresses are excluded from
movement/fan-out interpretations that would otherwise describe the device's own
MAC as a mysteriously mobile client.

## Cost model

The expensive read is #4, and primarily on switch hardware whose driver walks
a hardware table for each port.

On the realtek DSA driver, `port_fdb_dump` walks the entire hardware L2 table
for each port, holding the switch register mutex, with `cond_resched()` every
64 entries. Table size is 16384 entries on rtl839x and rtl930x, 8192 on
rtl838x, plus a 64-entry CAM. An unfiltered dump on a 24-port switch is
therefore on the order of 390,000 register-read iterations serialised on that
mutex.

This is accepted deliberately (`docs/decisions.md` D2, D20). The snapshot model
means it happens once per user action rather than once per query, the duration
is measured and displayed so the cost is visible rather than mysterious, and
nothing polls. Reads 1–3, 5 and 6 are software-side and negligible beside that
hardware walk; D46's generic link dump and D47's bridge-address capture add no
new source read.

Payload is not a constraint: a real 24-port switch snapshot is a few hundred
rows, and at roughly 400 bytes per row that is well under a megabyte.

## Assembly order

1. Discover readers: scan, load, validate manifests, check api. Every skip is
   recorded in `scope.readers` with a reason.
2. Call `read()` on each survivor. An exception is caught, recorded against
   that reader, and does not prevent a snapshot.
3. Merge rows by observation identity. Equal values from readers collapse with
   source attribution; disputed non-set values are withdrawn and recorded as
   conflicts. No precedence, no resolution.
4. Declare scope: per-reader status, per-collection status and raw observation
   count, and `not_applicable` for any collection no surviving reader claimed.
5. Derive once over the merged set, from the closed list in
   `docs/snapshot-format.md`.
6. Stamp `source` on every row from the manifest id.

Steps 3–6 belong to the assembler alone. Cost is aggregated from the manifests
at step 1, so an expensive read can be identified from the installed readers
rather than guessed from device class.

## Snapshot lifecycle in the view

```
press Update ──▶ snapshot() ──▶ becomes current
                                previous ◀── former current (older discarded)
```

Two snapshots at most, in memory, lost on navigation (P7). Queries filter the
current snapshot. The diff compares current against previous.

**Scope compatibility is checked before diffing.** The load-bearing collections
for FDB comparison are now `bridges`, `ports` and `fdb`: FDB is the evidence
being compared; port PVID can change resolved VLAN identity; and both port and
bridge addresses can change `derived.local`. Names and neighbours are annotation
only and do not block a diff. Successful reader coverage for the same three
collections is compared as well (D12, D47).

If one load-bearing read succeeds in one snapshot and fails in the other, a
naive diff can turn a coverage change into a plausible network change. P1 makes
this a check rather than a special case: compare declarations first and refuse
the strong comparison when coverage differs.

Row identity for diffing is `(mac, port, vlan)`, giving primitive appeared and
vanished evidence from which a port move is interpreted only in the unambiguous
1→1 remote-unicast case. Where one side's VLAN was inferred from PVID and the
other's was reported, the move is marked weak rather than presented as equal
provenance.

## Repository layout

```
l2-info/
├── README.md
├── CONVENTIONS.md
├── LICENSE                       Apache-2.0
├── docs/
│   ├── principles.md
│   ├── architecture.md
│   ├── snapshot-format.md
│   ├── fixtures.md
│   └── decisions.md
├── l2-info/                      backend package
│   ├── Makefile
│   └── files/usr/share/
│       ├── rpcd/ucode/l2-info            ubus surface
│       └── l2-info/
│           ├── assemble.uc               assembler
│           └── readers/rtnl.uc           the core reader
├── luci-app-l2-info/             view package
│   ├── Makefile
│   ├── htdocs/luci-static/resources/
│   │   ├── view/l2-info/main.js
│   │   └── l2-info/{hints,query,diff}.js
│   ├── po/
│   └── root/usr/share/
│       ├── luci/menu.d/luci-app-l2-info.json
│       └── rpcd/acl.d/luci-app-l2-info.json
├── fixtures/
│   ├── sources/<reader>/<case>/  raw source input → reader output
│   └── devices/<class>/          normalised reader output → snapshot
└── tests/
    ├── run.sh
    ├── replay-source.uc
    ├── replay-device.uc
    └── replay-discovery.uc
```

The two packages target two different upstream trees, so this monorepo is a
development convenience. Upstreaming splits them (`docs/decisions.md` D17).
