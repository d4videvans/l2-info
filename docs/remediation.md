# Upstream remediation and readiness status

**Status:** the correctness/portability remediation, planned hardware sweep,
package hygiene and reproducible CI work are complete for the current design.
The existing R5 partial-read case is implemented; broader machine-readable
per-attribute failure vocabulary remains deliberately deferred because the
hardware sweep did not produce evidence that would justify expanding the schema.

The project is now in a **pre-upstream external testing phase**: make it easy to
install/remove, invite OpenWrt community testing on hardware we do not own,
collect usability/portability feedback, then prepare the two upstream
submissions.

The purpose of this work has remained narrow: make `l2-info` truthful, portable
and reviewable without expanding it into a topology/fleet-management product.
The governing principles remain observation over classification, explicit
uncertainty, one user-triggered snapshot, read-only/stateless behaviour and a
small ubus surface.

## Priority classes

- **P0 — correctness / trust model:** required before wider testing.
- **P1 — portability / data-contract hardening:** required before wider testing.
- **P2 — integration / UI / packaging:** required before upstream submission.
- **P3 — polish/workflow:** useful, not a reason to invent product scope.

## Phase 1 — correctness and trust model

### R1 — Readers are trusted package code (P0) — done

The reader context is dependency injection and a fixture seam, not a sandbox.
Installed reader ucode runs inside rpcd and can import modules itself. D34,
`docs/readers.md`, `CONVENTIONS.md` and source comments were corrected to remove
the former over-claim while preserving the conforming-reader contract.

### R2 — Unambiguous movement inference (P0) — done

A MAC may legitimately have several simultaneous FDB observations. `moved` is
therefore inferred only when the complete qualifying remote-unicast
port-presence set changes from exactly one port to exactly one different port.
Raw dual reports on the same port do not affect that decision. Ambiguous
1->N/N->1/N->N port-presence cases remain primitive appeared/vanished evidence.
VLAN-only changes on one port are not port moves and remain visible as primitive
evidence.

The comparison logic is pure/tested outside the browser.

### R2a — Non-rendering view logic under tests (P0/P1) — done

Hint, export, query/filter, diff and scope-compatibility logic has direct Node
tests. A target device without Node may skip them in `sh tests/run.sh`, but CI
always supplies Node, so they are mandatory in repository validation.

### R3 — Compare acquisition scope before diffing (P1) — done

Strong FDB comparisons require compatible `bridges`, `ports` and `fdb`
collection status/reader coverage. These are load-bearing because FDB is the
observed change set, port PVID can change resolved VLAN identity, and both port
and bridge addresses affect `derived.local`. Names/neighbours are annotation.

## Phase 2 — source and data-contract portability

### R4 — Bridge identity independent of membership (P1) — done; hardware verified

Bridge identity comes from generic RTM_GETLINK `linkinfo.type == "bridge"`;
AF_BRIDGE RTM_GETLINK supplies membership/VLAN facts. An AF_BRIDGE master absent
from the generic bridge set is an inconsistency, not permission to infer a
bridge.

This handles empty bridges and the different live DSA/router link shapes seen
across x86, Realtek, Mediatek and Qualcomm targets.

### R5 — Preserve valid partial observations (P1) — implemented for existing multi-source partial shape

The bundled rtnl reader already has a partial-observation case: generic RTM_GETLINK can successfully establish bridge identity/address while the separate sysfs `vlan_filtering` read fails. Valid identity is now retained as an `ok` bridge row with the unavailable optional attribute omitted and an attributed collection note. This does not claim that hardware/driver-level sparse fields have been observed; it reconciles the existing multi-source reader shape. Version 1 still has no machine-readable per-attribute failure vocabulary.

### R6 — No special no-bridge FDB rule (P1) — rejected by evidence

Live x86 testing showed AF_BRIDGE FDB can still return protocol/self entries
when no Linux bridge exists. Bridge existence is therefore not the applicability
boundary for the FDB read. Successful zero-row FDB remains `indeterminate` when
one sample cannot distinguish true emptiness from an observation gap.

