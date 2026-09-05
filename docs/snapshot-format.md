# Snapshot format

**Document class:** contract. This is the stable interface between the backend,
the view, the export file, and any other consumer. It is the only place the
field vocabulary and the status vocabulary are defined; everywhere else is
navigation.

Format identifier: `l2-info.snapshot`, version `1`.

## What this is not

It is **not** C2, the observation format of the related fleet project, and it
must not claim to be. A one-shot query has no capture run, no sequence number,
no snapshot group id and no framing version, because those are properties of a
capture session and this is not one. A file that announced itself as C2 without
them would be either rejected by that project's converter or, worse, half
handled — a false oracle.

What it *does* borrow is the attribute vocabulary: field names under `fdb.*`
and `topo.*` follow C2 §6.1, and rows use the same `subject` / `attrs` shape.
That makes the export mechanically ingestible by an adapter on that side, which
is where session identity belongs. The borrowing is documented here so the
format stands on its own terms to a reader who has never heard of the other
project (`docs/decisions.md` D9).

## The vocabulary is closed

Attribute names, collection names and subject kinds are registered here and
nowhere else. Readers may bring new *sources* of data; they may not bring new
field names (`docs/readers.md` §1, `docs/decisions.md` D24). A reader needing
an attribute this document does not define is a decision record and an entry
here first, and a reader change second.

## Status vocabulary

Closed set. Every collection carries one (P1).

| Status | Meaning | `reason` |
|---|---|---|
| `ok` | The read succeeded. Zero rows means zero rows. | absent |
| `unavailable` | The read did not happen or failed. | required — what failed |
| `not_applicable` | The read happened; the feature is off, so there is nothing to report. | required — which feature |
| `indeterminate` | The read happened and returned nothing, and absence cannot be distinguished from emptiness from this sample. | required — what cannot be distinguished |

A collection may also carry `note`: free text a reader attached to a
collection it read successfully, attributed by reader id. Its use is to make an
`ok` with no rows legible — "read /etc/ethers; no address to name mappings in
them" is a real answer, and without the note it is indistinguishable at a
glance from having looked nowhere. A `note` never carries a status claim and
never appears where `reason` would.

`indeterminate` exists so P4 has somewhere honest to go. It is not a synonym
for "empty" and not a synonym for "failed".

**Consumers must treat an unrecognised status as `indeterminate`.** This is
what makes adding a status a compatible change.

## Envelope

```json
{
  "format": "l2-info.snapshot",
  "version": 1,
  "captured_at": "2026-09-03T19:54:02Z",
  "duration_ms": 812,
  "device": {
    "board": "zyxel,gs1920-24-v1",
    "target": "realtek/rtl839x",
    "kernel": "6.12.30"
  },
  "scope": {
    "readers": { },
    "conflicts": [ ]
  },
  "bridges": [ ],
  "ports":   [ ],
  "fdb":     [ ]
}
```

`captured_at` is required (P6). `duration_ms` covers all reads and is displayed
so the cost of a refresh is visible rather than mysterious. `device` comes from
`ubus call system board` and makes the snapshot self-describing, which matters
for a fixture contributed from hardware nobody here owns.

## Scope

One entry per collection, keyed by the collection it describes.

```json
"scope": {
  "bridges":    { "status": "ok", "count": 1 },
  "ports":      { "status": "ok", "count": 25 },
  "fdb":        { "status": "ok", "count": 112 },
  "neighbours": { "status": "ok", "count": 9 },
  "names":      { "status": "unavailable",
                  "reason": "/tmp/dhcp.leases and /etc/ethers both absent" }
}
```

### Collection status rollup

Where several readers claim one collection, its status is the most conclusive
honest answer available: `ok` if any reader returned `ok`, else
`indeterminate` if any did, else `unavailable` if any did, else
`not_applicable` (D38). Reasons are attributed by reader id, and appear as
`note` rather than `reason` when the rollup is `ok`, so a partial failure
alongside a success stays visible.

### Readers and conflicts

`scope.readers` reports one entry per reader found, whether or not it ran, so
an installed-but-unusable reader is visible rather than absent.

