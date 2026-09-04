# Principles

**Document class:** normative. These are rules, not aspirations. Each states
what is required, why, how it is enforced mechanically, and what a violation
looks like so it can be recognised in review. A change to any principle needs
a decision record in `docs/decisions.md`.

Ordering is by how much each constrains the design, not by importance.

---

## P1 — No field is empty for two different reasons

Every collection in a snapshot carries a status describing why it holds what
it holds, adjacent to the data itself.

**Why.** An empty list means at least four distinct things: the read never
happened; the read happened and the table is genuinely empty; the read
happened, returned rows, and the field was absent from all of them because the
feature is off; or the read happened, returned nothing, and the reason is not
determinable from one sample. On a device nobody in this project owns, telling
these apart *is* the problem. A consumer that can read the data without also
reading its status will eventually present one of these as another.

**How.** Status is a sibling of the data, never a separate capabilities block a
renderer can forget to consult. The vocabulary is closed and defined in
`docs/snapshot-format.md`: `ok`, `unavailable`, `not_applicable`,
`indeterminate`. Anything other than `ok` carries a `reason` string.

**Enforcement.** The fixture harness validates every snapshot against the
schema: each collection key must have a sibling status, each status must be in
the vocabulary, and every non-`ok` status must have a reason. A fixture whose
expectations name only row contents and not scope fails as incomplete.

**Violation looks like.** A UI that shows an empty VLAN column. A snapshot
where `fdb: []` appears with no accompanying status. A `capabilities` object
listing booleans separately from the data they describe.

---

## P2 — Report, don't classify

The snapshot states what was read and counts what was found. It does not
assign roles, categories, or verdicts.

**Why.** "Port lan6: role `beyond`" compresses "three MACs on lan6" into a
label, discarding the count that justified it and importing a threshold, a
vocabulary, and a claim about the world. The uncompressed form is shorter, has
no tuned constants, gives the reader more to work with, and cannot disagree
with any other tool because it asserts nothing. A reader who cannot interpret
"3 MACs, VLANs 12/20/30" also cannot audit a classifier's answer.

This is the boundary between this project and a fleet-scale one. A fleet system
exists to make inferences no single device can make. If the narrow tool starts
inferring, it is not narrower — it is a worse copy with a smaller evidence
base.

**How.** Counts, sets, and reported values only. One exception exists (P3's
single derived value) and adding a second requires a decision record.

**Enforcement.** A banned-vocabulary check over the source: the tokens
`uplink`, `access`, `beyond`, `at_or_beyond`, and `direct` may not appear as
values, field names, or enum members. They may appear in comments and
documentation discussing this principle.

**Violation looks like.** Any field whose value is a judgement. Any constant
tuned against observed data. A `role`, `kind`, `type`, or `confidence` field on
a port or an FDB row.

---

## P3 — Provenance travels with the value

Reported facts and derived values live in separate places, and a derived value
carries the basis it was derived from.

**Why.** Exactly one inference is unavoidable. An untagged arrival carries no
VLAN id in the FDB, so a VLAN query that filters on the reported id silently
misses every untagged host on a matching port. Resolving it against the
reporting port's native VLAN is correct and necessary — and is an inference,
which must never be displayed or exported as if the kernel had said it.

**How.** Each row has `attrs`, holding only what the kernel reported, and
`derived`, holding joins, counts, and the one inference. Provenance is a
sibling field (`vlan_source`), not a wrapped value type — consistent with the
idiom used in the related fleet project.

The closed list of permitted derived values is in `docs/snapshot-format.md`.
Every entry on it is a join, a count, or a classification of an address against
a published constant. Adding to the list requires a decision record stating
which of those three it is; if it is none of them, P2 forbids it.

**Enforcement.** Two checks. The export path must not emit `derived` (assert on
a fixture-produced export). The render path must not read `attrs` directly — it
consumes a flattening step — so that display and export cannot drift in what
they consider a fact.

**Violation looks like.** A resolved VLAN inside `attrs`. An export containing
`derived`. A display that shows an inferred VLAN identically to a reported one.

