# Getting started

This is the practical guide for trying `l2-info` **as it is not available in the
official OpenWrt feeds**.

The test install copies the same backend and LuCI files that potential future
packages will contain, but it bypasses the package manager. It is intended for
evaluation and hardware testing, not as the permanent distribution mechanism.

## Before you start

You need:

- an OpenWrt device with root shell access;
- a copy of this repository revision;
- LuCI if you want the web interface.

Git does not need to be installed on the router. It is usually easier to
download/clone the repository on another computer and copy the whole directory
to `/tmp/l2-info` with `scp`, WinSCP or another file-transfer tool.

The current hardware validation has been on OpenWrt 25.12-era systems and
current OpenWrt/LuCI build trees across x86, Realtek DSA, Mediatek Filogic and
Qualcomm DSA targets. Other OpenWrt versions and targets may work, but should be
treated as new validation rather than assumed support.

## What the test install changes

The installer:

1. checks that the required ucode runtime modules can be loaded;
2. copies the backend under `/usr/share/rpcd/ucode` and `/usr/share/l2-info`;
3. reloads `rpcd` so the `l2-info` ubus object is registered;
4. if LuCI is present, copies the LuCI JavaScript, menu and read-only ACL and
   clears LuCI's relevant caches.

It **does not** alter network, bridge, VLAN, interface or forwarding
configuration. It installs no UCI configuration and creates no daemon.

The installation itself necessarily writes these program files to the router
and reloads `rpcd`; "read-only" describes what the installed diagnostic does to
the network state.

## Install

Copy the whole checkout to the router. For example, from a Unix-like computer:

```sh
scp -r l2-info root@192.168.1.1:/tmp/l2-info
```

On the OpenWrt device:

```sh
cd /tmp/l2-info
sh tools/install-test.sh
```

### Missing dependencies

A package-manager installation would resolve these automatically. The
pre-upstream test installer deliberately does not install packages without
asking.

The backend needs:

- `rpcd-mod-ucode`
- `ucode-mod-fs`
- `ucode-mod-rtnl`
- `ucode-mod-ubus`

If one is missing, installation stops before copying the backend and prints a
command such as:

```sh
apk add rpcd-mod-ucode ucode-mod-fs ucode-mod-rtnl ucode-mod-ubus
```

or, on an opkg-based release:

```sh
opkg install rpcd-mod-ucode ucode-mod-fs ucode-mod-rtnl ucode-mod-ubus
```

Run the command the installer reports, then run:

```sh
sh tools/install-test.sh
```

again.

## Use it

### LuCI

Refresh the LuCI page after installation and open:

**Status → MAC & VLAN Lookup**

Nothing is read until you press **Update snapshot**.

The page then lets you:

- filter by port, VLAN and full/partial MAC address;
- include or hide multicast/protocol addresses;
- see ports, bridge membership, tagged/untagged VLANs and observed MAC counts;
- compare the current snapshot with the previous one when their acquisition
  scope is compatible;
- inspect the device and data-source details;
- download a JSON export of reported facts and declared scope.

The age shown beside the snapshot continues to increase, but that timer does
not poll or refresh the device.

## Safe screenshots and demonstrations

A normal snapshot contains real network identifiers. For screenshots, do not
try to edit a live page or publish a live export. Instead install the separate
synthetic demo surface after the ordinary test install:

```sh
cd /tmp/l2-info
sh tools/install-screenshot-demo.sh
```

Refresh LuCI and open:

**Status → MAC & VLAN Lookup (synthetic demo)**

This creates a second, temporary `l2-info-demo` ubus object and a second LuCI
view. It does **not** replace the normal `l2-info` object or modify the ordinary
page. The demo snapshot contains only clearly synthetic values:

- locally administered `02:00:00:...` MAC addresses;
- RFC documentation addresses from `192.0.2.0/24`;
- VLANs 10, 20 and 30;
- names such as `demo-laptop` and `demo-printer`;
- device identity `Synthetic l2-info demo` / `demo/synthetic`.

The synthetic snapshot lives in `tools/demo-snapshot.uc`. It can be edited in
the copied checkout before installation if a different harmless example would
make a better screenshot. Keep it synthetic; never paste live values into that
file and commit them.

Remove only the demo surface with:

```sh
sh tools/uninstall-screenshot-demo.sh
```

The real test installation is left untouched. `tools/uninstall-test.sh` also
removes the demo surface first when it is present, so a complete cleanup does
not leave a broken demo menu entry behind.

