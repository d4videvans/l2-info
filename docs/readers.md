# Readers

**Document class:** contract. This is the interface between the tool and the
things that can see L2 state. It is the only place the reader manifest, the
`read()` return shape, discovery, and merging are defined.

A reader is optional, separately packaged, and declares what it can see. The
core depends on exactly one (`rtnl`) and treats it identically to any other.
Readers are **trusted package code**: they are loaded into the rpcd process and
are subject to review and package trust in exactly the same way as the core.
The reader interface is a contract and a test seam, not a sandbox.

---

## 1. What is extensible, and what is not

**Sources are extensible. The vocabulary is not.**

A reader may bring a new way of seeing L2 state. It may not bring new field
names. If every reader could invent attributes, `docs/snapshot-format.md`
would stop being a contract, the export format would fragment per installed
package set, and no consumer could be written against it.

A reader that needs an attribute the format does not define is a documentation
change first — a decision record and an entry in the registered vocabulary —
and a reader change second. This ordering is not negotiable and is the reason
the plugin model does not dissolve the thing the plugins feed.

## 2. Module shape

A reader is one ucode file at:

```
/usr/share/l2-info/readers/<id>.uc
```

It is loaded with `loadfile()` and must **return a single manifest object**.
Loading must have no side effects: the manifest is inspected, validated, and
possibly rejected before `read()` is ever called. A reader that performs work
at load time cannot be safely skipped.

```
{
    id:       "rtnl",
    api:      1,
    describe: "Kernel bridge and neighbour tables via netlink",
    provides: [ "bridges", "ports", "fdb", "neighbours" ],
    cost:     "software",
    read:     function() { ... }
}
```

| Key | Required | Rules |
|---|---|---|
| `id` | yes | Must equal the filename stem. Lowercase, `[a-z0-9-]`. This makes duplicate ids impossible and the id unforgeable. |
| `api` | yes | Integer. The core declares which versions it supports; see §8. |
| `describe` | yes | One short phrase for the scope panel. Not a sentence, not marketing. |
| `provides` | yes | Non-empty array of registered collection names (§4). |
| `cost` | yes | `software` or `hardware-walk`; see §7. |
| — | — | Anything else in the manifest is ignored. |
| `read` | yes | Function taking a context; see §5. |

Anything else in the manifest is ignored. Validation failure means the reader
is skipped with a declared reason (§6), never a crash and never silence.

### One entry point, deliberately

There is no `applicable()`, no `probe()`, no `init()`, no `close()`. A reader
that is installed but irrelevant to this device reports `not_applicable`
through the ordinary return path. Every additional entry point is another
contract to specify, test and version, and none of them buys anything the
status vocabulary does not already provide.

## 3. Row contract

A row has exactly two keys.

```json
{
  "subject": { "port": "lan2" },
  "attrs":   { "topo.vlans": [20, 30], "topo.vlan_pvid": 20 }
}
```

**`subject`** carries exactly one identity key, from the registered set:

| Subject | Identifies |
|---|---|
| `{ "mac": "aa:bb:cc:11:22:33" }` | an address |
| `{ "port": "lan2" }` | a port or interface |
| `{ "bridge": "br-lan" }` | a bridge |
| `{ "self": true }` | this device as a whole |

Rows with equal subjects describe the same thing and are merged (§9). This is
one rule for every row type. Port facts therefore use `{port}` rather than
`{self}` with the port name in an attribute, which is a deliberate deviation
from the fleet project's C2 §6.1 self-description convention — that convention
was designed for an append-only spool where rows are never merged, and keying
a merge on an attribute value rather than on identity would need a second
merge rule for no gain (`docs/decisions.md` D30).

**`attrs`** carries registered attribute names only, and only values the
source actually reported. Omit an attribute rather than emitting `null`: a
present-but-null value is an empty field with two possible meanings, which is
P1's whole subject.

A reader **must not** emit:

- **`derived`** — any key at all. Joins, counts, classifications and the one
  permitted inference belong to the assembler, computed once over the merged
  row set. A reader that derives creates a second implementation of the same
  logic, and two implementations of one inference drift. This is the D7
  divergence problem one layer down, and it is the single most important rule
  in this document.
- **`source`** — the assembler stamps it from the manifest `id`. A reader
  cannot name itself, for the same reason a message cannot attest its own
  origin: provenance that the subject controls is not provenance.

## 4. Registered collections

| Collection | Contains |
|---|---|
| `bridges` | bridge existence and VLAN filtering state |
| `ports` | port membership, VLAN membership, link state |
| `fdb` | address-to-port-and-VLAN observations |
| `neighbours` | address-to-IP observations |
| `names` | address-to-hostname observations |

Adding a collection requires a decision record and an entry here.

## 5. `read(ctx)`

Returns per-collection status and rows. Nothing else.

### The context

A conforming reader imports no source module and binds nothing at load time:
the assembler hands it the source primitives it should use (D34).

