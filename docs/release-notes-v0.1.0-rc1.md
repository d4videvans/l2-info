# l2-info v0.1.0-rc1 — release notes

**Status:** first public pre-upstream test release.

This release candidate is intended to put `l2-info` in front of OpenWrt users
on a wider range of hardware before the backend and LuCI application are
submitted to their respective upstream repositories.

It is a test release from this repository, **not an OpenWrt feed package**.

## What l2-info does

`l2-info` is a read-only Layer 2 diagnostic for OpenWrt. From one
user-triggered snapshot it can show:

- MAC addresses and the ports on which they are visible;
- bridge and VLAN context for those observations;
- native/untagged VLAN information where the kernel provides enough evidence;
- port-level VLAN membership and observed VLANs;
- host names or neighbour IP addresses when the device itself knows them;
- changes between the current and previous snapshot;
- explicit coverage/status information when a data area cannot be read.

The LuCI page is **Status → MAC & VLAN Lookup**.

## Design properties

The release candidate intentionally keeps a narrow diagnostic boundary:

- snapshots are taken only when the user asks;
- there is no background polling;
- network observations are held in memory rather than stored to disk;
- there is no UCI configuration;
- the LuCI ACL is read-only;
- the project does not change bridge, VLAN, interface or forwarding state;
- uncertain or unavailable information is represented explicitly rather than
  silently converted into an empty result.

The backend exposes the same snapshot through:

```sh
ubus call l2-info snapshot
```

## Installation for this release candidate

Git is not required on the router. Download or clone the tagged repository on
another machine, copy the checkout to the OpenWrt device (for example as
`/tmp/l2-info`), then run:

```sh
cd /tmp/l2-info
sh tools/install-test.sh
```

If a required runtime dependency is missing, the installer stops before
copying project files and prints the appropriate package-manager command.

If LuCI is installed, refresh it after installation and open
**Status → MAC & VLAN Lookup**.

To remove the test installation:

```sh
cd /tmp/l2-info
sh tools/uninstall-test.sh
```

The uninstall removes only project files and leaves shared OpenWrt dependencies
installed. See `docs/getting-started.md` for the full installation, update,
troubleshooting and privacy guidance.

## Synthetic screenshot/demo mode

For demonstrations without exposing a live network, the repository includes a
separate synthetic surface:

```sh
sh tools/install-screenshot-demo.sh
```

It creates **Status → MAC & VLAN Lookup (synthetic demo)** using repository
supplied locally administered MAC addresses, documentation-range IP addresses
and demo VLANs. It does not fall back to the live snapshot reader.

Remove it with:

```sh
sh tools/uninstall-screenshot-demo.sh
```

## Hardware evidence before RC1

The current design has been exercised across deliberately different OpenWrt
platforms:

| Platform | Validation role |
|---|---|
| x86/64 software bridges | no bridge, empty bridge, populated bridge and VLAN-filtered bridge behaviour |
| Zyxel GS1920-24 v1 (`rtl839x`) | 24-port model with four additional combo/SFP interfaces (28 DSA interfaces exposed) and expensive hardware FDB walk |
| Zyxel GS1900-8HP B1 (`rtl838x`) | second Realtek generation and a different DSA link representation |
| Cudy WR3000P v1 (`mediatek/filogic`) | mixed DSA, WAN and Wi-Fi bridge membership |
| Linksys SPNMX56 (`qualcommax/ipq50xx`) | Qualcomm DSA and all-zero FDB placeholder behaviour |
| Linksys EA8300 (`ipq40xx/generic`) | older Qualcomm DSA/Wi-Fi representation |

This is evidence, **not a compatibility whitelist**. Wider target coverage is a
primary purpose of the RC/forum-test phase.

## Validation and packaging state

Mandatory CI covers:

- replay of source, discovery and device fixtures with OpenWrt-pinned host
  `ucode`;
- browser-side query, hint and snapshot-diff tests;
- JSON fixture validation;
- shell helper syntax and the synthetic demo backend/snapshot;
- current LuCI ESLint;
- LuCI translation-template drift;
- builds of both intended packages in the official OpenWrt x86_64 SDK.

The repository contains two package trees intended to be submitted separately
after public testing:

- `l2-info` → `openwrt/packages`;
- `luci-app-l2-info` → `openwrt/luci`.

The backend package is categorized under **Network**, rather than routing, and
the LuCI application is a read-only **Status** page.

## User-visible improvements included in RC1

The pre-release hardening work includes:

- explicit snapshot age and duration;
- MAC/port/VLAN filtering without re-reading hardware;
- clear distinction between a VLAN reported by the forwarding entry and a
  native/PVID VLAN inferred for an untagged arrival;
- comparison of two compatible user-triggered snapshots;
- explicit data-source and coverage details;
- safe JSON export using an allowlist of reported fields;
- improved MAC-address contrast while retaining monospace presentation;
- user-facing install, update, uninstall and troubleshooting documentation;
- a reversible synthetic demonstration mode for screenshots.

## Known limitations and cautions

- This RC is not in the official OpenWrt package feeds; installation is from the
  repository checkout.
- Completeness depends on what the running kernel and switch driver expose.
  `l2-info` reports unavailable/indeterminate coverage instead of pretending it
  has data it could not read.
- Some hardware FDB walks are comparatively expensive. The snapshot duration is
  shown deliberately, and the project does not poll automatically.
- Host names are only available when the OpenWrt device itself has suitable
  lease/name information; a pure switch may correctly show no names.
- The core currently ships one reader, based on rtnetlink. Additional readers
  should be driven by real missing hardware evidence rather than by target
  allowlists.
- LuCI JSON downloads and hardware-validation bundles can contain real MAC
  addresses, IP addresses and host names. Review/redact them before sharing
  publicly.

## What feedback is most useful

For a normal report, record the OpenWrt version, device model/target, exact tag
or revision, snapshot duration, relevant **Device and data-source details**, and
the result that appeared wrong or confusing.

For a new hardware target, `tools/collect-validation.sh` can capture deeper
evidence. Treat its output as potentially private network data and share it
privately or redact it before publication.

The most useful RC1 outcome is not a larger feature list; it is confidence that
the current small read-only contract remains accurate and comprehensible across
more OpenWrt hardware.

## After RC1

Evidence-backed correctness, portability, installation and serious performance
issues should be fixed during the test phase. Feature requests that broaden the
project beyond Layer 2 observation should normally wait.

Once the test phase no longer exposes material contract or portability issues,
the next milestone is to prepare separate upstream submissions for the backend
and LuCI package trees.


## External-review remediation

Before RC freeze, per-port host aggregates were corrected to exclude local/non-unicast observations; bridge identity is retained when only VLAN-filtering state is unreadable; neighbour-family partial failures are declared; browser diff raw identity now matches the backend while move detection operates at port-presence granularity; filter-relative counts and i18n/hint consistency were corrected; backend package version is `0.1.0`; and synchronous rpcd/transport constraints are documented. LuCI continues to use normal `luci.mk` revision-derived package versioning; tester reports should include the source RC tag and commit SHA.
