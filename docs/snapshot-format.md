# Snapshot format

**Document class:** contract. This document owns the backend snapshot envelope,
collection/status vocabulary, row vocabulary and versioning rules.

Format identifier: `l2-info.snapshot`, version `1`.

The backend returns this format from:

```sh
ubus call l2-info snapshot
```

The LuCI **Download JSON** action deliberately exports a privacy/portability
projection of the same snapshot: it keeps reported facts, source attribution,
declared scope and the self-describing envelope, but omits `derived` values and
presentation hints. It retains the same `format`/`version` because the reported
row vocabulary and scope contract are the same; consumers that require derived
fields must use the live backend snapshot rather than assume they are present in
an exported file.

## Design boundary

Rows separate three things:

- `subject` — what the row is about;
- `attrs` — facts a source actually reported;
- `derived` — joins, counts or classifications/inferences computed centrally by
  the assembler.

Source attribution is stamped by the assembler, not supplied by the reader.
Interpretive UI hints are never part of the snapshot.

Attribute names, collection names and subject kinds are a closed vocabulary.
Readers may add new **sources**; they may not invent new fields. A new field or
collection requires the corresponding design/decision update before code.

## Status vocabulary

Every collection has a sibling entry in `scope` with one of four statuses:

| Status | Meaning | `reason` |
|---|---|---|
| `ok` | The collection was successfully observed. Zero rows means zero observed rows. | absent |
| `unavailable` | A required read/source failed or could not be used. | required |
| `not_applicable` | The collection does not apply to the available source set/device state, including when no surviving installed reader provides it. | required |
| `indeterminate` | A read completed but the evidence cannot distinguish absence from an observation gap from this sample. | required |

A collection may also carry `note`: attributed explanatory evidence that does
not change an `ok` status, for example which naming files were read and found
empty, or that one reader failed while another successfully supplied the same
collection.

Consumers encountering a future/unrecognised collection status should treat it
conservatively as indeterminate rather than inventing success.

`skipped` is **not** a collection status. It may appear only under
`scope.readers` for an installed reader rejected during discovery/validation.

## Envelope

A backend snapshot has this shape:

```json
{
  "format": "l2-info.snapshot",
  "version": 1,
  "captured_at": "2026-09-06T10:00:00Z",
  "duration_ms": 396,
  "cost": "hardware-walk",
  "device": {
    "board": "linksys,ea8300",
    "model": "Linksys EA8300",
    "target": "ipq40xx/generic",
    "kernel": "6.12.94"
  },
  "scope": {
    "readers": {},
    "conflicts": [],
    "bridges": { "status": "ok", "count": 1 },
    "ports": { "status": "ok", "count": 11 },
    "fdb": { "status": "ok", "count": 175 },
    "neighbours": { "status": "ok", "count": 16 },
    "names": { "status": "ok", "count": 4 }
  },
  "bridges": [],
  "ports": [],
  "fdb": [],
  "neighbours": [],
  "names": []
}
```

`captured_at` is UTC ISO-8601. `duration_ms` covers the one user-triggered
snapshot acquisition. `cost` is aggregated from installed surviving readers and
is currently `software` or `hardware-walk`; it is a declared cost class, not a
measurement. `device` comes from `ubus call system board` and is descriptive
metadata rather than reader output.

## Scope

### Collection entries

Each registered collection has a `scope.<collection>` entry. `count` is the
number of valid **raw reader observations after source-boundary validation and
before cross-reader merging**. It therefore need not equal the number of
assembled rows in the top-level collection.

Where several readers claim a collection, rollup chooses the most conclusive
honest status: `ok` if any reader succeeded; otherwise `indeterminate`, then
`unavailable`, then `not_applicable`. A failure alongside a successful reader
remains visible as an attributed note rather than making the whole collection
unavailable.

FDB row shape is not interpreted as hardware/software provenance. In
particular `self`, presence/absence of a master bridge and missing
`fdb.bridge` are retained as reported facts only. `scope.fdb.count` is therefore
a neutral raw-observation count.

A successful FDB dump with zero rows is currently `indeterminate`: one sample
cannot distinguish a genuinely idle device from a driver/path that does not
make the relevant forwarding entries visible.

### `scope.readers`

Every discovered reader is represented, including rejected/unusable readers.
A successful entry may contain:

