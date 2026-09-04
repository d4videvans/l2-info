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
| `CONVENTIONS.md` | Contributor and agent conventions, mechanical checks |

## Status

Implemented, covered by fixtures, and run on real hardware: a GS1920-24 v1
(rtl839x, kernel 6.18.44) assembled a full snapshot of 28 ports and 7 VLANs in
1.34 s. That run exposed four defects — one in the merge (D40) and three in the
reader (D41) — all fixed and pinned by fixtures verified to fail against the
code that shipped them.

A second run cross-checked the reader against `bridge fdb show` and
`bridge -j vlan show` on the same device, verifying the flag and VLAN-flag
vocabularies and exposing one documented-but-unimplemented field (D42). A third
confirmed the counts agree with iproute2 on the same device — 81 entries, 44
reported by the switch hardware — and found one more dropped field (D43). The
page itself has now been rendered on that switch, which found a hint firing on
the device's own address (D44), and the first exported file carried a
view-internal field (D45).

The live switch now reports 28 ports, zero conflicts, and 83 forwarding entries
split 45/38 between the switch hardware and the software bridge, merging to 55
distinct observations.

`tests/run.sh` replays 18 fixtures across three seams and runs the mechanical
checks that enforce the principles. What that proves is parsing, merging, scope
declaration, derivation and hint firing. What it cannot prove is that any real
driver behaves as its fixture claims, or what a snapshot costs on a switch —
both need hardware (`docs/fixtures.md`, final section).

Open decisions: D21 (a `capture` method for fixture contribution) and D22
(panel layout).

## Trying it

```sh
# dependencies
apk add rpcd-mod-ucode ucode-mod-rtnl ucode-mod-ubus ucode-mod-fs
# or: opkg install rpcd-mod-ucode ucode-mod-rtnl ucode-mod-ubus ucode-mod-fs

# backend
scp l2-info/files/usr/share/rpcd/ucode/l2-info      root@dev:/usr/share/rpcd/ucode/
scp l2-info/files/usr/share/l2-info/assemble.uc     root@dev:/usr/share/l2-info/
scp l2-info/files/usr/share/l2-info/readers/rtnl.uc root@dev:/usr/share/l2-info/readers/

# view
scp luci-app-l2-info/htdocs/luci-static/resources/view/l2-info/main.js \
    root@dev:/www/luci-static/resources/view/l2-info/
scp luci-app-l2-info/htdocs/luci-static/resources/l2-info/hints.js \
    root@dev:/www/luci-static/resources/l2-info/
scp luci-app-l2-info/root/usr/share/luci/menu.d/*.json  root@dev:/usr/share/luci/menu.d/
scp luci-app-l2-info/root/usr/share/rpcd/acl.d/*.json   root@dev:/usr/share/rpcd/acl.d/

ssh root@dev '/etc/init.d/rpcd restart; rm -f /tmp/luci-indexcache*'
ssh root@dev 'time ubus call l2-info snapshot'
```

Create the target directories first; that last line is the cost measurement
that decides whether D20 needs reopening.

## Relation to bearings

`bearings` is a separate fleet-scale system: many devices, spooled captures, a
store, and cross-device inference. This project borrows its attribute
vocabulary and several of its hard-won lessons (see `docs/decisions.md` D9,
D18, D19) and deliberately borrows none of its machinery. The two answer
different questions, and this one exists because the narrow question does not
need any of that apparatus.

## Licence

Apache-2.0, matching LuCI (`docs/decisions.md` D16).
