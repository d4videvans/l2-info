# Decisions

**Document class:** current decision register. This file records the decisions
that are in force now, including open/deferred items. The detailed development
history and original long-form rationale through D49 is preserved in
[`decisions-history.md`](decisions-history.md).

Statuses used here:

- **settled** — current rule;
- **deferred** — deliberately not implemented until named evidence appears;
- **open** — design work still required before implementation;
- **superseded** — retained only as history.

When source comments refer to `Dxx`, this is the current index to consult.

## D1 — Standalone repository — settled

`l2-info` is its own project rather than a subdirectory of the related fleet
project. They share some vocabulary/lessons, not lifecycle, scope or package
machinery.

## D2 — Snapshot-and-query — settled

One explicit `snapshot()` acquisition serves subsequent filtering/search/diff in
the browser. The device is not re-read per query and nothing polls.

## D3 — Rtnetlink is the bundled kernel L2 source — settled; amended by D24

The bundled core reader uses `ucode-mod-rtnl`, not an unconditional shell
`bridge` dependency or vendor debugfs path. A separately packaged reader may add
another local source if it follows the reader contract; the core must not branch
on device id to choose a hidden alternate source.

This is a source-path decision, not a claim that `rtnl` is the backend's only
runtime package dependency. The current backend also legitimately requires
rpcd-ucode plus the ucode `fs` and `ubus` modules.

## D4 — Two packages — settled

- `l2-info`: backend, independently usable over ubus, no LuCI dependency;
- `luci-app-l2-info`: LuCI view/menu/read-only ACL, depends on backend.

The development monorepo contains both; upstream submission splits them.

## D5 — Name `l2-info`; human menu title `MAC & VLAN Lookup` — settled

The ubus object/package use `l2-info`. LuCI places the descriptive title under
**Status** rather than exposing implementation jargon as the primary UI label.

## D6 — Derivation in backend; filtering in view — settled

Joins/counts/address classification and the single permitted PVID inference are
computed once in the assembler. Port/VLAN/MAC filters and presentation hints
remain view policy. `snapshot()` therefore takes no query arguments.

## D7 — Report, don't classify — settled

Do not invent port/network roles from observed counts/topology. Report the
evidence; optional human interpretation belongs in D8/P5 hints.

## D8 — Interpretation allowed only as constrained UI hints — settled

Hints are presentation-only, use displayed evidence, are pure/testable, and a
causal `likely` hint names more than one plausible cause. Non-causal explanatory
text uses `note` semantics.

## D9 — Own `l2-info.snapshot` format; vocabulary borrowing only — settled

The format is not another project's capture/session format. It owns its own
envelope/version while retaining compatible `subject`/`attrs` vocabulary where
useful.

## D10 — Current and previous snapshots only — settled

LuCI keeps at most two snapshots in memory for comparison. No history store.

## D11 — No browser persistence — settled

No local/session storage for snapshots. Download is the explicit keep-it path.

## D12 — FDB diff identity and scope compatibility — settled; refined by R2/R3

Raw comparison identity is MAC + port + VLAN observation identity. Before a
strong diff, `bridges`, `ports` and `fdb` status/reader coverage must be
compatible. `moved` is emitted only for the unambiguous qualifying 1->1 case;
otherwise primitive appeared/vanished evidence remains.

## D13 — One permitted inference: PVID fallback — settled

If an FDB observation does not report a VLAN and its port reports a PVID,
`derived.vlan` may use that PVID with `vlan_source: "pvid"`. A reported FDB VLAN
uses `vlan_source: "fdb"`. Inferred VLAN is not used to merge raw observations.

## D14 — Fixtures are discovered data, not hard-coded cases — settled

Adding a fixture directory makes it part of the runner without editing a
per-device test list.

## D15 — Committed fixture redaction is positive rewrite — settled

Public fixtures use synthetic MACs and remove/sanitise site-specific annotation
rather than relying on a deny-list of secrets. Current live-validation bundles
are raw and require review/redaction before public sharing.

## D16 — Apache-2.0 — settled

Project/package code uses Apache-2.0, matching LuCI and the chosen upstream
shape.

## D17 — Upstream target is two OpenWrt trees — settled; submission pending

Intended targets:

- backend -> `openwrt/packages`;
- LuCI app -> `openwrt/luci/applications`.

Current pre-submission hygiene is complete: package names/layout/dependencies,
maintainer metadata, Apache metadata, backend URL/category, LuCI POT/current
lint/i18n, read-only ACL/menu paths, and official SDK builds are all covered by
CI.