### R6a — FDB row shape is not hardware/software provenance (P0/P1) — done

Pure software bridges produced the same `self`/no-master shapes that initially
looked hardware-specific on a Realtek switch. The invalid development counters
`entries_switch_reported`/`entries_bridge_reported` were removed. Raw flags and
bridge/master facts remain; `scope.fdb.count` is neutral pre-merge observation
count.

### R6b — Bridge/device own MAC participates in locality (P1) — done; hardware verified

Generic RTM_GETLINK supplies `br.address`; `derived.local` joins FDB MACs against
both reported port and bridge addresses. No locality is inferred merely from
`self` or from the FDB row's interface being a bridge.

### R6c — Successful zero-row rtnetlink dumps (P0/P1) — done

Current `ucode-mod-rtnl` may return null plus no error for a successful empty
multipart dump. The wrapper normalises that exact pair to an empty row set; a
real rtnl error remains unavailable. The `null-empty-dump` fixture and current
mandatory CI close the regression gap.

### R6d — Reject all-zero FDB placeholder identities (P0/P1) — done; hardware verified

A Linksys SPNMX56 produced large unstable runs of
`00:00:00:00:00:00` FDB placeholders with unrelated-looking VIDs. The reader
drops only the unusable all-zero address identity. In the post-fix validation,
121 non-zero `(MAC, port, VLAN)` identities matched `bridge -j fdb show`
one-for-one while 1,301 all-zero placeholders were excluded.

## Phase 3 — LuCI/API integration

### R7 — Age timer lifecycle (P2) — done

The view keeps one age-update chain, stops naturally after navigation and never
polls data. Only the displayed age changes until the user presses Update again.

### R8 — Stable labels/i18n (P2) — done

User-facing stable labels are translated, reader collection notes are displayed,
and the LuCI POT is generated/current. CI runs current LuCI's i18n scanner and
fails if the committed template drifts.

Reason-code machinery remains intentionally deferred; reader/source reasons are
currently free text evidence, not a stable public enum.

### R9 — Strict query validation (P2) — done

VLAN input is whole-string/range validated (1–4094); MAC search validation is
explicit and visible. Query/filter policy has direct Node tests.

## Phase 4 — upstream packaging and CI

### R10 — Two independently clean feed packages (P2) — done for current pre-submission tree

Backend (`openwrt/packages` target):

- real maintainer metadata set;
- Apache-2.0 metadata consistent with the project licence;
- no invalid `PKG_LICENSE_FILES` reference;
- package placed directly under **Network**, not `Routing and Redirection`;
- project URL set;
- current runtime dependencies declared:
  `rpcd-mod-ucode`, `ucode-mod-fs`, `ucode-mod-rtnl`, `ucode-mod-ubus`;
- architecture-independent payload (`PKGARCH:=all`);
- rpcd reload path live-verified and SDK-built.

LuCI (`openwrt/luci` target):

- maintainer metadata set;
- `luci-base + l2-info` dependency explicit;
- POT regenerated and drift-gated;
- current LuCI ESLint/i18n checks pass;
- menu location **Status -> MAC & VLAN Lookup** and the read-only ACL match
  current LuCI status-app patterns;
- official SDK build successfully produces the LuCI package with the backend.

The two directories remain in this monorepo for development/testing but are
shaped for separate upstream submissions.

### R11 — Reproducible CI/build checks (P2) — done

Repository CI now has three mandatory layers:

1. **unit/fixture/mechanical:** pinned host ucode, fixture JSON validation,
   source/discovery/device replay, mechanical checks and Node
   hint/export/query/diff tests;
2. **current LuCI integration:** current LuCI tree, ESLint and translation
   template drift check;
3. **official OpenWrt SDK package build:** both intended packages in
   `openwrt/sdk:x86_64-master` with the required base-feed source packages
   staged.

The SDK gate initially exposed a CI-environment defect rather than an l2-info
package defect: only `packages`/`luci` feeds had been populated, so LuCI's
`lucihttp` build failed on missing `lua.h`. A local official-SDK reproduction
showed the backend already built cleanly; selectively staging the relevant base
source packages made the LuCI build succeed too. CI was corrected without
weakening the build targets/gate.