```json
"rtnl": {
  "status": "ok",
  "api": 1,
  "cost": "hardware-walk",
  "describe": "Kernel bridge and neighbour tables via netlink",
  "provides": ["bridges", "ports", "fdb", "neighbours", "names"]
}
```

A rejected reader uses `status: "skipped"` plus a reason; a reader whose
`read()` throws or cannot operate is reported as unavailable with a reason.
Reader health and collection status are deliberately separate.

### `scope.conflicts`

Conflicts are declared and never silently resolved:

```json
{
  "subject": { "port": "lan5" },
  "attr": "topo.vlan_pvid",
  "values": [
    { "source": "reader-a", "value": 12 },
    { "source": "reader-b", "value": 1 }
  ]
}
```

The array is always present, including when empty.

## Subject kinds

A row carries exactly one subject identity:

| Subject | Meaning |
|---|---|
| `{ "mac": "aa:bb:cc:11:22:33" }` | usable link-layer address |
| `{ "port": "lan2" }` | port/interface |
| `{ "bridge": "br-lan" }` | bridge device |
| `{ "self": true }` | the device as a whole (reserved/registered) |

For FDB observations, `00:00:00:00:00:00` is not a usable address identity and
is discarded at the source boundary. This is important on drivers that emit
large transient placeholder runs with unrelated-looking VLAN ids.

## Registered collections and attributes

| Collection | Registered attributes |
|---|---|
| `bridges` | `br.name`, `br.address`, `br.vlan_filtering` |
| `ports` | `topo.port`, `topo.bridge`, `topo.carrier`, `topo.address`, `topo.vlans`, `topo.vlan_flags`, `topo.vlan_pvid`, `topo.vlan_untagged` |
| `fdb` | `fdb.port`, `fdb.vlan`, `fdb.bridge`, `fdb.flags` |
| `neighbours` | `neigh.ips` |
| `names` | `name.hostname` |

A reader emitting any unregistered attribute fails its contract and is reported
rather than having the unknown field silently accepted.

Readers omit unavailable **attributes** rather than emitting `null`. Collection
status explains collection-level inability to observe data. Derived values may
use null where null is itself an explicit result of a join/inference (notably
resolved VLAN and its source).

## Observation identity and merging

A subject is not always one observation. One MAC may legitimately occur on
several ports simultaneously. FDB observations are therefore identified by:

```text
(subject.mac, fdb.port, reported fdb.vlan)
```

The registered discriminators are:

| Collection | Observation discriminators |
|---|---|
| `fdb` | `fdb.port`, `fdb.vlan` |
| `bridges`, `ports`, `neighbours`, `names` | none beyond subject |

The assembler does **not** use an inferred VLAN to decide whether two raw FDB
observations are identical.

`fdb.flags` and `neigh.ips` are set-valued: equal observations from one or more
sources union those values. For an ordinary non-set-valued attribute, equal
claims collapse; unequal claims withdraw the attribute from `attrs` and record
all claims in `disputed`, with a matching `scope.conflicts` entry.

Every assembled row carries `source`, either one reader id or an array of reader
ids that contributed to the observation.

## Bridge rows

Example:

```json
{
  "subject": { "bridge": "br-lan" },
  "attrs": {
    "br.name": "br-lan",
    "br.address": "02:00:00:00:00:01",
    "br.vlan_filtering": true
  },
  "derived": { "port_count": 4 },
  "source": "rtnl"
}
```

Bridge identity/address come from generic RTM_GETLINK. Bridge membership and
VLAN membership come from the AF_BRIDGE link view. An empty bridge can therefore
still be represented with `port_count: 0`.

`br.vlan_filtering` is read from the bridge's own state; it is not inferred from
whether VLAN ids happened to appear elsewhere.

## Port rows

Example:

```json
{
  "subject": { "port": "lan2" },
  "attrs": {
    "topo.port": "lan2",
    "topo.bridge": "br-lan",
    "topo.carrier": true,
    "topo.address": "02:00:00:00:02:01",
    "topo.vlans": [20, 30],
    "topo.vlan_flags": ["PVID Egress Untagged", ""],
    "topo.vlan_pvid": 20,
    "topo.vlan_untagged": [20]
  },
  "derived": {
    "mac_count": 3,
    "vlans_observed": [20, 30]
  },
  "source": "rtnl"
}
```

`topo.vlan_flags` is index-aligned with `topo.vlans` and uses the space-joined
text vocabulary shown by `bridge vlan show`: `PVID`, `Egress Untagged`, both, or
an empty string.