Backend runtime dependencies are currently:
`rpcd-mod-ucode`, `ucode-mod-fs`, `ucode-mod-rtnl`, `ucode-mod-ubus`.
LuCI depends on `luci-base` and `l2-info`.

The backend sits directly in OpenWrt **Network** rather than the unrelated
`Routing and Redirection` submenu.

Actual upstream PRs are intentionally postponed until the external tester/forum
phase in D50.

## D18 — Every source read has a failure/empty seam — settled

Rtnetlink reads distinguish error from successful empty output; fixture replay
uses the same seam so tests cannot accidentally reach the live kernel.

## D19 — `fdb.flags` follows iproute2 text vocabulary — settled

Flag/state tokens are represented together in the order/vocabulary familiar
from `bridge fdb show`, preserving state rather than dropping it.

## D20 — Whole-device snapshot cost accepted — settled

The consistent whole-device snapshot is preferred over per-port query reads.
Cost is measured/displayed and never polled. Reopen only if real hardware makes
an explicit user-triggered snapshot unacceptably slow.

## D21 — Contributor-oriented redacted capture facility — open

A future helper/method may turn live evidence into fixture-ready source and
normalised data with D15 redaction before public sharing.

It **does not exist today**. The current supported evidence collector is
`tools/collect-validation.sh`, whose output is intentionally raw/private until
reviewed.

Still to settle before implementing D21:

- backend ubus method versus separate contributor tool;
- redaction mapping lifetime/reproducibility;
- exact output packaging while preserving D26's two data seams.

## D22 — One LuCI status page and implemented section order — settled

The implemented UI is one page at **Status -> MAC & VLAN Lookup**. It contains:

1. Snapshot actions/age/summary;
2. Find addresses;
3. Matching addresses/hints;
4. Changes since previous snapshot;
5. Ports and VLANs;
6. collapsible Device and data-source details.

The details panel automatically opens when collection coverage needs attention
or conflicts exist. This replaces the earlier open question about a separate
facts page/panel ordering.

## D23 — Not a channel inside the fleet agent — settled

This is a standalone one-device, request-driven diagnostic. A fleet collector
may consume its backend later without changing this project's lifecycle.

## D24 — Reader architecture: source-extensible, vocabulary-closed — settled

Readers may add local observation sources. They may not add arbitrary snapshot
fields/collections. Vocabulary changes are format/design decisions first.

## D25 — Reader discovery is filesystem state — settled

Scan `/usr/share/l2-info/readers/*.uc`; no UCI registry, enable list or reader
priority. Installing/removing a reader package adds/removes source capability.

## D26 — Source and device fixture seams are separate — settled

Source fixtures preserve source-shape parsing evidence; device fixtures start
from normalised reader results and test assembler/presentation interactions.
Discovery is a third seam for manifest/API loading.

If D21 is implemented in future, its output must support both source-shape and
normalised evidence. Earlier wording saying "capture emits both" described the
intended contract, not shipped functionality.

## D27 — Conflicts are declared, not resolved — settled

No reader has precedence. Unequal ordinary claims withdraw the disputed value
and preserve each claim plus a scope conflict.

## D28 — Reader seam is real although one reader ships — settled

`rtnl` uses the same discovery/validation path as any future reader. A core
reader-id special case would invalidate the abstraction and is mechanically
checked against.

## D29 — Reader API versioned independently — settled

Current reader API is integer version 1. Unsupported readers are skipped with a
declared reason.

## D30 — Port rows use `{port}` subject identity — settled

Port identity is a subject key, not an attribute hidden under `{self}`. This
keeps one merge rule across row types.

## D31 — Readers do not read other devices — settled

No SNMP/SSH/controller/remote-host source belongs in a single-device reader.
Cross-device inference is outside scope.

## D32 — Readers report; assembler derives/stamps source — settled

Reader rows contain `subject`/`attrs`; assembler owns `derived` and `source`.

## D33 — Ordinary presentation is plain; provenance surfaces when useful — settled

Normal tables do not cover every cell in source badges. Reader details,
conflicts/disputed claims and JSON source fields preserve provenance where it is
material.

## D34 — `read(ctx)` dependency injection is not a security boundary — settled, corrected

Readers receive `api`, rtnetlink, filesystem and ubus primitives for conformance
and total fixture replay. They remain trusted package code running in rpcd.

## D35 — Port/bridge facts reported by link dump stay in `attrs` — settled

Port bridge/carrier/address are source facts (`topo.*`), not derived joins.

## D36 — Bridges are subject-keyed rows — settled

