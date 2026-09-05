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
(rtl839x, kernel 6.18.44) assembles a full 28-port snapshot in about 1.3 s. Live
validation on that switch exposed merge, reader, scope, hint and export defects
(D40–D45), all of which are now represented in the design or fixtures.

A later x86/64 OpenWrt software-bridge sweep verified empty-bridge handling
(D46) and deliberately challenged several assumptions that had looked
reasonable from the switch captures alone. In particular, FDB row shape does
**not** portably identify hardware versus software provenance; the development
`entries_switch_reported` / `entries_bridge_reported` split was therefore
removed (D47). The same sweep added bridge-device link addresses to the
reported vocabulary so the device's own FDB observations can be recognised by
an exact reported-value join, including for an empty bridge.

D46's bridge-identity mechanism has since been cross-checked again on the real
GS1920-24 v1: generic RTM_GETLINK identifies its `switch` interface as
`linkinfo.type == "bridge"`, while the AF_BRIDGE view exposes the same bridge
self-mastered. This independently confirms the identity/membership split on
rtl839x rather than only on a software bridge.

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

```sh
# dependencies
apk add rpcd-mod-ucode ucode-mod-rtnl ucode-mod-ubus ucode-mod-fs
# or: opkg install rpcd-mod-ucode ucode-mod-rtnl ucode-mod-ubus ucode-mod-fs

# backend, when the repository checkout is already on the target
sh tools/install-dev-backend.sh

# alternatively copy the backend from another machine
scp l2-info/files/usr/share/rpcd/ucode/l2-info      root@dev:/usr/share/rpcd/ucode/
scp l2-info/files/usr/share/l2-info/assemble.uc     root@dev:/usr/share/l2-info/
scp l2-info/files/usr/share/l2-info/readers/rtnl.uc root@dev:/usr/share/l2-info/readers/

# view
scp luci-app-l2-info/htdocs/luci-static/resources/view/l2-info/main.js \
    root@dev:/www/luci-static/resources/view/l2-info/
scp luci-app-l2-info/htdocs/luci-static/resources/l2-info/*.js \
    root@dev:/www/luci-static/resources/l2-info/
scp luci-app-l2-info/root/usr/share/luci/menu.d/*.json  root@dev:/usr/share/luci/menu.d/
scp luci-app-l2-info/root/usr/share/rpcd/acl.d/*.json   root@dev:/usr/share/rpcd/acl.d/

ssh root@dev '/etc/init.d/rpcd restart; rm -f /tmp/luci-indexcache*'
ssh root@dev 'time ubus call l2-info snapshot'
```

`tools/install-dev-backend.sh` is a development helper, not a package-manager
replacement. It copies the backend files from the current checkout, reloads
rpcd and verifies that the ubus object re-registers; it does not trigger a
snapshot automatically.

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
