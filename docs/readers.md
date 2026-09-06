# Readers

**Document class:** contract. This document owns the interface between the
assembler and code that can observe L2 state: manifest, discovery, `read(ctx)`,
collection ownership and merge obligations.

Readers are **trusted package code**. They are loaded into the rpcd process and
are reviewed/trusted on the same basis as the core package. Passing source
primitives in `ctx` is a dependency-injection/test seam, not a sandbox or a
privilege boundary.

The core currently ships one reader, `rtnl`. The architecture deliberately
keeps source acquisition extensible while the output vocabulary stays closed.

## 1. Sources are extensible; the vocabulary is not

A reader may add a new way of observing facts already registered in
`docs/snapshot-format.md`. It may not introduce new collection names,
attributes, subject kinds or derived fields merely by returning them.

A source that genuinely needs a new vocabulary item requires the format/design
decision first and the reader implementation second. This keeps every consumer
able to reason about one stable snapshot contract regardless of installed
reader set.

## 2. Module and manifest

A reader is a ucode file at:

```text
/usr/share/l2-info/readers/<id>.uc
```

Loading it with `loadfile()` must return one manifest object and must not perform
source reads or other side effects at load time.

The current core reader's manifest is equivalent to:

```javascript
{
    id:       'rtnl',
    api:      1,
    describe: 'Kernel bridge and neighbour tables via netlink',
    provides: [ 'bridges', 'ports', 'fdb', 'neighbours', 'names' ],
    cost:     'hardware-walk',
    read:     function(ctx) { /* ... */ }
}
```

| Key | Required | Contract |
|---|---|---|
| `id` | yes | Lowercase `[a-z0-9-]`; must equal filename stem |
| `api` | yes | Integer reader API version |
| `describe` | yes | Non-empty short source description |
| `provides` | yes | Non-empty array of registered collection names |
| `cost` | yes | `software` or `hardware-walk` |
| `read` | yes | Function taking the supplied context |

Unknown extra manifest keys are ignored. Invalid manifests are skipped with a
declared reason in `scope.readers`; they do not crash a snapshot and are not
silently absent.

There is deliberately no separate `probe()`, `applicable()`, `init()` or
`close()` entry point. Applicability belongs in collection status, and mutable
reader lifecycle state would conflict with the one-shot/stateless design.

## 3. Row contract

A reader row contains exactly source-level identity and reported attributes:

```json
{
  "subject": { "port": "lan2" },
  "attrs": {
    "topo.port": "lan2",
    "topo.vlan_pvid": 20
  }
}
```

The registered subject kinds and attributes are defined only in
`docs/snapshot-format.md`.

A reader must not emit:

- `derived` — joins, counts, classifications and the PVID inference are computed
  once by the assembler over the merged evidence;
- `source` — the assembler stamps provenance from the validated manifest id;
- unregistered attribute or collection names;
- `null` as a placeholder for an unread reported attribute.

A present-but-null reported attribute would make absence ambiguous. Collection
status and explicit source behaviour are used instead.

## 4. Registered collections

Current collection vocabulary:

| Collection | Contains |
|---|---|
| `bridges` | bridge identity/address/filtering facts |
| `ports` | interface membership, carrier and VLAN membership facts |
| `fdb` | forwarding address observations |
| `neighbours` | MAC-to-IP observations |
| `names` | MAC-to-hostname observations |

Adding a collection is a format/design change, not a reader-local extension.

## 5. `read(ctx)`

The assembler passes:

| Context field | Provides |
|---|---|
| `ctx.api` | reader API version in force |
| `ctx.nl` | rtnetlink handle (`request`, `error`, `const`), or null |
| `ctx.fs` | `readfile()` and `access()` wrappers returning null/false on failure |
| `ctx.ubus` | `call(object, method, args)` returning null on failure |

A conforming reader uses these primitives rather than importing its source
module directly. That makes fixture replay total without shipping a test-mode
branch. It does **not** prevent arbitrary installed ucode from importing other
modules; reader trust remains package-code trust.

The reader returns:

```json
{
  "collections": {
    "ports": { "status": "ok" },
    "fdb": {
      "status": "indeterminate",
      "reason": "dump succeeded with no entries; an idle device and an observation gap are indistinguishable from one sample"
    }
  },
  "rows": []
}
```

Rules:

1. Every collection named in `provides` appears in `collections`.
2. A collection not declared in `provides` does not appear there.
3. Status is one of the four values in `docs/snapshot-format.md`.
4. Every non-`ok` collection has a non-empty `reason`.
5. Rows may belong only to a collection whose status is `ok`.
6. `ok` with zero rows means zero observed rows; when zero cannot be
   distinguished from inability to observe, use `indeterminate`.