Bridge facts use `{bridge}` subject plus `br.*` attributes so normal merge rules
apply.

## D37 — Disputed value is withdrawn — settled

On disagreement, no arbitrary first value remains in `attrs`; claims live in
`disputed`/`scope.conflicts`.

## D38 — Collection status rollup chooses most conclusive honest evidence — settled

`ok` wins when any reader actually succeeded; otherwise indeterminate,
unavailable, then not-applicable. A failed reader alongside success remains
visible as attributed note/reader status.

## D39 — Hint kind distinguishes causal `likely` from explanatory `note` — settled

The two-cause requirement binds causal hints; it does not force invented causes
into explanatory notes.

## D40 — One subject may have several observations — settled

FDB observation identity includes reported port/VLAN discriminators. Set-valued
facts such as flags/IPs union across duplicate observations.

## D41 — First live-switch source corrections — settled; some mechanics superseded by D46

Live rtl839x validation exposed self-mastered bridge representation, unresolved
all-zero neighbour mappings and the need for evidence notes on successful empty
naming reads. Current bridge identity is now governed by D46.

## D42 — GS1920 FDB cross-check — settled; provenance inference superseded by D47

The cross-check validated much of the flag/VLAN vocabulary and raw count
behaviour. Its temporary hardware/software row-shape interpretation is no
longer valid.

## D43 — Reader notes reach collection scope — settled

A successful source can attach evidence explaining an `ok` zero-row result;
assembler preserves it. Fixtures must assert deliberately supplied fields.

## D44 — Device-own MAC is an exact reported-address join — settled; extended by D47

`derived.local` prevents the device's own addresses being presented as remote
hosts/fan-out. D47 adds bridge link addresses to the same exact join.

## D45 — JSON export is positive allowlist — settled

Export constructs the retained envelope/scope/reported row fields explicitly,
omitting `derived`, hints and arbitrary view state.

## D46 — Generic link kind defines bridge identity — settled; multi-platform verified

Generic RTM_GETLINK identifies bridges/bridge address; AF_BRIDGE supplies
membership/VLANs. Empty/self-mastered/mixed DSA/Wi-Fi cases all use the same
rule.

## D47 — FDB row shape is not provenance; bridge addresses complete locality — settled

Remove the invalid development hardware/software scope split. Preserve raw
flags/master/bridge facts. Join `derived.local` against both port and bridge
reported link addresses. This was a pre-release v1 correction.

## D48 — rtnl null plus no error means successful empty dump — settled

Normalise that source representation to an empty row set and let collection
semantics decide whether empty is `ok` or `indeterminate`. The regression is in
fixtures and mandatory CI.

## D49 — All-zero lladdr is not a valid FDB subject — settled

Drop only `00:00:00:00:00:00` FDB identities at the source boundary. Live
qualcommax validation showed these were unstable placeholders; non-zero
identities on the same ports/VLANs remain reportable.

## D50 — External tester/forum phase before upstream PRs — settled workflow

Before submitting the two package PRs:

1. make the repository front door/install/uninstall path easy and reversible;
2. tag a known pre-release revision;
3. introduce it on the OpenWrt Forum (Community Builds, Projects & Packages);
4. invite testing on hardware outside the existing validation matrix;
5. collect usability/portability/snapshot-cost evidence;
6. fix concrete defects without expanding the schema speculatively;
7. then prepare the separate upstream PRs.

Forum interest is itself evidence. The goal is not to accumulate features before
submission; it is to expose assumptions to real users/hardware and make the
upstream review better informed.

## Superseded/changed decisions at a glance

| Earlier position | Current decision |
|---|---|
| query-per-read | D2 snapshot-and-query |
| role/classification vocabulary | D7 reported counts + D8 hints |
| export another project's capture format | D9 own snapshot format |
| port subject `{self}` | D30 `{port}` |
| reader `read()` with no context | D34 `read(ctx)` |
| port link facts in derived | D35 reported `attrs` |
| bridge as plain object array | D36 subject-keyed rows |
| hint two-cause rule applied to all hints | D39 causal `likely` only |
| FDB keyed on MAC alone | D40 observation discriminators |
| bridge identity from AF_BRIDGE master shape | D46 generic link kind |
| hardware/software provenance from FDB row shape | D47 no provenance classification |
| locality joined only to port addresses | D47 bridge address included |
| D22 panel/layout undecided | D22 current one-page Status layout settled |

For the original evidence trail and detailed costs/consequences behind these
entries, see `docs/decisions-history.md` and `docs/remediation.md`.