---

## P4 — Absence is declared, never inferred from one sample

A capability is reported as absent only on positive evidence of absence. One
dump returning nothing is not that evidence.

**Why.** A switch that has learned nothing yet and a driver that does not
report its hardware table produce byte-identical evidence: zero entries. Any
tool that concludes "no hardware FDB" from that is guessing, and it is guessing
to an audience that by construction cannot detect the error — the reader who
needs the panel is the reader who cannot check it. The related fleet project
learned this expensively in the opposite direction, where a deny-list of known
identifiers missed 574 instances of a shape nobody had thought of.

**How.** The status vocabulary includes `indeterminate` specifically so this
case has somewhere honest to go. Where evidence is positive it is reported as
such: "112 entries, 87 from the switch table" is fact; "hardware FDB: yes" is a
lossy restatement of it.

**Enforcement.** No boolean field may be computed from the absence of rows in a
single dump. The fixture class for a driver without `port_fdb_dump` asserts
`indeterminate`, not `unavailable` and not a false negative.

**Violation looks like.** `hardware_fdb: false`. "VLAN filtering: off" derived
from seeing no VLAN ids rather than from reading the bridge's own filtering
flag. Any capability claim a second sample could overturn.

---

## P5 — Interpretation is presentation

The view may say "this likely means…". The data may not.

**Why.** Interpretation is genuinely useful — "0 entries: this could be an idle
switch, or a driver that doesn't report its hardware table" is the sentence
that saves an hour, and no classifier could write it because its content is the
uncertainty. But interpretation in the data layer is P2's classification with a
hedge attached, and hedges decay into assertions as they pass through a reader.

**How.** Four rules, all of which must hold:

- **H1.** A hint renders next to evidence and is never a field. Delete every
  hint and the app is still correct and complete; if deleting one loses
  information, it was a classification, not a hint.
- **H2.** A hint may only use values already displayed. Nothing hidden feeds
  it, so the reader can check the reasoning against the numbers beside it.
- **H3.** A hint of kind `likely` — one asserting a probable cause — must name
  at least two. Three MACs on a port is an unmanaged switch, or a hypervisor
  bridging guests, or a desk phone with a PC passthrough port. If a second
  cause cannot be named, the hint is a verdict and does not ship. A hint of
  kind `note` explains what is on the screen and asserts nothing about the
  world, so the rule does not bind it and would produce invented alternatives
  if it did (D39).
- **H4.** A hint is a pure function of displayed values, so its firing is
  testable.

**Enforcement.** Hint text does not appear in the export (P3's check covers
this). Fixture expectations name which hints fire for each device class, so
"class 4 fires the filtering-off hint and not the no-hardware-table hint" is an
assertion rather than an intention.

**Violation looks like.** A hint string in the snapshot. A single-cause
`likely` hint. A `note` that quietly asserts a cause. A hint drawing on a value
the user cannot see. Hint logic reaching back into raw netlink data. A `likely`
hint whose named causes are all wrong for some of the rows it fires on — H3
stops a hint being a verdict and does not stop it being irrelevant, so its
causes have to be checked against the rows it will actually fire on (D44).

---

## P6 — Freshness is explicit

Data is read when the user asks for it, and its age is always visible.

**Why.** The snapshot model exists so one expensive hardware read serves many
queries. Its cost is that everything on screen is as old as the last press. A
snapshot presented as current when it is four minutes old is the same class of
dishonesty as an undeclared empty field.

**How.** No polling and no auto-refresh anywhere. The snapshot carries its
capture time; the view renders both the timestamp and the elapsed time, and
ages visibly. Refresh is an explicit act with a visible cost — duration is
reported so the user learns what the read actually costs on their hardware.

**Enforcement.** The view must not use LuCI's `poll` module; checked by grep.
The snapshot schema requires `captured_at`.

**Violation looks like.** `poll.add`. A rendered table with no age indicator. A
refresh triggered by anything other than a user action.

---

## P7 — Read-only and stateless

The tool reads. It does not write, persist, or accumulate.

