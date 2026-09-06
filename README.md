# l2-info

`l2-info` is a read-only OpenWrt diagnostic for answering a simple set of
questions from one device:

- which MAC addresses are visible on which ports and VLANs;
- which ports belong to which bridges and VLANs;
- which VLAN is native/untagged on each port;
- what changed between two user-triggered snapshots;
- what the device could not determine, rather than silently showing an empty
  result.

The LuCI page is **Status → MAC & VLAN Lookup**.

> **Project status:** pre-upstream testing. The backend and LuCI packages build
> successfully against the official OpenWrt SDK and current LuCI, but they have
> not yet been submitted to the OpenWrt package feeds. The installation method
> below is therefore a reversible test install from this repository.

## What it does — and does not do

Press **Update snapshot** and the backend reads the device's live bridge,
forwarding and neighbour state once. The browser then filters, searches and
compares that snapshot without re-reading the hardware.

`l2-info`:

- stores no network state;
- runs no daemon of its own;
- does not poll;
- ships no UCI configuration;
- has a read-only LuCI ACL;
- does not change bridge, VLAN, interface or forwarding configuration.

Some switch drivers make an FDB read comparatively expensive. The duration is
shown in the page so that cost is visible; another snapshot is only taken when
you ask for one.

## Quick test install

Git is **not** required on the OpenWrt device. Download or clone the revision
you want to test on another machine, copy the whole checkout to the router
(for example as `/tmp/l2-info` with `scp` or WinSCP), then run:

```sh
cd /tmp/l2-info
sh tools/install-test.sh
```

If a required runtime package is missing, the installer stops before copying
files and prints the appropriate `apk add` or `opkg install` command. Run that
command, then run the installer again.

If LuCI is installed, the same command installs the web interface. Refresh LuCI
and open **Status → MAC & VLAN Lookup**. For a headless check:

```sh
ubus call l2-info snapshot
```

To remove the test install:

```sh
cd /tmp/l2-info
sh tools/uninstall-test.sh
```

The uninstall removes only `l2-info` files and leaves shared dependencies
installed.

For step-by-step installation, updating, troubleshooting and privacy notes, see
[`docs/getting-started.md`](docs/getting-started.md).

### Safe screenshots with synthetic data

For screenshots or demonstrations, install the ordinary test build first, then
add the separate synthetic demo surface:

```sh
sh tools/install-screenshot-demo.sh
```

Refresh LuCI and open **Status → MAC & VLAN Lookup (synthetic demo)**. That page
uses only repository-supplied synthetic MACs, documentation-range IP addresses
and demo VLANs; the ordinary page remains connected to the live device. Remove
the demo surface with:

```sh
sh tools/uninstall-screenshot-demo.sh
```

The getting-started guide explains the separation and how to edit the harmless
demo values if a different screenshot would be clearer.

## Hardware validation so far

The current design has been exercised on deliberately different OpenWrt
platforms rather than being tied to a device allowlist:

| Platform | Validation role |
|---|---|
| x86/64 software bridges | no bridge, empty bridge, populated bridge and VLAN-filtered bridge behaviour |
| Zyxel GS1920-24 v1 (`rtl839x`) | 28-port Realtek DSA switch, expensive hardware FDB walk |
| Zyxel GS1900-8HP B1 (`rtl838x`) | second Realtek generation and a different DSA link representation |
| Cudy WR3000P v1 (`mediatek/filogic`) | mixed DSA, WAN and Wi-Fi bridge membership |
| Linksys SPNMX56 (`qualcommax/ipq50xx`) | Qualcomm DSA and all-zero FDB placeholder behaviour |
| Linksys EA8300 (`ipq40xx/generic`) | older Qualcomm DSA/Wi-Fi representation |

That is evidence, not a compatibility whitelist. Other targets are exactly what
the pre-upstream test phase is intended to find. The detailed hardware matrix
and measurements live in [`docs/remediation.md`](docs/remediation.md).

## Package shape

The repository develops two packages intended for two upstream trees:

| Package | Purpose | Intended upstream |
|---|---|---|
| `l2-info` | rpcd ucode backend and the core rtnetlink reader | `openwrt/packages` |
| `luci-app-l2-info` | LuCI view, menu entry and read-only ACL | `openwrt/luci` |

The backend has no LuCI dependency and exposes one method:

```sh
ubus call l2-info snapshot
```

Readers are an internal extension seam for adding other *sources* of L2 facts
without allowing each source to invent a different output vocabulary. The core
currently ships one reader, using rtnetlink.

## Testing and CI

`sh tests/run.sh` replays source, discovery and device fixtures and runs the
mechanical checks that enforce the project's design rules. CI additionally:

- runs the browser-side hint/export/query/diff tests with Node;
- validates every fixture JSON file;
- runs current LuCI ESLint and checks that the translation template is current;
- builds both intended packages in the official OpenWrt x86_64 SDK.

Passing CI proves the tested parsing, merging, declaration, presentation logic
and package integration. It cannot prove how an unseen physical driver behaves
or how long its hardware reads take; those still need live validation.

## Useful documentation

Start with the document that matches what you are trying to do:

- **Install or test it:** [`docs/getting-started.md`](docs/getting-started.md)
- **Contribute or run the tests:** [`CONTRIBUTING.md`](CONTRIBUTING.md)
- **Understand the design rules:** [`docs/principles.md`](docs/principles.md)
- **Understand the components and kernel reads:** [`docs/architecture.md`](docs/architecture.md)
- **Consume the JSON snapshot:** [`docs/snapshot-format.md`](docs/snapshot-format.md)
- **Understand or add a reader:** [`docs/readers.md`](docs/readers.md)
- **Add hardware evidence/fixtures:** [`docs/fixtures.md`](docs/fixtures.md)
- **See why design choices were made:** [`docs/decisions.md`](docs/decisions.md)
- **See the upstream-hardening history and hardware matrix:** [`docs/remediation.md`](docs/remediation.md)

## Feedback

For an ordinary bug or confusing result, include the OpenWrt version, device
model/target, the exact revision or tag tested, and what the **Device and
data-source details** panel says.

For a new hardware target, `sh tools/collect-validation.sh` creates a much more
useful diagnostic bundle. **That bundle and the LuCI “Download JSON” export can
contain real MAC addresses, IP addresses and hostnames. Do not post either
publicly without reviewing/redacting it.** See `docs/getting-started.md` and
`docs/fixtures.md`.

## Licence

Apache-2.0.
