# Decisions

**Document class:** register. Every architectural decision, its status, why it
was taken, and what it costs. Rationale lives here; the resulting rules live in
`docs/principles.md` and the resulting structures in `docs/architecture.md` and
`docs/snapshot-format.md`.

Statuses: **settled** (in force), **deferred** (deliberately not now, with the
condition that would reopen it), **open** (needed before the code it governs is
written), **superseded** (with a pointer).

---

## D1 — Its own repository — settled

Not a directory inside the fleet project. The two share a vocabulary and a set
of lessons, and nothing else: different scope, different lifecycle, different
audience, different upstream. A subdirectory would inherit the other project's
conventions, its documentation lifecycle tests, and its licence, none of which
fit here, and would make the standalone packages awkward to extract later.

*Cost:* the borrowed vocabulary can drift out of alignment. Mitigated by D9
making the borrowing explicit and versioned rather than implicit.

## D2 — Snapshot-and-query, not query-per-read — settled

One `snapshot()` per user action; all subsequent questions answered from that
snapshot in the view. Supersedes the original per-query design, in which each
search performed its own dumps.

Three reasons, the third of which was not the motivating one:

1. The expensive hardware read is amortised across every query.
2. Everything on screen comes from one instant, so two answers cannot
   inconsistently disagree in a way indistinguishable from a bug.
3. Whole-device counts (`mac_count`, `vlans_observed`) are computable at all.
   A port-scoped read structurally cannot count MACs per port across the
   device.

*Cost:* staleness becomes possible, which P6 exists to handle.

## D3 — Netlink only; no `ip-bridge`, no debugfs — settled

`ucode-mod-rtnl` is the single data path. `bridge -j fdb show` is rejected
because `ip-bridge` is not installed by default and its absence silently
emptied an entire capture channel for two rounds in the fleet project — a
dependency that can be missing is a latent P1 violation. Reading
`/sys/kernel/debug/rtl83xx/l2_table` is rejected on principle despite being
cheaper on that hardware: single-vendor, unstable format, root-only, and it
makes behaviour depend on which switch you are in front of.

*Cost:* on realtek hardware the tool pays a per-port table walk where a
single-pass path exists. Accepted; see D20.

### Amendment (D24)

D3 as first written forbade device-specific read paths outright. That is
narrowed, explicitly rather than by reinterpretation, to what its rationale
actually supports:

> D3 forbids **undeclared, unconditional, core** dependence on a
> device-specific read path. It does not forbid a **declared, optional,
> separately-packaged** one.

The distinction is the manifest. With one, the core's behaviour does not vary
by device: a device without a given reader gets an honest declaration rather
than silent emptiness (P9). The core package still depends on
`ucode-mod-rtnl` and nothing else.

Debugfs hardware-table paths remain out, now on their own merits — unstable
format, root-only, single-vendor — which makes them a reader nobody should
write rather than a category the architecture prohibits.

## D4 — Two packages — settled

`l2-info` (backend, rpcd ucode plugin, no LuCI dependency) and
`luci-app-l2-info` (view, menu, ACL). The backend is independently useful on a
headless device via `ubus call l2-info snapshot`, and reusable by other tooling
without pulling in LuCI.

The ACL belongs to the LuCI package, since it grants a LuCI session access to
the object. The CLI path therefore costs nothing extra: no separate binary, no
argument parsing.

## D5 — Name `l2-info`; menu title is not the package name — settled

Package `l2-info` / `luci-app-l2-info`; ubus object `l2-info`; menu title
descriptive, e.g. "MAC & VLAN Lookup", under Status.

`bearings` names the fleet project and means nothing to a stranger.
`topology` overstates what one device can know. `luci-app-fdb` is too narrow
given the ports and VLAN panels. `switch-info` is wrong because this works on
any bridge. `-info` additionally signals read-only to a reviewer.

Two consequences that follow from D4: the ubus object must **not** be under
`luci.*`, which signals LuCI-only and would be flagged upstream for a package
with no LuCI dependency; and "L2" is acceptable in a package name but fails the
menu's audience, who by construction do not know what they are looking at.

*Cost:* the `resolve` step adds IPs and hostnames, which are L3. Defensible as
L2 data annotated for recognisability, but the name slightly overpromises.

## D6 — Derivation in the backend, filtering in the view — settled

Joins, counts, address classification and the single inference happen in ucode
and land in the snapshot. Port filters, MAC substring matching, hiding
multicast, and hint text happen in the view.

Prevents a snapshot whose meaning depends on which client rendered it, and is
why `snapshot()` takes no arguments.

## D7 — Report, don't classify — settled

Supersedes an earlier intention to port the fleet project's wired role
vocabulary (`uplink` / `access` / `beyond` / `at_or_beyond` / `direct`) to this
tool.

The observable is "three MACs on lan6". The label compressed that into a
verdict, imported two tuned thresholds, and would have disagreed with the
fleet system immediately: that system's VLAN-coverage denominator counts
multicast self-rows that carry no bridge field, which dragged one switch's
pseudo-port to zero coverage. This tool classifies MAC class up front and would
have excluded them, producing a different answer for the same port — two
implementations of one inference, drifting, with a regression test pinning one
of them.

