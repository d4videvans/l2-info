# l2-info

##***PLEASE NOTE: This is work in progress, it may not function as expected, or at all.***##

Answers, on one OpenWrt device, from live kernel state:

- which MAC addresses are on which ports and VLANs
- which ports are in which VLANs, tagged or untagged, and which VLAN each port
  treats as native
- what kind of L2 setup this device actually has, and what it cannot see

It takes one snapshot when you ask for it, then answers questions from that
snapshot without re-reading the hardware. It stores nothing, runs no daemon,
polls nothing, and writes no configuration.

It is a deliberately narrow, single-device tool. It makes no inferences that
require a second device, and it does not classify — it reports what it read,
counts what it found, and says plainly what it could not determine. See
`docs/principles.md`, which is the document to read first.

## Shape

Two packages, developed in this repository, intended for two different
upstream trees:

| Package | Contents | Upstream target |
|---|---|---|
| `l2-info` | rpcd ucode plugin exposing ubus object `l2-info`, plus the one core reader | `openwrt/packages` |
| `luci-app-l2-info` | LuCI view, menu entry, ACL | `openwrt/luci` |

Data is read through *readers*: small, separately packaged modules that declare
what they can see. The core ships exactly one, for the kernel bridge and
neighbour tables via netlink, and treats it identically to any third-party
one. Sources are extensible; the attribute vocabulary deliberately is not. See
`docs/readers.md`.

The backend has no LuCI dependency and is usable on a headless device:

```sh
ubus call l2-info snapshot
```

## Documentation map

One fact has one home. Where a document repeats something owned elsewhere it
is navigation, not a rival definition, and the owning document wins.

| Document | Owns |
|---|---|
| `docs/principles.md` | The architectural rules and how each is enforced |
| `docs/architecture.md` | Components, data flow, kernel interfaces, cost model |
| `docs/readers.md` | The reader contract: manifest, discovery, merging, obligations |
| `CONTRIBUTING.md` | How to work on this, and how to contribute hardware coverage |
| `docs/snapshot-format.md` | The snapshot contract: envelope, scope, rows, versioning |
| `docs/fixtures.md` | Device classes, fixture layout, capture and redaction |
| `docs/decisions.md` | Every settled and deferred decision, with consequences |
| `docs/remediation.md` | The current upstream-hardening work plan and hardware matrix |
| `CONVENTIONS.md` | Contributor and agent conventions, mechanical checks |

## Status

Implemented, covered by fixtures, and run on real hardware. A GS1920-24 v1
(rtl839x, kernel 6.18.44) assembles a full 28-port snapshot in about 1.2–1.3 s.
Live validation on that switch exposed merge, reader, scope, hint and export
defects (D40–D45), all of which are now represented in the design or fixtures.

A later x86/64 OpenWrt software-bridge sweep verified empty-bridge handling
(D46) and deliberately challenged several assumptions that had looked
reasonable from the switch captures alone. In particular, FDB row shape does
**not** portably identify hardware versus software provenance; the development
`entries_switch_reported` / `entries_bridge_reported` split was therefore
removed (D47). The same sweep added bridge-device link addresses to the
reported vocabulary so the device's own FDB observations can be recognised by
an exact reported-value join, including for an empty bridge.

D46 and D47 have since been cross-checked again on the real GS1920-24 v1.
Generic RTM_GETLINK identifies its `switch` interface as
`linkinfo.type == "bridge"` and supplies its link address; AF_BRIDGE exposes the
same bridge self-mastered. With the current backend, `br.address` is present,
matching FDB observations are marked local, and the removed provenance-split
fields stay absent.

