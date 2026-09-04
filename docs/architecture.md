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
| 2 | Link identity | generic `RTM_GETLINK` | interface kind; bridge identity from `linkinfo.type == "bridge"` |
| 3 | Bridge links | `RTM_GETLINK`, `family=AF_BRIDGE`, `ext_mask` | ports, bridge membership, carrier, per-port VLAN membership with PVID and untagged flags |
| 4 | FDB | `RTM_GETNEIGH`, `family=AF_BRIDGE` | MAC, port, VLAN id, state and flags |
| 5 | Neighbours | `RTM_GETNEIGH`, `family=AF_INET` / `AF_INET6` | MAC → IP, for recognisability |
| 6 | Names | `/tmp/dhcp.leases`, `/etc/ethers` | MAC → hostname |

These are the core reader's reads, not the tool's: a third-party reader has its
own list and declares which collections it covers. Reads 1–4 are load-bearing.
Reads 5–6 are annotation: on a pure L2 switch they are legitimately near-empty,
which is a declared `ok`-with-zero-rows or `unavailable`, never a blank column
(P1).

Every read goes through one wrapper that checks `rtnl.error()` and returns
either rows or an error, so a failure can never be rendered as an empty table.
The two link dumps are deliberately coupled for the `bridges` and `ports`
collections: if generic link identity and AF_BRIDGE membership cannot both be
read consistently, those collections are declared unavailable rather than one
view being promoted into a substitute for the other (D46).

Read 6's presence is probed per call rather than cached, because a lease file
only exists once a first lease has been issued and that can happen after this
process started.

## Why netlink, and only netlink

`ucode-mod-rtnl` covers every device where a Linux bridge exists, which is
every current OpenWrt device. Two alternatives were considered and rejected
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
are the fixture classes (`docs/fixtures.md`).

1. **DSA with hardware FDB reporting.** The switch driver implements
   `port_fdb_dump`, so hardware-learned addresses reach the kernel FDB.
2. **DSA without it.** `port_fdb_dump` is optional in DSA and many drivers omit
   it; only software-learned entries appear, with nothing in the data marking
   that as the reason. This is the case P4 exists for.
3. **Software bridge, VLAN filtering on.** No switch hardware involved; entries
   carry VLAN ids.
4. **Software bridge, filtering off.** No entry carries a VLAN id and no
   per-port VLAN attributes exist, so every VLAN answer is empty — correctly,
   and indistinguishably from class 3 unless the filtering flag is read and
   declared.
5. **Bridge-per-VLAN.** Tagging happens at the netdev layer, one bridge per
   VLAN. The VLAN ids present are each bridge's internal default rather than
   the real 802.1Q tag, so per-port VLAN data is near content-free and must not
   be presented as segment membership.

### The one thing that can be probed structurally

Class 1 and class 2 are distinguishable *when there is traffic*, because the
two sources are marked differently in netlink. DSA reports hardware entries
with `NTF_SELF` and no `NDA_MASTER`; the software bridge reports its own with
`NTF_MASTER` or a master. So a snapshot containing `self`-without-master
entries is positive evidence that this device reports a hardware table.

The converse is not evidence: zero such entries could be an idle switch or a
driver that never reports one. That asymmetry is exactly P4, and it is why the
status vocabulary has `indeterminate`.

Classes 3–5 are readable from the link dumps and the bridge filtering flag.
Bridge existence itself comes from the generic link kind, independently of
whether the bridge has members (D46). Class 5 is additionally suggested by the
board/target and by every bridge having exactly one VLAN.

## Kernel behaviour this design depends on

Verified against current sources and hardware observations, and worth
restating because several are counter-intuitive.

- **Bridge identity is in the generic link kind, not AF_BRIDGE membership.**
  `ucode-mod-rtnl` decodes `IFLA_INFO_KIND` as `linkinfo.type`. On an x86/64
  OpenWrt 25.12.5 system (kernel 6.12.94), every software bridge appeared as
  `linkinfo.type: "bridge"` in a generic RTM_GETLINK dump. In the AF_BRIDGE
  dump the same bridge devices had `linkinfo: null` and appeared self-mastered.
  `/sys/class/net/*/bridge` agreed with the generic link-kind set. This was a
  development probe; `l2-info` itself was not installed on that box, so it is
  not package-level compatibility evidence (D46).
- **`rtnl_fdb_dump()` filters by ifindex.** Setting the request header's
  ifindex causes the kernel to skip every other netdev, so a port-scoped dump
  invokes `port_fdb_dump` once rather than once per port. This tool does not
  use it — consistency requires a single dump — but the mechanism is why the
  full-scan cost below is what it is, and why per-port scoping remains
  available if the cost proves unacceptable (`docs/decisions.md` D20).
- **DSA hardware entries carry no bridge.** `dsa_user_port_fdb_do_dump()` emits
  `NDA_LLADDR` and `NDA_VLAN` only, with `ndm_flags = NTF_SELF` and
  `ndm_state = NUD_NOARP` when static, `NUD_REACHABLE` otherwise. There is no
  `NDA_MASTER`, so the bridge a MAC belongs to must be joined from the link
  dump. A tool that reads the bridge from the FDB row alone shows nothing on
  DSA hardware.