Reporting the counts dissolves the conflict rather than managing it. It is also
the correct boundary: a fleet system exists to make inferences a single device
cannot. A narrow tool that infers is not narrower, it is a worse copy.

*Cost:* a bare count is sometimes less immediately helpful than a label. D8 is
how that is recovered.

## D8 — Interpretation allowed, in the view, under four rules — settled

The view may say "this likely means…", governed by H1–H4 in
`docs/principles.md`: never a field, only from displayed values, at least two
plausible causes, and a pure function so its firing is testable.

The most valuable hint is not about fan-out but about scope: "0 entries — this
could be an idle switch, or a driver that doesn't report its hardware table" is
the sentence that saves an hour, and its content is the uncertainty, so no
classifier could produce it.

The two-cause rule is the load-bearing one. A single-cause hint is a verdict
wearing a hedge, and hedges decay into assertions as they pass through a
reader.

## D9 — Own export format, borrowing C2's attribute vocabulary — settled

Format `l2-info.snapshot`, version 1. Field names under `fdb.*` and `topo.*`
follow C2 §6.1 and rows use the `subject`/`attrs` shape, but the file does not
claim to be C2 and carries none of C2's session fields (`run`, `seq`, `snap`,
framing version) because a one-shot query has none of those properties.

A file claiming to be C2 without them would be rejected by that project's
converter or, worse, half handled — a false oracle. Session identity is minted
by an adapter on the collector side, which is where the question "which run
does this belong to" can actually be answered.

This also removes the upstream awkwardness: the file explains itself rather
than explaining another project. The `subject`/`attrs`/`derived` split is
defensible entirely on its own terms.

## D10 — Current and previous only — settled

Two snapshots, in memory. Pressing Update discards the older. The diff shows
both timestamps rather than "since last refresh".

A history would need retention policy, storage, and a staleness model — the
apparatus D2's whole point was to avoid. Two is enough for the actual
troubleshooting question, which is "did this move".

## D11 — No browser persistence — settled

No `localStorage`, no `sessionStorage`. Snapshots are lost on navigation.

Persisted data makes staleness ambiguous in exactly the way P6 exists to
prevent, and a MAC inventory in browser storage is a liability with no
compensating benefit. The export button covers the legitimate keep-it case.

## D12 — Diff identity is `(mac, port, vlan)`, scope-compared first — settled

Four primitive changes: appeared, vanished, port changed, VLAN changed.
"Moved" is an interpretation of a vanish/appear pair sharing a MAC, so it is a
hint under D8 and not a field.

Scope compatibility is checked before diffing. If the FDB read succeeded in one
snapshot and failed in the other, a naive diff reports every MAC as removed —
wrong and plausible-looking. Where one side's VLAN was PVID-inferred and the
other's reported, the change claim is weaker than it looks and must be
presented as such.

## D13 — One permitted inference — settled

The PVID fallback for untagged arrivals, carried as `vlan` with mandatory
`vlan_source`.

Directly adopted from the fleet project's own correction: ~25% of one real
switch's FDB rows carried no VLAN id at all, and resolving them against the
reporting port's native VLAN removed spurious duplicate attachments (13 rows
for 11 MACs became 11 for 11). Without it a VLAN query silently misses every
untagged host on a matching port.

Adding a second inference requires a decision record. The closed list of
permitted derived values in `docs/snapshot-format.md` is the enforcement point.

## D14 — Fixtures as data, discovered not listed — settled

One directory per device class, generic replayer, runner iterates over whatever
exists. Expectations assert scope declarations and hint firing, not only rows.

"Easy to add a class later" is usually false by the third one; making the
fixture data and the harness generic is what keeps the marginal cost near zero.

## D15 — Redaction by positive rewrite — settled

Deterministic MAC remapping into a documented synthetic range with a stable
within-capture mapping; hostnames and IPs dropped rather than remapped;
conventional interface and bridge names kept, unconventional ones replaced;
board, target and kernel kept.

A deny-list can only catch what it already knows about — the fleet project's
first anonymiser missed 574 long-form DHCP client-ids for exactly that reason.
Rewriting happens before anything is written to disk, so an unredacted capture
never exists as a file to send by accident, and the guardrail check runs over
every fixture in the tree rather than only at capture time.

## D16 — Apache-2.0 — settled

Matches LuCI, which is the tree the view package targets, and matches the
closest existing precedent (`luci-app-sfp-info`). The fleet project's GPL-3.0
is not carried over; nothing is shared as code, only vocabulary and lessons.

## D17 — Upstream target: two trees — settled as intent, work deferred

`luci-app-l2-info` to `openwrt/luci` (`applications/`), `l2-info` to
`openwrt/packages`. This monorepo is a development convenience; upstreaming
splits them.