A GS1900-8HP B1 adds a second Realtek generation (`rtl838x`, kernel 6.12.94).
Its generic link view identifies `switch` directly as a bridge while DSA user
ports identify as `type: "dsa"` even though their nested slave metadata also
contains `type: "bridge"`; the VLAN child `switch.20` identifies as `type:
"vlan"`. The production backend reports exactly one bridge and eight ports,
keeps `switch.20` out of the bridge-port collection, recognises the switch's
distinct per-port link addresses as local, and produced 141 raw FDB
observations in 1.187 s. The simultaneous `bridge -j fdb show` cross-check also
contained 141 rows. A minimal redacted `rtl838x-dsa-link-shape` source fixture
pins the new link representation without copying the live forwarding table.

The current ucode/mechanical suite has run on the GS1920 and on the GS1900
checkout used for this validation: all 30 then-existing groups pass, including
the `null-empty-dump` (D48) and `empty-bridge-local` (D47) regressions.
Browser-side hint/export/query/diff unit tests are still skipped on targets
without Node and remain a CI task. The newly-added RTL838x source fixture was
created after the GS1900 run and still needs a subsequent suite execution.

`sh tests/run.sh` discovers and replays fixtures across source, discovery and
device seams and runs the mechanical checks that enforce the principles. With
Node present it also directly tests hint, export, query/filter and diff/scope
policy. What that proves is parsing, merging, scope declaration, derivation and
the tested presentation policy. What it cannot prove is that any real driver
behaves as its fixture claims, or what a snapshot costs on a switch — both need
hardware (`docs/fixtures.md`, final section).

Open decisions: D21 (a `capture` method for fixture contribution) and D22
(panel layout).

## Trying it

Git is **not required on a target OpenWrt device**. A normal development flow is
to download or extract the desired repository branch on another machine, copy
the resulting directory to the device (for example to `/tmp/l2-info` with
WinSCP), and run the helper scripts from that copied checkout.

```sh
# dependencies
apk add rpcd-mod-ucode ucode-mod-rtnl ucode-mod-ubus ucode-mod-fs
# or: opkg install rpcd-mod-ucode ucode-mod-rtnl ucode-mod-ubus ucode-mod-fs

cd /tmp/l2-info

# install/update the backend from this copied checkout
sh tools/install-dev-backend.sh

# take one read-only hardware-validation bundle, including the fixture suite
sh tools/collect-validation.sh
```

`tools/install-dev-backend.sh` is a development helper, not a package-manager
replacement. Because manual copying bypasses package dependency resolution, it
first verifies that the ucode modules required by the backend are actually
available and prints the appropriate `apk add`/`opkg install` command if not.
It then installs/reloads the core before replacing the dynamically loaded
reader, avoiding a transient new-reader/old-assembler contract mismatch, and
verifies that the ubus object re-registers. It does not trigger a snapshot
automatically.

`tools/collect-validation.sh` creates a timestamped directory under `/tmp` by
default. It records board metadata, runtime module availability, one production
snapshot, the safe rtnetlink link probe, optional `bridge -j` cross-checks when
`ip-bridge` is installed, and the fixture/mechanical test output. It requires no
git, Node or jq. When `sha256sum` is available it also records hashes of both
the copied source files and the installed backend, so an archive/WinSCP
workflow still has exact code provenance. Copy the resulting directory off the
device with WinSCP for analysis.

Validation bundles are deliberately raw evidence and may contain MAC addresses,
IP addresses and host names. They are suitable for private analysis but must not
be committed as fixtures until D15 redaction has been applied.

For development from another Unix-like machine, the individual backend/view
files can still be copied with `scp`; the copied-checkout workflow above is the
preferred path when validating several physical devices.

## Relation to bearings

Some of the design choices are related to something else I'm working on, as yet
unpublished:
`bearings` is a separate fleet-scale system: many devices, spooled captures, a
store, and cross-device inference. This project borrows its attribute
vocabulary and several of its hard-won lessons (see `docs/decisions.md` D9,
D18, D19) and deliberately borrows none of its machinery. The two answer
different questions, and this one exists because the narrow question does not
need any of that apparatus.

## Licence

Apache-2.0, matching LuCI (`docs/decisions.md` D16).