7. A reader may attach `note` to successful collection evidence when useful;
   the assembler carries it through attributed by reader id.

If `read()` throws, the assembler records that reader unavailable and continues
with other readers. A reader must not perform unbounded retries, retain mutable
state across snapshots, spawn background work or write device/network state.
These are conformance obligations on trusted code, not sandbox guarantees.

A reader must not read another device. Network-reachable remote state is outside
the single-device scope.

## 6. Discovery

Discovery happens for every snapshot:

1. list `/usr/share/l2-info/readers/*.uc`, sorted by id;
2. load each module;
3. validate manifest/id;
4. check reader API compatibility;
5. call `read(ctx)` for survivors.

Every rejection is represented in `scope.readers` with a reason. There is no
reader registry, UCI setting, enable list or priority value.

Filesystem discovery is intentional: installing/removing a reader package adds
or removes source capability without creating configuration state that can
disagree with what is actually installed.

The bundled `rtnl` reader receives no special treatment in the assembler. Tests
and mechanical checks enforce that there is no core branch keyed on the reader
id.

## 7. Cost

`cost` is a coarse declaration:

- `software` — reads are software-side and not expected to scale through switch
  hardware tables;
- `hardware-walk` — the reader may trigger a switch-table walk whose cost can
  scale with port count/table size.

The current `rtnl` reader is `hardware-walk` because an AF_BRIDGE FDB dump can
cause per-port hardware-table traversal on some DSA drivers even though the
same code path is cheap on ordinary software bridges.

Cost is aggregated before the snapshot and is separate from measured
`duration_ms`. Hardware validation, not fixture replay, is what establishes
real duration.

## 8. Reader API versioning

Current API: **1**.

The core advertises the set of supported integer API versions. An unsupported
reader is skipped and declared rather than best-effort loaded.

Compatible examples:

- adding an optional manifest key which old cores ignore;
- allowing a reader to provide an already-registered optional source fact.

Breaking examples requiring a reader API bump:

- adding a required manifest key;
- changing the `read(ctx)` call/return shape;
- changing status meaning;
- changing the row contract expected from a reader.

Snapshot-format versioning is separate and defined in
`docs/snapshot-format.md`.

## 9. Merging across readers

The assembler, not readers, owns merging.

Observation identity is defined in the snapshot contract. In particular FDB
observations are distinguished by MAC subject plus reported port and reported
VLAN, so one multicast address legitimately visible on several ports remains
several observations.

For the same observation:

1. equal ordinary attribute values collapse and retain multi-reader source
   attribution;
2. set-valued `fdb.flags` and `neigh.ips` are unioned;
3. unequal ordinary values are withdrawn from `attrs`, every claim is retained
   in `disputed`, and `scope.conflicts` records the conflict;
4. no reader wins by discovery order or declared priority;
5. derivation happens once after merging.

A conflict is evidence. Resolving it would require an external theory of which
source is authoritative, which this single-device diagnostic deliberately does
not invent.

## 10. Unclaimed collections

The assembler compares the registered collection set with the surviving reader
manifests. If no reader provides a collection, it is declared
`not_applicable` with an explicit reason, for example:

```json
"names": {
  "status": "not_applicable",
  "reason": "no installed reader provides names on this device"
}
```

This is structurally different from a reader successfully checking a naming
source and finding zero mappings; that would be `ok`, normally with a note
saying what was read.

## 11. Presentation and provenance

The normal lookup table is deliberately not covered in source badges. Merged
facts display plainly. Source attribution is always present in the data and is
surfaced where it matters most:

- reader/data-source details;
- conflicts/disputed values;
- exported JSON source fields.

The view's interpretive hints are presentation-only and do not belong in a
reader or snapshot source row.

## 12. Requirements for a new reader

A reader is not ready to merge unless it has:

1. a valid manifest and API version;
2. registered collections/attributes only;
3. no reader-emitted `derived` or `source`;
4. source reads through the supplied testable context;
5. honest `cost`;
6. package dependencies covering every runtime prerequisite;
7. at least one source fixture under `fixtures/sources/<id>/`, including
   `NOTES.md` describing the evidence/case;
8. appropriate device fixtures when the new source exposes a genuinely new
   arrangement or merge interaction.

A new source should not require a reader-id branch in the core. If it does, the
reader seam or the proposed source needs reconsidering.

## Candidate readers

These are design probes, not promised features:

- **LLDP:** local daemon data could report neighbour identity/description as
  evidence rather than inferring a downstream device from MAC fan-out.
- **legacy swconfig:** potentially useful for older non-DSA targets if a source
  can fit the contract and package its dependencies cleanly.

Neither is needed for the current pre-upstream release. The forum/test phase is
a good place to discover whether real users/hardware justify either.