`mac_count` and `vlans_observed` describe this snapshot's assembled forwarding
observations on the port; they are counts/sets, not port-role classifications.

## FDB rows

Example with an untagged observation whose VLAN was resolved from the port's
PVID:

```json
{
  "subject": { "mac": "aa:bb:cc:44:55:66" },
  "attrs": {
    "fdb.port": "lan2",
    "fdb.flags": ["self"]
  },
  "derived": {
    "mac_class": "unicast",
    "local": false,
    "vlan": 20,
    "vlan_source": "pvid",
    "bridge": "br-lan",
    "on_bridge_device": false,
    "ips": ["192.0.2.15"]
  },
  "source": "rtnl"
}
```

`fdb.port` is present for a valid FDB row. `fdb.vlan`, `fdb.bridge` and
`fdb.flags` are present only when reported/applicable. Missing `fdb.bridge` is
not a hardware-provenance signal.

### FDB flag vocabulary

Tokens follow iproute2's `bridge fdb show` text vocabulary/order:

```text
self router extern_learn offload master sticky permanent static stale
```

At most one of the final state tokens is emitted by the current reader for one
observation.

## Neighbour and name rows

Neighbour annotation:

```json
{
  "subject": { "mac": "aa:bb:cc:44:55:66" },
  "attrs": { "neigh.ips": ["192.0.2.15", "2001:db8::15"] },
  "source": "rtnl"
}
```

Name annotation:

```json
{
  "subject": { "mac": "aa:bb:cc:44:55:66" },
  "attrs": { "name.hostname": "example-host" },
  "source": "rtnl"
}
```

Unresolved/failed neighbour entries with an all-zero hardware address do not
become address mappings. Naming sources are currently local lease/ethers files;
absence or emptiness is declared in collection scope rather than rendered as a
mysterious blank value.

## Permitted derived values

The list is closed. Each item is a join, count, classification against a
published constant, or the single permitted VLAN inference:

| Row | Field | Basis |
|---|---|---|
| bridge | `port_count` | count of reported member ports |
| port | `mac_count` | count of assembled FDB MACs observed on the port |
| port | `vlans_observed` | set of resolved VLANs represented by those observations |
| FDB | `mac_class` | address classification (`unicast`, `multicast`, `protocol`) against address constants/prefixes |
| FDB | `local` | exact join to a reported device port/bridge link address |
| FDB | `vlan` | reported `fdb.vlan`, otherwise the reporting port PVID when available |
| FDB | `vlan_source` | `fdb`, `pvid`, or null, making the preceding value's provenance explicit |
| FDB | `bridge` | reported FDB bridge or join through reporting-port topology |
| FDB | `on_bridge_device` | exact topology join indicating the reporting interface itself is a known bridge |
| FDB | `ips` | join to neighbour rows, present only when available |
| FDB | `hostname` | join to name rows, present only when available |

`vlan` and `vlan_source` are explicit nulls when neither the FDB nor the port
PVID supplies a VLAN. `ips` and `hostname` are omitted when no annotation is
available; consumers must not rely on a `hostname: null` placeholder.

## Export projection

The LuCI download is built from an allowlist. It keeps:

- `format`, `version`, `captured_at`, `duration_ms`, `cost`, `device`, `scope`;
- every collection's `subject`, `attrs`, `source`, and `disputed` where present.

It deliberately drops `derived` values and all presentation hints. This prevents
inferences/UI state from being mistaken for reported source facts and prevents
future view-only fields from leaking into an exported file by default.

Exports can still contain real MAC addresses, IP addresses and hostnames. See
`docs/getting-started.md` and `docs/fixtures.md` before sharing them publicly.

## Versioning

Version 1 is the first external contract intended for testing/upstream use.
Before a released/stable external version exists, development mistakes may be
corrected in place; D47 records the specific pre-release removal of invalid
hardware/software provenance counters.

After v1 is treated as a stable external interface:

- adding an optional field whose absence old consumers already tolerate can be
  compatible when its semantics do not change existing fields;
- removing/renaming a field, changing a field's meaning/type, changing subject
  identity or observation identity, or changing status semantics requires a
  format-version bump;
- readers have their own independent integer API version in `docs/readers.md`.

A consumer should always check both `format` and `version` before making strong
assumptions about row identity or derived semantics.