```json
"readers": {
  "rtnl": { "status": "ok", "api": 1, "cost": "software",
            "provides": ["bridges", "ports", "fdb", "neighbours"] },
  "lldp": { "status": "unavailable", "reason": "read() threw: connect: No such file or directory" },
  "swconfig-arl": { "status": "skipped", "reason": "manifest api 2 is not supported" }
},
"conflicts": [
  { "subject": { "port": "lan5" }, "attr": "topo.vlan_pvid",
    "values": [ { "source": "rtnl", "value": 12 },
                { "source": "swconfig-arl", "value": 1 } ] }
]
```

`skipped` appears only in `scope.readers` and describes reader health, not a
collection — the closed four-value vocabulary applies to collections. Reader
health and collection status are separate concerns: the first is the
assembler's, the second is the reader's (`docs/readers.md` §5).

Conflicts are declared, never resolved (`docs/decisions.md` D27). An empty
`conflicts` array is meaningful and is always present.

A collection claimed by no surviving reader is declared `not_applicable` with
a reason naming that, which is how P9 makes absence a computation rather than
an inference.

Notes that are contract, not commentary:

- `count` is counted over valid rows as read, before merging, so it says how
  many observations sources returned after source-boundary validation. FDB row
  shape is **not** interpreted as hardware/software provenance; `self` plus no
  master occurs on ordinary software bridges as well as on switch-oriented
  systems (D47). All-zero FDB placeholder rows do not count because they cannot
  form a valid `{mac}` subject (D49).
- `fdb.status` is `indeterminate` when the dump succeeded with zero rows, since
  an idle switch and a driver that does not expose relevant forwarding entries
  are indistinguishable from one sample.

## Bridge rows

Keyed by bridge, like every other collection, so one merge rule covers them
all (D36).

```json
{
  "subject": { "bridge": "br-lan" },
  "attrs": {
    "br.name": "br-lan",
    "br.address": "02:00:00:00:00:01",
    "br.vlan_filtering": true
  },
  "derived": { "port_count": 25 },
  "source":  "rtnl"
}
```

`br.vlan_filtering` is read from the bridge's own state, never inferred from
whether any VLAN ids happened to be seen (P4). `br.address`, when present, is
the bridge device's own link address reported by the generic link dump. It is
not inferred from a member port or from an FDB row (D47). Where VLAN filtering
state cannot be read, the `bridges` collection is `indeterminate` and carries
no rows, rather than rows with the attribute silently missing.

## Registered attributes

| Namespace | Attributes |
|---|---|
| `br.*` | `name`, `address`, `vlan_filtering` |
| `topo.*` | `port`, `bridge`, `carrier`, `address`, `vlans`, `vlan_flags`, `vlan_pvid`, `vlan_untagged` |
| `fdb.*` | `port`, `vlan`, `bridge`, `flags` |
| `neigh.*` | `ips` |
| `name.*` | `hostname` |

A reader may emit no other attribute name; the assembler rejects a row that
does, attributing the violation to the reader (`docs/readers.md` §3).

## Subject kinds

Registered set. A row carries exactly one identity key.

| Subject | Identifies |
|---|---|
| `{ "mac": … }` | a usable non-zero link-layer address |
| `{ "port": … }` | a port or interface |
| `{ "bridge": … }` | a bridge |
| `{ "self": true }` | this device as a whole |

For FDB observations specifically, `00:00:00:00:00:00` is not an address
identity and must not produce a row. Some drivers emit it as a transient or
placeholder lladdr while walking their forwarding table; treating it as a
subject invents one synthetic MAC and can attach unrelated placeholder VLANs
to real ports. Readers discard that identity at the source boundary, without
filtering the accompanying port, VLAN or flags for any non-zero address (D49).

### Observation identity

A subject is not always one observation. One MAC is legitimately on several
ports at once — every multicast group address is on all of them — and those are
distinct observations, not a disagreement about one.

So each collection declares the attributes that distinguish observations of the
same subject, and rows merge when the subject **and** those values match
(D40):

