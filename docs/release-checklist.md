# Forum test release checklist

This is the repository-side checklist for the first public **pre-upstream test
release** of `l2-info`. It is deliberately not forum-post copy.

The aim of this phase is to find portability, installation, performance and
usability problems on hardware we do not own before preparing the separate
OpenWrt packages and LuCI submissions.

## 1. Freeze the candidate

- [ ] All mandatory CI jobs are green on the candidate commit:
  - unit and fixture tests;
  - shell helper syntax;
  - synthetic demo validation;
  - current LuCI ESLint and translation-template check;
  - both intended packages building in the official OpenWrt SDK.
- [ ] No known correctness regression is being deferred merely to get the
  release out.
- [ ] The README, getting-started guide, current decision register and
  remediation status describe the code that is actually being released.
- [ ] `main` contains the candidate state before the public test release is
  tagged.

The current remediation branch is intended to be merged normally rather than
squashed: its commits contain useful hardware-validation and remediation
history. A merge commit gives `main` a clear release-readiness boundary while
preserving that evidence.

## 2. Smoke-test the user path

Do this from a fresh copy of the candidate revision on at least one real
OpenWrt device.

- [ ] Run `sh tools/install-test.sh` and confirm any missing dependency is
  reported before project files are copied.
- [ ] Confirm `ubus call l2-info snapshot` returns a usable snapshot.
- [ ] Confirm **Status → MAC & VLAN Lookup** loads and **Update snapshot** works.
- [ ] Exercise at least one MAC, VLAN or port filter.
- [ ] Take a second snapshot and confirm the comparison section behaves
  sensibly.
- [ ] Confirm **Download JSON** works, while remembering that the downloaded
  file may contain private network identifiers.
- [ ] Run `sh tools/uninstall-test.sh` and confirm the project is removed while
  shared OpenWrt dependencies remain installed.
- [ ] Reinstall once after the uninstall, so the documented path is known to be
  reversible rather than merely installable.

## 3. Prepare safe public material

- [ ] Install the separate synthetic screenshot surface with
  `sh tools/install-screenshot-demo.sh`.
- [ ] Take the main screenshot from **MAC & VLAN Lookup (synthetic demo)**, not
  from the live page.
- [ ] Keep **Device and data-source details** collapsed for the primary image so
  the screenshot focuses on snapshot, lookup and port/VLAN information.
- [ ] Check visually that the screenshot contains only synthetic `02:` MACs,
  documentation-range IP addresses and demo VLANs/host names.
- [ ] Remove the demo afterwards with
  `sh tools/uninstall-screenshot-demo.sh` if it is no longer needed.

Do **not** post a raw `tools/collect-validation.sh` bundle or LuCI JSON download
without reviewing and redacting it. They can contain real MAC addresses, IP
addresses and host names.

## 4. Mainline and tag

Only after the candidate CI and smoke test are green:

- [ ] Merge `remediation/upstream-hardening-v2` into `main` with a normal merge
  commit; do not squash the validation/remediation history.
- [ ] Confirm the `main` README presents the pre-upstream test install as the
  front-door path.
- [ ] Confirm CI is green on the resulting `main` commit.
- [ ] Tag that exact commit as the release candidate (proposed:
  `v0.1.0-rc1`).
- [ ] Use the tag, not a moving branch name, in public tester instructions.
- [ ] Use `docs/release-notes-v0.1.0-rc1.md` as the factual basis for any GitHub
  release notes or announcement text.

Creating a GitHub release, posting to the OpenWrt forum or submitting anything
upstream is an explicit external action and is not implied by this checklist.

## 5. Ask testers for evidence that changes decisions

For an ordinary report, ask for:

- OpenWrt version;
- device model and target/subtarget;
- exact `l2-info` tag/revision;
- what went wrong or was confusing;
- snapshot duration;
- the relevant **Device and data-source details** statuses.

For new hardware or ambiguous results, the validation collector may be useful,
but detailed bundles should be shared privately or redacted before publication.

Particularly useful coverage includes:

- DSA targets and switch drivers not already in the hardware matrix;
- devices where the FDB read is unusually slow;
- empty or lightly used bridges where “empty” and “unreadable” are easy to
  confuse;
- unusual VLAN topologies;
- older supported OpenWrt releases if someone is already running them.

## 6. Triage without turning the test phase into feature creep

Treat as release-candidate defects:

- incorrect MAC/port/VLAN facts;
- a result presented as known when it is actually unknown;
- installation/removal failures;
- browser errors or inaccessible LuCI presentation;
- unexpectedly destructive or persistent behaviour;
- serious target-specific snapshot cost that is not made visible to the user.

Investigate before deciding:

- data gaps caused by a particular kernel/switch driver;
- target-specific representation differences;
- unexpectedly slow but bounded reads.

Normally defer until after the upstream-readiness decision:

- additional dashboards or unrelated network information;
- automatic polling/background monitoring;
- configuration-changing features;
- speculative reader backends without hardware evidence;
- presentation additions that do not help interpret the current facts.

## 7. Exit criteria for the forum-test phase

The project is ready to move from public testing to upstream preparation when:

- [ ] no known correctness or installation defect remains unresolved;
- [ ] reports from additional hardware either work correctly or have an
  evidence-backed fix/limitation;
- [ ] snapshot cost remains bounded and visible on tested targets;
- [ ] user-facing installation, privacy and troubleshooting instructions have
  survived use by someone other than the original development workflow;
- [ ] the backend and LuCI package trees still pass their upstream-style CI
  gates independently;
- [ ] there is no compelling evidence that the snapshot/schema contract needs
  another breaking change.

At that point prepare the `l2-info` contribution for `openwrt/packages` and the
`luci-app-l2-info` contribution for `openwrt/luci` as separate upstream changes.