**Why.** It is a diagnostic. Every capability it does not have is a class of
bug it cannot have, a review question it does not have to answer, and an
upstream objection that does not arise. Statelessness is also what makes P6
honest: with nothing stored, there is no stale state to mistake for fresh.

**How.** No uci configuration file. Read-only ACL. Nothing written to disk. The
current and previous snapshots live in browser memory only and are lost on
navigation; `localStorage` is not used, because persisted data makes staleness
ambiguous in precisely the way P6 exists to prevent, and because a MAC
inventory in browser storage is a liability with no compensating benefit. The
export button covers the legitimate keep-it case.

**Enforcement.** The ACL file must contain no `write` section; checked by grep.
No `localStorage` or `sessionStorage` in the view; checked by grep. The package
ships no file under `/etc/config`.

**Violation looks like.** A settings page. A cached snapshot surviving a page
reload. Any write path added "just for convenience".

---

## P8 — Device coverage is enforced by fixtures, not asserted in prose

Every L2 arrangement the tool claims to handle has a fixture, and each fixture
asserts the declarations, not only the rows.

**Why.** "Device-agnostic" is otherwise a claim about hardware nobody in the
project owns. There is no CI on a LuCI app and no lab of switches; a replayable
fixture per device class is the only mechanism that turns the claim into
something checkable. Asserting on declarations rather than rows is what makes
it test P1 and P4 rather than just the parsing.

**How.** Fixtures are data, not code, at two seams. A *source* fixture holds
raw input as one reader's source emits it and asserts that reader's normalised
output. A *device* fixture holds normalised reader output — source-independent
— and asserts scope declarations, derived values and hint firing. The second
kind is why adding a device class is cheap: a swconfig device and a DSA device
produce fixtures in the same shape, run by the same harness, with no per-source
stub. The harness is a generic replayer and the runner iterates over whatever
directories exist. Layout, the starting classes, and the capture-and-redaction
path are in `docs/fixtures.md`.

**Enforcement.** The runner discovers fixture directories rather than listing
them, so an added class runs without a harness edit, and a class whose
expectations omit scope fails. Three seams are replayed: one reader against a
recorded source, the assembler against recorded reader output, and discovery
against a directory of reader files — the last because the other two start
after discovery, leaving manifest validation and api rejection otherwise
unexercised.

**Violation looks like.** A README claiming support for hardware with no
fixture. A test function per device class. Expectations that check row counts
and nothing else.

---

## P9 — A source declares what it can see

Every reader declares, in a manifest, which collections it can provide. The
assembler derives absence from those declarations rather than from an empty
result.

**Why.** P1 and P4 are otherwise per-call diligence: at each read site,
somebody has to remember to distinguish failure from emptiness and to resist
inferring a capability from one sample. With manifests, absence becomes a
computation. A collection claimed by no installed reader is declared
`not_applicable` with the reason naming that, which is strictly more
informative than "we looked and found nothing" — the best a monolith can
manage.

This is why the reader architecture is not merely more flexible than a single
code path. It makes the honesty principles compositional.

**How.** Manifest schema, discovery, and the `read()` contract are defined in
`docs/readers.md`. A reader declares `provides`, and returns a status for every
collection it claimed. Rows may only accompany a collection it declared `ok`.

**Enforcement.** Manifest validation rejects a reader whose `read()` omits a
claimed collection, or reports one it did not claim, or attaches rows to a
non-`ok` collection. A fixture with the reference reader absent asserts that
unclaimed collections are declared rather than rendered empty. A reader that
throws is recorded as `unavailable` and does not prevent a snapshot.

**Violation looks like.** A reader whose capability is discovered by trying it.
An empty collection with no reader accounting for it. A `provides` list that
does not match what `read()` returns. Any reader-specific branch in the core.

---

## Precedence

Where two principles appear to conflict, the earlier-numbered one wins, and the
conflict is a decision record rather than a judgement call made in code. The
one live tension is P2 against usefulness: a bare count is sometimes less
immediately helpful than a label. P5 exists to resolve that tension in the view
rather than by weakening P2.