Constraints this imposes *now*, not later, because they propagate through every
file: descriptive naming (D5), no dependency beyond `rpcd-mod-ucode`,
`ucode-mod-rtnl` and `luci-base` (D3), no uci schema (P7), read-only ACL (P7),
i18n from the first commit with every string through `_()` and `po/templates/`
generated, and no debugfs (D3).

*Deferred:* the actual submission, and the detailed review of current
`openwrt/luci` contribution requirements, which should be re-read at submission
time rather than trusted from memory.

## D18 — Every read behind one seam — settled

All kernel and file reads go through a single wrapper that distinguishes
failure from emptiness and returns one of the four statuses.

Two independent reasons: it is what makes P1 mechanical rather than a matter of
diligence at each call site, and it is what makes fixture replay total, so no
test can accidentally reach a real kernel.

## D19 — `fdb.flags` merges flags and state, text-form style — settled

Tokens and order follow iproute2's own text output. The JSON form of `bridge
fdb show` puts state in a separate field, and consumers commonly drop it: the
fleet project's own JSON parser reads only the flags array, so a v2 capture
loses `permanent`/`static`/`stale` entirely while a v1 text capture keeps them
in the same array. Two downstream analyses there depend on those tokens being
present.

Merging keeps `["self", "permanent"]` meaning at the API what it means at the
shell. Worth raising as a separate finding against that project's converter.

## D20 — Full-device scan accepted; per-port scoping retained but unused — settled

`snapshot()` always dumps every port. The kernel supports scoping a dump by
ifindex — `rtnl_fdb_dump()` skips every other netdev — but using it would break
D2's consistency guarantee and make the whole-device counts impossible.

The cost is real and hardware-specific: on rtl839x a full dump is on the order
of 390,000 register-read iterations serialised on the switch register mutex.
Mitigated by being once per user action, measured, displayed, and never polled.

*Measured:* **1.34 s** for a full snapshot on a GS1920-24 v1 (rtl839x, kernel
6.18.44), reported as `duration_ms: 1308`. That settles the question in favour
of the snapshot model: acceptable for something a person presses, and clearly
unacceptable to poll. No UI change needed and no per-port scoping.

*Condition to reopen:* a device where the measured duration is long enough to
look broken. The response would be a UI change — require a port selection
before reading, and declare the snapshot's scope as that port — not a second
data path. The scope field already has somewhere to say so.

## D21 — `capture` method for fixture contribution — open

`ubus call l2-info capture` emitting raw netlink responses in fixture layout,
with D15's redaction applied before writing.

Needed because coverage cannot grow past the maintainers' own hardware, which
upstreaming makes a certainty. It is also the only justified second ubus method
(D6 argues one method; this is not a query).

*Settled since:* the raw-versus-normalised question, by D26 — capture emits
both, because they are fixtures at two different seams testing two different
things.

*Still to settle before building:* whether capture belongs in the backend
package or a separate contributor script, and whether the redaction mapping
should be reproducible across captures from the same device or deliberately
not.

## D22 — Menu placement and panel set — open

Status is the right menu section. Undecided: whether the L2-facts panel
(board, target, per-bridge filtering, collection counts) is a section of the
one page or a separate page, and how the query, results, diff and panel
sections are ordered.

Presentation detail generally is deliberately not specified in these documents
beyond what P5 and P6 require.

## D23 — Rejected: a channel inside the fleet agent — settled

That agent is deliberately monolithic and spool-oriented; an on-demand query is
a structurally different mechanism, and that project's own spec defers
request-driven snapshots explicitly. D4's split gives the agent access to this
data without changing its shape, should it ever want it.

## D24 — Reader architecture: sources extensible, vocabulary frozen — settled

L2 state is read through readers: optional, separately packaged ucode modules
declaring a manifest and one `read()` function, contracted in
`docs/readers.md`. The attribute and collection vocabulary is **not**
extensible — a reader needing a new attribute is a decision record and a
format change first, a reader change second.

Three reasons for the seam, in order of weight:

1. **It makes the honesty principles compositional** (P9). Absence stops being
   per-call diligence and becomes derivable from the manifests: a collection
   claimed by no reader is declared, with a reason naming that.
2. **It fixes the missing-dependency failure structurally.** A reader needing a
   binary is a package that depends on it, so presence of the reader implies
   presence of its prerequisites — the direct lesson of D3's `ip-bridge`
   incident, moved from runtime probing to package metadata.
3. **It gives the deleted role vocabulary an honest replacement.** An LLDP
   reader *reports* a neighbour where D7 would have *inferred* one.

The frozen vocabulary is what stops the plugin model dissolving the contract
the plugins feed. Extensibility in sources; deliberately none in field names.

*Cost:* an abstraction for one reader, discussed under D28.

## D25 — Discovery is the filesystem; no config, no precedence — settled

Readers are discovered by scanning `/usr/share/l2-info/readers/*.uc`. No
config file, no enable list, no priority ordering. `id` must equal the
filename stem, so duplicate ids are impossible and a reader cannot misname
itself.

A config file is state that can disagree with what is installed, which P7
already rules out for uci; filesystem discovery matches how `ucode-mod-*`,
`rpcd-mod-*` and `luci-app-*` already work, so installing a package adds
capability and removing it removes capability with nothing to explain.

Discovery order exists only to make output deterministic and carries no
precedence, because D27 declines to resolve conflicts at all.

## D26 — Two fixture seams — settled

`fixtures/sources/<reader>/<case>/` holds raw input as a source emits it and
asserts that reader's normalised output. `fixtures/devices/<class>/` holds
normalised reader output and asserts scope declarations, derived values and
hint firing.

Conflating them is why "easy to add a class later" usually turns out false: a
single seam either forces a per-source stub into the device harness, or leaves
reader parsing untested. Because device fixtures are source-independent, a
swconfig device and a DSA device produce fixtures in the same shape for the
same harness — and a device class can be contributed for hardware whose reader
already exists without touching reader code.

`capture` emits both, so raw input and the reader's interpretation of it can be
cross-checked. This settles the open sub-question in D21.

## D27 — Conflicts are declared, never resolved — settled

Where two readers report different values for one subject and attribute, both
are kept and the assembler records a `conflicts` entry naming subject,
attribute and readers. There is no precedence, no priority field, and no
resolution policy.

A disagreement about what is on a port is information. Resolving it silently
requires a theory of which hardware lies, which nobody has; the fleet project
reaches the same conclusion from the other direction by surfacing its own
coverage disagreement rather than picking a winner. Detection is a value
comparison and costs nothing.

## D28 — Contract specified in full; seam implemented; one reader shipped — settled

The reader contract is specified completely now. The seam — a directory scan
and one function boundary — is implemented now. Exactly one reader (`rtnl`)
ships. Conflict *resolution*, priority and cross-source reconciliation are
specified as absent (D27) rather than deferred as unbuilt.

Building a plugin system for a single plugin is a known way to waste time. The
countervailing argument, accepted here, is that designing to a contract forces
better boundaries than designing to a single implementation: the rule that
readers may not emit `derived` is what keeps derivation in one place, and it
only becomes visible once a second producer is imaginable.

The test that keeps this honest: `rtnl` loads through the same discovery path
as any third-party reader, validated by the same rules, with no reader-id
literal anywhere in the core. A grep enforces it. If a special case appears,
the abstraction is decorative and should be deleted rather than maintained.

## D29 — Reader api is versioned; unsupported readers are skipped and declared — settled

The manifest declares `api` as an integer, currently 1. The core declares the
set it supports; a reader outside it is skipped with a declared reason, not
crashed and not best-effort loaded. A reader declares one api version only —
a multi-version reader contains exactly the device-dependent branch this
architecture exists to keep out.

Readers are separately packaged and will drift from the core in both
directions, so this is not optional ceremony.

## D30 — Port rows use `subject: {port}` — settled

Port facts are keyed `{ "port": "lan2" }`, not `{ "self": true }` with the
port name as an attribute.

A deliberate deviation from the fleet project's C2 §6.1 self-description
convention, which was designed for an append-only spool where rows are never
merged. Keying a merge on an attribute value would need one merge rule for
port rows and another for address rows; identity-keyed subjects give one rule
for every row type — equal subjects describe the same thing. Required as soon
as more than one reader can report per-port facts.

*Cost:* the export is one step further from ingestible-as-is by the fleet
project, which D9 already accepted by not claiming to be C2.

## D31 — Readers may not read another device — settled

No SNMP, no ssh, no controller API. Anything reachable over the network is a
second device, and cross-device work is a fleet system's problem by
definition (D23).

Stated as a reader obligation rather than left implicit, because the reader
architecture is exactly the mechanism by which someone would otherwise add it
in good faith.

## D32 — Readers report; only the assembler derives — settled

A reader emits `subject` and `attrs` and nothing else. `derived` is computed
once by the assembler over the merged row set. `source` is stamped by the
assembler from the manifest id, never by the reader.

The first half prevents N implementations of one inference — D7's divergence
problem one layer down, and this time inside a single codebase where it would
be harder to notice. The second half is the same reasoning the fleet project's
validator applies when it re-originates identity fields on messages it
forwards: provenance the subject controls is not provenance.

## D33 — Merged presentation is plain; attribution surfaces on conflict or on demand — settled

The view shows one row per subject with no source column and no per-cell
provenance badge. Attribution appears in the scope panel, and on any conflict,
because that is the case where plain display would be misleading. Otherwise
provenance is discoverable rather than decorative.

The rigour belongs in the data layer. A lookup tool whose every cell carries an
epistemic annotation is a worse lookup tool, and P5 already establishes that
interpretation belongs in presentation — this is the same boundary seen from
the other side.

## D34 — `read(ctx)`: readers are handed their primitives — settled, corrected

Amends `docs/readers.md` §2 and §5, which specified `read()` as taking no
arguments. The assembler passes a context carrying `api`, `nl` (the netlink
handle, or null), `fs` (readfile and access) and `ubus` (call). A conforming
reader uses those source primitives rather than binding a source module at load
time.

The surviving reason is **total fixture replay without a production test
hook**. With a compile-time `import ... from 'rtnl'`, the ways to replay a
fixture are a global the production code consults or shadowing the module
search path. Both put test concerns in shipped code. A parameter puts them
nowhere.

**Correction, 2026-09-04.** The original decision recorded a second rationale:
that passing only read helpers made a reader "structurally incapable of
writing". That claim was false. A reader is ordinary ucode loaded with
`loadfile()` inside rpcd and can import modules itself; this was verified by a
test reader importing `writefile` from `fs` and successfully writing a file.
The supplied `nl` handle and generic `ubus.call()` are not capability-limited
security wrappers either.

Readers are therefore **trusted package code**. `read(ctx)` is a conformance
contract and dependency-injection seam, not a sandbox or privilege boundary.
The absence of an exec helper still means a *conforming* reader cannot add an
exec-based source without a decision record and api change, which is the
architectural gate D3 wants; it does not prevent arbitrary installed code from
ignoring the contract. If untrusted readers ever become a requirement, that
needs process/privilege isolation and a new threat-model decision rather than a
stronger `ctx` abstraction.

No api bump: the call shape and reader contract for conforming code are
unchanged; the correction removes an invalid security property rather than
changing the interface.

## D35 — Port and bridge facts are reported, not derived — settled

`docs/snapshot-format.md` originally placed a port's bridge, carrier and
address in `derived`, described as joins from the link dump. They are not
joins: the link dump *reports* them about the port. Corrected to `attrs`,
with three attributes registered: `topo.bridge`, `topo.carrier`,
`topo.address`.

The distinction matters because `derived.bridge` on an **FDB** row genuinely
is a join when that row does not itself report a bridge — and if reported and
joined values sit in the same place, the one honest inference in the format
loses the company of the rule that isolates it.

Registered at the same time, for the two collections that had no vocabulary:
`br.name`, `br.vlan_filtering`, `neigh.ips`, `name.hostname`.

## D36 — Bridges are rows, not a plain array — settled

`docs/snapshot-format.md` described `bridges` as an array of objects while
ports and FDB entries were rows with subjects. Under the reader model that
inconsistency is untenable: two readers reporting bridge facts would need a
merge rule that ports and addresses do not use. Bridges are now
`subject: {bridge}` rows with `br.*` attributes and a derived `port_count`,
so one merge rule covers every collection (the same reasoning as D30).

## D37 — A disputed value is withdrawn, not arbitrated — settled

D27 settled that conflicts are declared rather than resolved but did not say
what `attrs` holds for a disputed attribute. Keeping one value would be
precedence by another name — whichever reader was read first silently wins.

So on first disagreement the attribute is **removed** from `attrs` and every
claim is recorded on the entity's `disputed` map, alongside the `conflicts`
entry in scope. A consumer cannot read a winner because there is no value
there to read.

This propagates correctly without further code: in the conflict fixture two
readers disagree about a port's native VLAN, so no PVID is available, so an
untagged address on that port resolves to `vlan: null` with a null source
rather than to whichever value won. A conflict becomes absence, not a guess.

## D38 — Collection status rolls up to the most conclusive honest answer — settled

Where several readers claim one collection, the collection's status is `ok` if
any reader returned `ok`; otherwise `indeterminate` if any did; otherwise
`unavailable` if any did; otherwise `not_applicable`. Reasons from every
reader are concatenated and attributed by reader id, and are carried as `note`
rather than `reason` when the rollup is `ok`, so a partial failure alongside a
success is still visible.

`ok` wins because it means data was actually obtained; a reader that failed
alongside one that succeeded is a reader problem, reported per reader, not a
reason to call the collection unreadable.

## D39 — Hints have a kind; the two-cause rule binds only causal ones — settled

Amends H3. A hint of kind `likely` asserts a probable cause and must name at
least two. A hint of kind `note` explains what is on the screen — why a column
is blank, that a VLAN was inferred, that readers disagreed — and asserts
nothing about the world, so the two-cause rule does not apply and would
produce nonsense if forced.

Without the distinction, either the useful explanatory notes acquire invented
second causes, or H3 gets quietly ignored. The test enforces the rule against
`likely` hints only, and the kind is visible in the rendering.

## D40 — A subject is not always one observation — settled

FDB entities are keyed on the subject **plus** the attributes that distinguish
one observation of it from another: `fdb.port` and `fdb.vlan`. Set-valued
attributes (`fdb.flags`, `neigh.ips`) accumulate across rows instead of
conflicting.

Found by the first live snapshot, on a GS1920-24 v1. The device reported
`33:33:00:00:00:01` on `eth0`, `switch` and `switch.20` simultaneously — which
is simply what a multicast group address looks like, present on every port. The
merge keyed FDB entities on the MAC alone, so three observations collapsed into
one entity and their differing ports were reported as *a conflict between
`rtnl` and `rtnl`*. A single reader cannot disagree with itself, so the
conflict machinery was being handed something D27 was never about.

Two things should have caught this earlier and did not:

- the diff already used `(mac, port, vlan)` as row identity, so the code
  contained both the right answer and the wrong one
- the `mac_on_several_ports` hint could never fire, because the merge destroyed
  exactly the evidence it looks for. A rule that cannot fire is a defect
  indicator; nothing was checking for one

No fixture had one MAC on two different *ports* — the duplicate case that was
covered was one MAC twice on the *same* port — which is the coverage gap
`fixtures/devices/mac-on-many-ports` closes. That fixture is verified to fail
against the old merge key.

The set-valued rule is the other half. The same forwarding observation can be
reported more than once with complementary flags or bridge metadata. Those are
not two sources disagreeing about a set-valued fact, and the honest value is
the union. D47 explicitly prevents the merge machinery from assigning
hardware/software provenance to those row shapes.

Conflicts now mean what D27 says they mean: two *different* readers disagreeing
about one observation.

## D41 — Three corrections from the first live snapshot — settled

All three found on a GS1920-24 v1 (rtl839x, kernel 6.18.44) and pinned by
`fixtures/sources/rtnl/self-mastered-bridge`, verified to fail against the
pre-fix reader.

**A bridge names itself as its own master.** In this device's AF_BRIDGE link
dump the bridge — called `switch`, not `br-something` — appears with
`master: "switch"`. Bridge detection excluded a bridge from the ports
collection only when it had *no* master, so the bridge was emitted as a port of
itself and counted in its own `port_count`: 29 ports on a 28-port switch. A
bridge is now excluded from `ports` whichever way the kernel names it, and
self-mastered entries do not count toward `port_count`.

Every synthetic fixture had given the bridge no master at all, because that is
what a `br-lan` looks like in the dumps I modelled from. The naming was the
clue that this device's bridge is not a conventional one.

**An unresolved neighbour is not an address mapping.** The kernel reported
`0.0.0.0` with an all-zero hardware address, and the reader turned it into a
mapping — inventing a host that does not exist, which is the one thing a tool
built on P2 must not do. Entries whose state is `NUD_INCOMPLETE` or
`NUD_FAILED` are now skipped, with an explicit all-zero address guard as well.

**`ok` with no rows needs to say what it read.** The device has an empty
`/etc/ethers`, so the names collection was correctly `ok` with zero rows: the
files exist and map nothing. Correct, but illegible — indistinguishable at a
glance from having looked nowhere. The reader now attaches a note listing the
files it read. This is the boundary case of P1's "zero rows means zero rows":
the status was right, and it still needed evidence attached.

## D42 — GS1920 FDB cross-check — settled; provenance inference superseded by D47

A cross-check on the live GS1920-24 v1, which happens to have `ip-bridge` and
`lldpd` installed, against `bridge fdb show` and `bridge -j vlan show` on the
same device at the same time. Three useful observations remain.

**D19 is largely verified rather than inferred.** The flag vocabulary
synthesised from `bridge/fdb.c` matches what iproute2 prints for every token
the kernel actually emits on a dump: `self permanent`, `permanent`, `self`, and
the empty set.

One correction to an over-claim made when first reading that output: the
`master switch` in a `bridge fdb show` line is iproute2 printing `NDA_MASTER`
(the bridge's name), **not** a `master` flag. `NTF_MASTER` is a request flag
used when adding an entry, and does not come back on a dump — so the `master`
branch in `fdb_flags()` is correct against `fdb.c` line 115 and is effectively
unreachable on a read path. It stays for completeness and is marked untested.
So does `topo.vlan_flags`: iproute2's JSON gives `["PVID","Egress Untagged"]`
and the space-joined text form is exactly what this format registers. Both were
previously arguments from source reading.

**The total scope count is useful; the old provenance split was not.** The
format had documented `count`, `entries_switch_reported` and
`entries_bridge_reported`; implementation then counted them over raw rows before
merging. The GS1920 evidence motivated that split, but x86 software-only bridge
validation later proved that `self` plus no master is not a portable hardware
origin marker. D47 therefore removes the two split fields and retains only the
raw pre-merge `count`.

**The two row forms on this GS1920 differ in VLAN reporting.** An access-port
address appeared as:

```
<mac> dev lan2 vlan 5 master switch
<mac> dev lan2 self
```

The first row carries a VLAN id and master; the second does not. The device and
driver context made distinct reporting paths worth investigating, but the row
shape alone is no longer labelled hardware versus software.

*Rejected: merging them on the resolved VLAN.* It is technically easy — resolve
the PVID before merging rather than after — and it would collapse the pair into
one entity with the flags unioned, which looks tidier. It is refused because it
would make an **inference load-bearing for identity**: the two rows would be
declared the same forwarding entry on the strength of a PVID guess. The reason
one row lacks a VLAN is genuinely unknown; merging would bake a guess about a
driver into the data model.

So the duplication stays visible. On a trunk port with no PVID the row lacking
a VLAN resolves to `null` and correctly stays there, which is the same behaviour
with nothing to guess from.

This remains a question worth asking upstream of the realtek driver, which is a
better outcome than a tidier table.

## D43 — Reader notes reach the snapshot — settled

D41 had the reader attach a note to a successfully-read collection with no
rows, so that `names: ok, count: 0` would say *which files it read and found
empty*. The assembler collected only `reason` from a collection status and
silently discarded `note`, so the note never appeared. Confirmed on the live
device: `{"status": "ok", "count": 0}` and nothing else.

Notes are now carried through attributed by reader id, alongside the case that
already used the field — one reader failing beside another that succeeded,
where the collection is `ok` and the failure is still worth seeing.

Worth recording how this got through: the fixture for this case **already
carried the note in its input** and never asserted it in its expectation. A
fixture that supplies a value without checking it looks like coverage and is
not. The general lesson is narrower than "assert more": an expectation should
assert every field the fixture's input deliberately sets, because a field only
gets into a fixture input on purpose.

## D44 — The device's own address is a reported join, not a mystery host — settled; extended by D47

`derived.local` is true when an address equals a reported link address belonging
to this device. It was first implemented against `topo.address` on port rows;
D47 extends the same join to `br.address` on bridge rows. The fan-out hints skip
local addresses, and the view labels them "this device".

Found in the first live render of the page. The switch installs its own address
as a permanent entry on several ports and on every VLAN, so
`mac_on_several_ports` fired on it and offered three explanations — a client
that just moved, a link aggregation, a bridging loop — **none of which applies
to the switch itself**. A `likely` hint naming two or more causes still fails
H3's purpose if every named cause is wrong; the rule stops a hint being a
verdict, and does not stop it being irrelevant.

The fix remains a join, not a filter or a heuristic: the device's own addresses
are reported facts and matching FDB observations are joined to them. D47 found
the missing bridge half on an empty software bridge; it does not declare every
FDB row on a bridge device local.

`duplicate_reports` has the same local-address exclusion so a device's own
per-VLAN observations do not look like a remote address duplicated behind a
port.

Recorded as a lesson about hint review: a `likely` hint needs its causes
checked against the rows it will actually fire on, not only against the rows it
was written for.

## D45 — The export is built from an allowlist — settled

`exportable()` constructs the file from a declared list of registered keys.
The first version copied the snapshot and deleted `derived`.

Found in the first exported file from the live switch, which contained `_t` —
the view's own receive timestamp, attached to its copy of the snapshot so the
age display could tick. Harmless in itself, and exactly the wrong shape of
mistake: a denylist removes only what it already knows about, which is the
lesson D15 records about redaction and which had not been applied to the one
artefact a user keeps and another tool ingests.

Two changes. The view no longer mutates the snapshot at all — the receive time
lives beside it — so there is nothing extra to leak. And the export is a
positive construction, so any future field has to be added to `EXPORT_KEYS`
deliberately rather than arriving by default.

`tests/export.test.js` asserts the shape against every device fixture, and
attaches junk to the snapshot first to prove the allowlist is doing the work
rather than the absence of junk.

*Verified in the field at the same time:* the exported snapshot showed
`conflicts: 0` (D40), `ports: 28` on a 28-port switch (D41), and
`fdb.count: 83` raw observations merging to 55 FDB observations. The temporary
hardware/bridge split displayed in that development build is superseded by D47.

## D46 — Bridge identity comes from the generic link kind — settled; x86 verified

The `rtnl` reader uses **two RTM_GETLINK views for two different facts**:

1. a generic RTM_GETLINK dump identifies bridge devices from their own
   `linkinfo.type == "bridge"` (`IFLA_INFO_KIND`) and reports their link
   address;
2. an `AF_BRIDGE` RTM_GETLINK dump with the bridge-VLAN ext-mask supplies
   bridge-port membership and live VLAN membership.

The old implementation inferred bridge identity from AF_BRIDGE `master`
references. That worked on populated bridges and was patched in D41 for the
self-mastered form seen on the GS1920, but it still made bridge existence depend
on membership. An empty bridge could therefore disappear entirely.

An **x86/64 OpenWrt 25.12.5** device (kernel 6.12.94) settled the source shape.
Software bridges in the generic dump exposed `linkinfo.type: "bridge"`; the
same bridge devices in the AF_BRIDGE view exposed `linkinfo: null` and could
appear self-mastered. `/sys/class/net/*/bridge` agreed with the generic
link-kind set.

The production backend was then installed on that system and exercised with a
deliberately empty `l2probe0` bridge. It reported one bridge, zero ports and
`derived.port_count: 0`. The same bridge populated with `eth0`, with VLAN
filtering enabled, and with VLAN 10 added continued to report one bridge/one
port with the expected VLAN membership. R4 is therefore live-verified on x86,
not merely structurally represented in a fixture.

The reader no longer promotes an AF_BRIDGE master reference into bridge
identity. If AF_BRIDGE names a master which the generic dump did not identify
as a bridge, the link read is declared inconsistent/unavailable rather than
guessed through. A bridge identified generically remains a bridge even if it
has zero members or is omitted by the AF_BRIDGE view.

*Cost:* one extra generic link dump per user-triggered snapshot. It is
software-only and negligible beside the FDB hardware walk.

## D47 — FDB row shape is not provenance; bridge addresses complete the local join — settled

The x86 validation that closed D46 disproved two plausible-looking assumptions
at once.

**First: `self` plus no master is not hardware provenance.** A pure software
Linux bridge with no switch ASIC produced many FDB rows carrying `self` and no
`fdb.bridge`. With one virtio member the development snapshot reported a 9/2
`entries_switch_reported` / `entries_bridge_reported` split; with VLAN filtering
and VLAN 10 it reported 13/5. Those numbers could not possibly mean hardware
versus software origin on that system.

Therefore `entries_switch_reported` and `entries_bridge_reported` are removed.
`scope.fdb.count` remains and counts raw FDB observations before merging. The
reader continues to report `fdb.flags` and `fdb.bridge` exactly as observed,
but neither the core nor the view assigns hardware/software provenance from
that shape. `fixtures/devices/dual-reported-entries` negatively asserts the old
scope fields stay absent.

**Second: bridge devices have their own reported addresses.** An empty
`l2probe0` exposed its own unicast FDB observation, but D44 initially marked it
non-local because the snapshot only collected `topo.address` from port rows and
an empty bridge has no member row. After `eth0` was enslaved,
`/sys/class/net/l2probe0/address` and `/sys/class/net/eth0/address` both reported
`52:54:00:12:34:56`, and the existing port-address join then correctly marked
the matching FDB rows local.

The generic RTM_GETLINK dump already used by D46 reports the bridge link
address. It is now registered as `br.address`, and `derived.local` joins against
both `topo.address` and `br.address`. This adds no read and no heuristic: locality
still requires a matching address reported about this device. An FDB row is not
local merely because `fdb.port` names a bridge or because it carries `self`.
`fixtures/sources/rtnl/empty-bridge-generic` pins the source fact and
`fixtures/devices/empty-bridge-local` pins the derived join.

**Format version remains 1 because this contract has not shipped.** Development
drafts of v1 contained the now-disproved split fields, but there is no released
or upstream v1 consumer to preserve. Correcting the pre-release contract before
it ships is preferable to publishing a knowingly false v1 and immediately
creating v2. Once v1 is released or treated as a stable external interface,
removing/renaming fields or changing their meaning requires a format bump under
`docs/snapshot-format.md`; this pre-release correction is not precedent for
changing a released version in place.

## D48 — `ucode-mod-rtnl` null plus no error is a successful empty dump — settled

Live x86 testing found the neighbours collection occasionally reported
`unavailable` with "netlink dump returned no result and no error". Inspection
of `ucode-mod-rtnl` showed why: for a multipart request the result array is
allocated only when a valid reply row arrives. A successful zero-row dump can
therefore return `null` while `nl.error()` remains clear.

D18's seam now interprets that pair correctly: error present means failure;
`null` with no error normalises to an empty row array. Collection semantics then
decide what empty means. Neighbours can be `ok` with zero rows; FDB remains
`indeterminate` when one empty sample cannot distinguish true emptiness from an
observation gap (P4).

A `null-empty-dump` source fixture represents this source behaviour explicitly.
The production change also passed the older 28-group OpenWrt fixture/mechanical
suite on x86; the new fixture still needs to be run from a current branch
checkout rather than the older offline ZIP used for that regression check.

---

## Superseded

| Decision | Superseded by | Note |
|---|---|---|
| Per-query reads with `port`/`vlan`/`mac` arguments | D2 | Prototype in tree still reflects this |
| Port the wired role vocabulary | D7 | Replaced by counts plus D8 hints |
| Export as C2 | D9 | Borrows the vocabulary, not the identity |
| `luci.bearings` ubus object | D4, D5 | Namespace and name both wrong |
| D3's blanket ban on device-specific read paths | D3 amendment, D24 | Narrowed to undeclared, unconditional, core dependence |
| Port rows as `subject: {self}` | D30 | Merge key must be an identity, not an attribute value |
| `read()` with no arguments | D34 | Primitives are passed in, so stubbing needs no test hook |
| Port bridge/carrier/address as derived | D35 | They are reported by the link dump, not joined |
| `bridges` as a plain array | D36 | One merge rule for every collection |
| H3 binding every hint | D39 | Only causal hints can name two causes |
| FDB entities keyed on the MAC alone | D40 | One MAC on several ports is several observations |
| Bridges detected as masterless devices | D41 | A bridge can be its own master |
| Bridge identity inferred from AF_BRIDGE master references | D46 | Generic link kind identifies the bridge; AF_BRIDGE reports membership |
| Scope counts as documentation only | D42 | Raw collection counts were implemented; D47 later removes the invalid provenance split |
| Hardware/software provenance inferred from `self`/master row shape | D47 | Row shape remains reported evidence only |
| `derived.local` joined only to port `topo.address` | D47 | Bridge `br.address` participates in the same reported-value join |