### Command line / headless device

The backend is independent of LuCI:

```sh
ubus call l2-info snapshot
```

A healthy installation should also expose the object:

```sh
ubus -v list l2-info
```

## Update a test install

Copy the newer checkout over the old copied checkout (or copy it to a new
temporary directory), then run the same installer again:

```sh
cd /tmp/l2-info
sh tools/install-test.sh
```

The backend helper deliberately reloads the core before replacing the
dynamically discovered reader, so a manual update does not expose a new reader
to an old assembler between copies.

## Uninstall

From the copied checkout:

```sh
cd /tmp/l2-info
sh tools/uninstall-test.sh
```

This removes only the files copied by the test installer, clears the LuCI
caches used by this app, and reloads `rpcd`.

It does **not** remove `rpcd-mod-ucode` or the `ucode-mod-*` dependencies. They
are shared OpenWrt packages and may be used by other software.

## What results mean

A few behaviours are deliberate and can otherwise look like failures:

- **An empty FDB can be `indeterminate`.** From one successful empty read the
  tool may not be able to distinguish an idle device from a driver that does
  not expose the relevant forwarding entries.
- **Some addresses are hidden by default.** Multicast and protocol addresses
  can be shown with the checkbox on the page.
- **A VLAN can be marked native.** If an untagged FDB observation carries no
  VLAN id, the backend can resolve it from the reporting port's PVID and marks
  the provenance as native/inferred rather than pretending the FDB reported it.
- **A snapshot can take around a second on some switches.** Some DSA drivers
  walk hardware forwarding tables per port. The page shows the measured
  duration and never polls.
- **A comparison can be refused.** If two snapshots successfully read different
  load-bearing sources, showing a network diff would confuse a coverage change
  with a topology change.

## Troubleshooting

### `missing required runtime package(s)`

Install the package(s) named by the message using the `apk add` or
`opkg install` command it prints, then rerun the installer.

### `l2-info ubus object did not register`

Check:

```sh
logread | tail -100
ubus -v list l2-info
```

If necessary, try a full rpcd restart once:

```sh
/etc/init.d/rpcd restart
ubus -v list l2-info
```

If it still does not register, report the device model, OpenWrt version and the
exact revision/tag you copied.

### The LuCI page is not visible

Confirm LuCI is installed and that the test installer said it installed the
LuCI files. Then hard-refresh the browser. The installer already removes
LuCI's index/module caches and reloads rpcd.

The backend can still be checked independently:

```sh
ubus call l2-info snapshot
```

### The page says a data area is unavailable or indeterminate

Open **Device and data-source details**. The status/reason there is part of the
diagnostic result; include it in a bug report rather than reducing the report to
"the table is empty".

## Reporting useful feedback

For an ordinary problem, please include:

- device model;
- output of `ubus call system board` (review it before posting);
- OpenWrt version/target/kernel;
- exact `l2-info` revision or tag tested;
- what you expected and what happened;
- the statuses/reasons shown under **Device and data-source details**;
- a screenshot if the problem is presentation-related.

For a new or unusual hardware target, this produces much better evidence:

```sh
cd /tmp/l2-info
sh tools/collect-validation.sh
```

It writes a timestamped directory under `/tmp` containing board metadata,
runtime-module checks, one production snapshot, a safe rtnetlink link probe,
optional `bridge -j` cross-checks when `bridge` is installed, and the repository
fixture/mechanical test output.

## Privacy: read before sharing captures

The application is read-only, but its output describes a real network.

The LuCI **Download JSON** file and `tools/collect-validation.sh` bundle can
contain:

- MAC addresses;
- IP addresses;
- hostnames;
- interface/bridge names;
- device/target/kernel information.

The validation collector intentionally records **raw evidence**. Do not attach
its directory to a public forum post or GitHub issue without inspecting and
redacting it.

Committed fixtures use the positive-rewrite rules in
[`fixtures.md`](fixtures.md): synthetic MACs, dropped IP/hostname annotations
and sanitised unusual local interface names. D21 records a possible future
redacted capture helper; it does **not** exist today.

For a public first report, the safest useful starting point is the device
model/target/kernel plus the scope/status summary. More detailed raw data can be
requested separately if needed.

## Development helpers

`tools/install-test.sh` is the friendly wrapper for testers.

The lower-level scripts remain available for development:

```sh
sh tools/install-dev-backend.sh
sh tools/install-dev-luci.sh
```

They are intentionally separate so backend-only and LuCI development can be
tested independently.