- **`NDA_VLAN` is omitted when the id is zero**, i.e. for untagged arrivals and
  on non-filtering bridges. This is the source of the single permitted
  inference (P3).
- **Duplicate rows are legitimate.** With assisted learning on the CPU port,
  one address can appear twice: once from the hardware table and once from the
  software bridge. Distinct `(mac, port, vlan)` triples are never collapsed;
  only exact repeats of one triple are.
- **`RTEXT_FILTER_*` is not exported by `ucode-mod-rtnl`**, so the ext_mask
  value is a numeric literal with a reference to `linux/if_link.h`.

## Cost model

The expensive read is #4, and only on switch hardware.

On the realtek DSA driver, `port_fdb_dump` walks the entire hardware L2 table
for each port, holding the switch register mutex, with `cond_resched()` every
64 entries. Table size is 16384 entries on rtl839x and rtl930x, 8192 on
rtl838x, plus a 64-entry CAM. An unfiltered dump on a 24-port switch is
therefore on the order of 390,000 register-read iterations serialised on that
mutex.

This is accepted deliberately (`docs/decisions.md` D2, D20). The snapshot model
means it happens once per user action rather than once per query, the duration
is measured and displayed so the cost is visible rather than mysterious, and
nothing polls. Reads 1–3, 5 and 6 are software-only and negligible; D46's extra
generic link dump is in that negligible group.

Payload is not a constraint: a real 24-port switch snapshot is a few hundred
rows, and at roughly 400 bytes per row that is well under a megabyte.

## Assembly order

1. Discover readers: scan, load, validate manifests, check api. Every skip is
   recorded in `scope.readers` with a reason.
2. Call `read()` on each survivor. An exception is caught, recorded against
   that reader, and does not prevent a snapshot.
3. Merge rows by subject. Equal values from two readers collapse with both
   sources recorded; unequal values are both kept and a `conflicts` entry
   raised. No precedence, no resolution.
4. Declare scope: per-reader status, per-collection status, and
   `not_applicable` for any collection no surviving reader claimed.
5. Derive once over the merged set, from the closed list in
   `docs/snapshot-format.md`.
6. Stamp `source` on every row from the manifest id.

Steps 3–6 belong to the assembler alone. Cost is aggregated from the manifests
at step 1, so an expensive read can be warned about before step 2 rather than
reported after it.

## Snapshot lifecycle in the view

```
press Update ──▶ snapshot() ──▶ becomes current
                                previous ◀── former current (older discarded)
```

Two snapshots at most, in memory, lost on navigation (P7). Queries filter the
current snapshot. The diff compares current against previous.

**Scope compatibility is checked before diffing.** If the FDB read succeeded in
one snapshot and failed in the other, a naive diff reports every MAC as
removed — wrong, and entirely plausible-looking. P1 makes this a check rather
than a special case: compare declarations first, refuse or degrade explicitly.

Row identity for diffing is `(mac, port, vlan)`, giving four primitive changes:
appeared, vanished, port changed, VLAN changed. "Moved" is an interpretation of
a vanish/appear pair sharing a MAC, so it is a hint under P5 and not a field.
Where one side's VLAN was inferred from PVID and the other's was reported, the
change claim is weaker than it looks — which is the provenance discipline of P3
paying for itself at the one point a user makes a decision from the output.

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
│       ├── rpcd/ucode/l2-info            assembler + ubus surface
│       └── l2-info/readers/rtnl.uc       the one core reader
├── luci-app-l2-info/             view package
│   ├── Makefile
│   ├── htdocs/luci-static/resources/view/l2-info/main.js
│   ├── po/
│   └── root/usr/share/
│       ├── luci/menu.d/luci-app-l2-info.json
│       └── rpcd/acl.d/luci-app-l2-info.json
├── fixtures/
│   ├── sources/<reader>/<case>/  raw source input → reader output
│   └── devices/<class>/          normalised reader output → snapshot
└── tests/
    ├── run.sh                    discovers and replays every fixture
    └── replay.uc                 generic stub: fixture directory in, snapshot out
```

The two packages target two different upstream trees, so this monorepo is a
development convenience. Upstreaming splits them (`docs/decisions.md` D17).

## Installation surface on the device

| File | Purpose |
|---|---|
| `/usr/share/rpcd/ucode/l2-info` | assembler and ubus surface; read by rpcd, not executed, no exec bit needed |
| `/usr/share/l2-info/readers/rtnl.uc` | the core reader; discovered by directory scan, not registered |
| `/usr/share/rpcd/acl.d/luci-app-l2-info.json` | read-only ACL for the two ubus methods |
| `/usr/share/luci/menu.d/luci-app-l2-info.json` | menu entry, gated on that ACL |
| `/www/luci-static/resources/view/l2-info/main.js` | the view |

rpcd scans its ucode directory only at startup, so installing or changing the
backend requires `/etc/init.d/rpcd restart`. The LuCI menu is cached in `/tmp`
and must be cleared for a new entry to appear.

Dependencies: `rpcd-mod-ucode` and `ucode-mod-rtnl` for the backend,
`luci-base` for the view. No others (`docs/decisions.md` D3). A reader package
carries its own dependencies, which is what makes a missing prerequisite
impossible rather than merely unlikely (`docs/readers.md` §6).