| Field | Provides |
|---|---|
| `ctx.api` | the interface version in force for this call |
| `ctx.nl` | netlink: `request(cmd, flags, payload)`, `error()`, `const`. **May be null** |
| `ctx.fs` | `readfile(path)` and `access(path, mode)`, both returning null/false rather than raising |
| `ctx.ubus` | `call(object, method, args)`, returning null on failure |

The purpose of this context is **dependency injection and total fixture
replay**. It is not a capability boundary. Reader modules execute as trusted
code inside rpcd: ucode can import other modules directly, `ctx.nl` is a raw
rtnetlink handle, and `ctx.ubus.call()` is not restricted to a read-method
allowlist. Passing only observational helpers therefore does not make an
installed reader incapable of writing.

The contract still deliberately exposes no exec helper. A conforming reader
that needs to execute a program (a `swconfig` reader would) needs a decision
record and an api bump rather than quietly acquiring a new source dependency.
That is an architectural/review gate, not a sandbox: arbitrary installed code
could ignore the contract. If untrusted reader code ever becomes a requirement,
it needs an actual process/privilege boundary and a separate threat-model
decision rather than stronger wording around `ctx`.

`ctx.nl` being null is a normal case, not an error: the reader declares every
collection it claimed `unavailable` with that reason, which is what
`fixtures/sources/rtnl/no-rtnl` asserts.

```json
{
  "collections": {
    "ports": { "status": "ok" },
    "fdb":   { "status": "indeterminate",
               "reason": "dump returned no entries; an idle switch and a driver that does not report its table are indistinguishable from one sample" }
  },
  "rows": [ ]
}
```

Rules, all checkable:

1. Every name in `provides` **must** appear in `collections`. A reader that
   claims a collection and then says nothing about it has left a field empty
   for an undeclared reason.
2. A name not in `provides` **must not** appear in `collections`.
3. Status values come from the closed vocabulary in
   `docs/snapshot-format.md`: `ok`, `unavailable`, `not_applicable`,
   `indeterminate`. Anything other than `ok` requires a `reason`.
4. Rows may only belong to a collection whose status is `ok`. Rows attached to
   a non-`ok` collection are a contract violation, not a partial result.
5. `ok` with zero rows is legitimate and means zero. If zero cannot be
   distinguished from cannot-see, the status is `indeterminate` — that is what
   it is for (P4).

### Failure

If `read()` throws, the assembler catches it, records that reader as
`unavailable` with the exception message, and continues with the others. One
reader must never take down a snapshot. A fixture with a deliberately throwing
reader asserts this.

`read()` must not block indefinitely, must not retry unboundedly, must not
spawn background work, and must hold no mutable state between calls. It must
not write anything, anywhere (P7 applies transitively). These are obligations
on trusted reader code, enforced by review and tests where possible; they are
not containment guarantees against a malicious or defective installed module.

It must not read **another device**. Anything reachable over the network is a
second device, which is a fleet system's problem by definition and explicitly
out of scope (`docs/decisions.md` D23, D31).

## 6. Discovery

The reader directory is scanned at snapshot time. There is no config file, no
registry and no enable list.

1. List `/usr/share/l2-info/readers/*.uc`, sorted by id for deterministic
   output ordering. Order carries **no** precedence (§9).
2. `loadfile()` each; a load error means skip, declared.
3. Validate the manifest (§2); a validation error means skip, declared.
4. Check `api` against the supported set (§8); unsupported means skip,
   declared.
5. Call `read()` on each surviving reader.

Every skip appears in the snapshot's scope with a reason. A reader that is
installed but unusable is visible, not absent.

### Why the filesystem and not a config

- **A config file is state that can disagree with reality.** A reader enabled
  in config but not installed, or installed but disabled, is a class of
  confusing failure that need not exist. P7 already forbids a uci schema, and
  this is one of the reasons why.
- **It matches OpenWrt's own model.** `l2-info-reader-lldp` is a package;
  installing it adds capability and removing it removes capability, exactly as
  `ucode-mod-*`, `rpcd-mod-*` and `luci-app-*` already behave. Nothing to
  explain to a user or a reviewer.
- **It fixes the missing-dependency failure structurally.** A reader needing a
  binary is a package that *depends* on that binary, so if the reader is
  present its dependencies are present. The problem moves from runtime probing
  to package metadata, where it is actually solvable. This is the direct
  lesson of an entire capture channel silently emptying for two rounds in the
  fleet project because `ip-bridge` was not installed
  (`docs/decisions.md` D3).

### The reference reader has no special treatment

`rtnl` loads through this same path and is validated by the same rules. If the
core contains a literal reader id anywhere — a special case, a fallback, an
ordering exception — the abstraction is decorative and should be deleted
rather than maintained. A grep for reader-id literals outside the reader
directory enforces this.

## 7. Cost