Run `34026863495` at commit `a2f4ef2` completed all three jobs successfully,
including the official two-package SDK build. The subsequent metadata/category
state at commit `355f49e7` also completed the same three-job workflow green in
run `34027255403`. Later repository changes remain subject to the same workflow.

### R12 — Unambiguous local test invocation (P3) — done

Documentation consistently uses:

```sh
sh tests/run.sh
```

so archive/WinSCP workflows do not depend on preserved executable bits.

## Phase 5 — external tester release before upstream submission

### R13 — Make pre-upstream testing easy and reversible (P2/P3) — active

This phase was added after the internal remediation completed. The goals are:

- a concise, user-oriented README rather than a development diary;
- one practical installation/troubleshooting guide;
- `tools/install-test.sh` as the one-command copied-checkout installer;
- `tools/uninstall-test.sh` removing only project files and leaving shared
  dependencies alone;
- explicit privacy guidance around exported snapshots/validation bundles;
- documentation reconciled with the current v1 contract and current UI;
- a stable pre-release tag/revision for external testers;
- an OpenWrt Forum introduction in **Community Builds, Projects & Packages** to
  test usefulness and hardware portability before opening upstream PRs.

This is intentionally a test phase, not a new product-development phase. Forum
feedback should first answer: does the tool solve a useful problem, is the
installation/UI legible, which new hardware shapes appear, and is any snapshot
cost unacceptable?

## Hardware validation matrix

The planned diversity sweep is complete for the current portability questions.

| Device | State | Primary evidence |
|---|---|---|
| x86/64 OpenWrt 25.12.5 / 6.12.94 | complete for current software-bridge questions | no-bridge, empty/populated/VLAN-filtered bridge; exposed/corrected no-bridge, provenance and null-empty assumptions |
| Zyxel GS1920-24 v1 | rtl839x complete for current questions | generic bridge identity/address; 24-port model with four additional combo/SFP interfaces (28 DSA interfaces exposed); locality; roughly 1.2–1.3 s hardware walk |
| Zyxel GS1900-8HP B1 | rtl838x complete | one bridge/eight ports; distinct per-port addresses; nested DSA slave metadata; management VLAN child excluded; 141 raw FDB rows matched cross-check |
| Cudy WR3000P v1 | Filogic/router complete | one bridge/eight mixed wired/Wi-Fi ports; AF_BRIDGE membership where generic kind is absent; duplicate flag-only observations merged; ~233 ms |
| Linksys SPNMX56 | qualcommax/ipq50xx complete | one bridge/nine ports; all-zero qca8k FDB placeholders discovered/fixed; exact non-zero cross-check; ~915 ms |
| Linksys EA8300 | ipq40xx complete | one bridge/eleven mixed ports; VLAN children excluded; 175 raw observations -> 141 merged identities matching cross-check; ~396 ms |

The physical sweep did not produce an R5 partial-attribute case.

## Evidence to collect from new external targets

Start publicly with low-risk metadata and scope information:

- device model;
- OpenWrt version/target/kernel;
- exact test tag/revision;
- snapshot duration;
- collection/reader statuses and reasons;
- presentation screenshots where relevant.

`tools/collect-validation.sh` is available when deeper evidence is required, but
its output is raw and can contain MAC addresses, IP addresses and hostnames. It
must not be casually attached to a public forum/issue. `docs/fixtures.md` owns
the redaction rules; D21's possible redacted capture helper is still unbuilt.

## Next decision gate

After a small external test round:

1. fix concrete portability/usability defects found by testers;
2. avoid speculative schema/features without evidence;
3. tag the candidate intended for upstream review;
4. re-read the current contribution requirements for each upstream tree;
5. prepare separate backend and LuCI PRs, referencing the public testing/evidence
   where useful.

If forum interest is low, that is still useful evidence: the repository remains
a working diagnostic without forcing upstream submission merely because the
engineering is complete.