| Collection | Discriminators |
|---|---|
| `fdb` | `fdb.port`, `fdb.vlan` |
| `bridges`, `ports`, `neighbours`, `names` | none — the subject is the observation |

This is the same identity the diff uses, so a MAC moving port is one
observation ending and another beginning rather than one changing.

### Set-valued attributes

`fdb.flags` and `neigh.ips` accumulate across rows rather than conflicting.
Two rows reporting the same observation are not two sources disagreeing when
they carry complementary set-valued facts. The honest value is the union. No
hardware/software provenance is assigned from the presence of `self`, a master,
or the absence of one (D40, D47).

## Port rows

Keyed by port. This is a deliberate deviation from C2 §6.1, which describes
per-port facts with a `self` subject — a convention suited to an append-only
spool that never merges rows, and unusable as a merge key once more than one
reader can report per-port facts.

```json
{
  "subject": { "port": "lan2" },
  "attrs": {
    "topo.port": "lan2",
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

A port's bridge, carrier and address are **reported** by the link dump, so
they are `topo.bridge`, `topo.carrier` and `topo.address` in `attrs` — not
joins, and not derived (D35). `derived.bridge` on an *FDB* row is a genuine
join when that FDB observation did not itself carry `fdb.bridge`; keeping the
two apart is what stops the format's one inference from sitting among reported
values.

`topo.vlan_flags` is index-aligned with `topo.vlans` and carries the
space-joined text form (`"PVID Egress Untagged"`), matching what the
corresponding `bridge vlan show` text output produces, with an empty string
rather than a short array where a VLAN has no flags.

`topo.port` is retained alongside the subject: it is what the source reported,
and `attrs` holds reported values even where they duplicate an identity.

`mac_count` and `vlans_observed` are counts over this snapshot's own valid FDB
rows — reported quantities, not classifications (P2). Three MACs on a port is
displayed as three MACs on a port; what that implies is a hint (P5).

### Disputed values

Where two readers report different values for one non-set-valued attribute of
one observation, the attribute is **removed** from `attrs` and every claim is
recorded on the entity, with a matching entry in `scope.conflicts` (D27, D37):

```json
{
  "subject": { "port": "lan5" },
  "attrs":   { "topo.port": "lan5", "topo.bridge": "br-lan" },
  "disputed": {
    "topo.vlan_pvid": [ { "source": "aa-first", "value": 12 },
                        { "source": "bb-second", "value": 1 } ]
  },
  "source": [ "aa-first", "bb-second" ]
}
```

Keeping one value would be precedence by another name: whichever reader was
read first would silently win. With the value withdrawn, a consumer cannot
read a winner because there is none, and the absence propagates honestly — an
untagged address on that port resolves to `vlan: null`, not to the value that
happened to be first.

`disputed` is absent when there is nothing disputed.

### Source stamping

Every row carries `source`, a reader id, stamped by the assembler from the
manifest — never emitted by the reader itself, for the same reason a message
cannot attest its own origin (`docs/decisions.md` D32). Where a merged
attribute came from more than one reader in agreement, `source` is an array.

## FDB rows

```json
{
  "subject": { "mac": "aa:bb:cc:44:55:66" },
  "attrs": {
    "fdb.port": "lan2",
    "fdb.flags": ["self"]
  },
  "derived": {
    "bridge": "br-lan",
    "mac_class": "unicast",
    "vlan": 20,
    "vlan_source": "pvid",
    "on_bridge_device": false,
    "ips": ["10.0.20.50"],
    "hostname": null
  }
}
```

`attrs` contains `fdb.port` always, `fdb.vlan` only when the kernel reported
one, `fdb.bridge` only when the kernel reported one, and `fdb.flags` when any
flag or state applies. The absence of `fdb.bridge` is a reported structural
fact, not by itself evidence that the row came from a hardware table (D47).
An FDB row also requires a usable non-zero `subject.mac`; all-zero lladdrs are
source placeholders rather than address identities and are not emitted (D49).

### `fdb.flags` vocabulary

Tokens and ordering follow iproute2's own printing of `bridge fdb show`
(`fdb_print_flags()` then `state_n2a()`), so the values match what a human
sees at the shell and what a text-form parser produces:

`self`, `router`, `extern_learn`, `offload`, `master`, `sticky`, then at most
one state token from `permanent`, `static`, `stale`.

This deliberately merges flags and state into one array, as the text form does.
The JSON form of `bridge fdb show` separates them and its consumers commonly
drop state entirely; merging keeps `["self", "permanent"]` meaning what it
means at the shell (`docs/decisions.md` D19).

## Permitted derived values — closed list

Every entry is a **join**, a **count**, or a **classification against a
published constant**. Nothing else may be added without a decision record
stating which of the three it is; if it is none of them, P2 forbids it.

| Field | Kind | Basis |
|---|---|---|
| `bridge` | join | FDB row → its port's bridge, where the row does not report one |
| `mac_count` | count | FDB rows on this port in this snapshot |
| `port_count` | count | ports whose `topo.bridge` is this bridge |
| `vlans_observed` | count | distinct resolved VLANs on this port |
| `mac_class` | classification | `unicast` / `multicast` / `protocol`; group bit and a published prefix list |
| `local` | join | the address equals a reported `topo.address` or `br.address` of this device |
| `on_bridge_device` | join | the row's port is itself a bridge |
| `vlan` | **inference** | reported id, else the port's PVID |
| `vlan_source` | provenance | `fdb` when reported, `pvid` when inferred, `null` when neither |
| `ips`, `hostname` | join | neighbour tables and lease/ethers files |

`vlan` is the only inference in the format. It exists because a VLAN query that
filters on the reported id silently misses every untagged host on a matching
port. `vlan_source` is mandatory whenever `vlan` is present, and the view must
mark a `pvid` value visibly (P3).

### `mac_class` constants

`protocol` covers the published multicast and control ranges — IPv4 multicast
`01:00:5e`, IPv6 multicast `33:33`, STP/LLDP `01:80:c2`, Cisco `01:00:0c`,
DEC/OSI `09:00:2b` — plus the all-ones address and two exact values observed as
bridge-FDB self entries across a whole fleet without their registering protocol
being identified. `multicast` is any other address with the group bit set.
Everything else is `unicast`.

The all-zero address is intentionally absent from this classifier: D49 rejects
it before an FDB row exists. Valid rows are classified, never dropped; filtering
them out of a display is view policy (P2, P5).

## Export

The export file is this structure with `derived` removed (P3) and hint text
absent (P5), so the file contains reported facts, declared scope, and the
inputs a hint would have used, but no interpretation. `source`, `scope.readers`
and `scope.conflicts` are retained: they are reported facts about where data
came from, not interpretations of it. Filename carries the board name and the
capture timestamp.

The current snapshot only. Exporting the previous one is a second action.

## Versioning

`version` is an integer and appears in every snapshot.

**Compatible, no version bump:** adding a field; adding a status value; adding
a `fdb.flags` token; adding an entry to `scope`.

**Breaking, bump required:** removing or renaming a field; changing a field's
meaning or type; removing a status value; changing what an existing status
means.

The September 2026 hardening work is a one-time pre-release exception in
process, not in semantics: unreleased development drafts labelled version 1
contained `entries_switch_reported` / `entries_bridge_reported`, whose stated
meaning was disproved by live software-bridge evidence. They were removed, and
`br.address` was added, before there was an upstream or released v1 contract.
The version therefore remains 1 for the contract that will actually ship. Once
v1 is released or consumed as a stable interface, the breaking-change rule
above applies normally; this correction is not precedent for changing a
released v1 in place (D47).

Two rules make the compatible list actually compatible, and both are consumer
obligations:

1. **Ignore unknown fields.** Never reject a snapshot for containing something
   new.
2. **Treat an unknown status as `indeterminate`.** The safe reading of "I do
   not recognise this state" is "I cannot tell", never "fine" and never
   "broken".

The reader interface has its own independent version (`docs/readers.md` §8).
A snapshot format bump does not imply a reader api bump, or the reverse: the
two contracts have different consumers and different rates of change.