`cost` is `software` or `hardware-walk`.

`hardware-walk` means the read touches switch hardware in a way that scales
with port count or table size — on rtl839x, a per-port walk of a
16384-entry table under the switch register mutex
(`docs/architecture.md`). The assembler aggregates declared cost so the view
can warn *before* an expensive read rather than reporting its duration
afterwards.

This is a declaration, not a measurement. The measured `duration_ms` is
reported separately and is the thing that would justify reopening D20.

## 8. Interface versioning

Readers are separately packaged and will drift from the core in both
directions.

- The manifest declares `api` as an integer. Current version: **1**.
- The core declares the set it supports. A reader outside that set is skipped
  with a declared reason — not crashed, not silently ignored, and not
  best-effort loaded.
- **Compatible, no bump:** adding an optional manifest key; adding a
  registered collection or attribute a reader may choose to provide.
- **Breaking, bump required:** adding a required manifest key; changing the
  `read()` return shape; changing the meaning of a status; changing the row
  contract.

A reader may declare support for one api version only. Multi-version readers
are not supported, because the branch inside them is exactly the
device-dependent behaviour this architecture exists to keep out of one code
path.

## 9. Merging

The assembler merges rows across readers. Order of discovery is not
precedence; there is no precedence.

1. Rows with equal subjects describe one entity.
2. The same attribute from two readers with **equal** values yields one value,
   with both sources recorded.
3. The same attribute from two readers with **unequal** values keeps both. The
   assembler records a `conflicts` entry in scope naming the subject, the
   attribute, and the readers involved.
4. Derived values are computed once, by the assembler, over the merged set.

**There is no conflict resolution policy, and none should be invented.** A
disagreement between two sources about what is on a port is information, not
an error to be hidden by picking a winner. The fleet project reaches the same
conclusion from the other direction, surfacing its own
`pvid_coverage_disagreement` rather than resolving it. Detection is a value
comparison; resolution would require a theory of which hardware lies, which
nobody has.

### Unclaimed collections

The assembler knows which collections are claimed by any surviving reader. A
collection claimed by none is declared:

```json
"bridge_vlans": {
  "status": "not_applicable",
  "reason": "no installed reader provides VLAN membership on this target"
}
```

This is strictly more informative than anything a monolith can say, because a
monolith can only report that it looked and found nothing. The manifest turns
P4's "declare, do not infer" from per-call diligence into a computation (P9).

## 10. Presentation

Merged facts display plainly: one row per subject, no source column, no
per-cell provenance badge.

Source attribution surfaces in exactly two places: the scope panel, which
reports per-reader status and counts; and any conflict, which must be visible
because it is the case where "plainly" would mean "misleadingly". Beyond that,
provenance is discoverable on demand — a tooltip, a detail view — and never
decorative.

The rigour belongs in the data. The view is a lookup tool, not a lecture.

## 11. Obligations for a reader to be merged

1. A fixture under `fixtures/sources/<id>/` with at least one case, asserting
   the reader's normalised output (`docs/fixtures.md`).
2. Manifest validation passes; `id` equals the filename stem.
3. No `derived` and no `source` emitted; registered attributes only.
4. Source reads use the supplied context rather than importing source modules,
   so fixture replay remains total. This is a conformance rule, not a security
   boundary.
5. Declared `cost`, honestly.
6. Package dependencies cover every runtime prerequisite, so the reader cannot
   be installed without what it needs.
7. A `NOTES.md` in its fixture directory saying which hardware or arrangement
   the capture came from, and what makes it distinctive.

A reader without a fixture is unmergeable. Adding a source requires adding the
evidence that it works — which is P8 applied to the extension mechanism rather
than only to the core.

## 12. Candidate readers

Recorded so the contract is judged against real cases rather than
hypotheticals.

**`lldp`** — per-port neighbour chassis id, port description and system name
from a local LLDP daemon. Valuable because it *reports* what fan-out
inference was deleted for guessing: an LLDP neighbour distinguishes "another
switch" from "several devices behind an unmanaged hub" as fact. Provides
`ports`.

**`swconfig-arl`** — the address table on pre-DSA swconfig targets. The current
reader contract deliberately provides no exec helper, so a conforming reader
which shells out needs a decision record and an api bump before it can exist
(§5). This is an interface/review constraint, not containment of arbitrary
installed ucode. `arl_table` is a real readable attribute on the ar8xxx driver
family. It is also the best available test of the manifest, because sibling
drivers differ: b53 implements only a flush operation and no read, so the same
reader honestly provides `fdb` on one chip family and reports `indeterminate`
on another.

**Out of scope:** anything reading another device — SNMP, ssh, a controller
API. That is a second device and belongs to a fleet system.

**Rejected:** debugfs hardware-table paths. Unstable format, root-only,
single-vendor. This is a reader nobody should write, rather than a category the
architecture forbids (`docs/decisions.md` D3 as amended).