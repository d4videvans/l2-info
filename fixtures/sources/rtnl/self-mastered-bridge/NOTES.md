# sources/rtnl/self-mastered-bridge

Taken from a live GS1920-24 v1 (rtl839x, kernel 6.18.44), redacted.

Two things this device does that no synthetic fixture had:

1. **The bridge names itself as its own master.** In its AF_BRIDGE link dump
   the bridge — which is called `switch`, not `br-something` — appears with
   `master: "switch"`. The original bridge detection excluded a bridge from the
   ports collection only when it had *no* master, so the bridge was emitted as a
   port of itself and its own `port_count` counted it: 29 ports on a device that
   should expose 28 DSA interfaces (the GS1920-24's 24-port model plus four
   additional combo/SFP interfaces).

2. **An unresolved neighbour.** The kernel reported `0.0.0.0` with an all-zero
   hardware address, which the reader turned into a mapping and so invented a
   host that does not exist.

Also present and deliberately kept: every port reports the same
`topo.address`, because on this switch the DSA user ports all carry the
device's base MAC. That is what the kernel says, so it is reported as-is.

## D46/D47 generic-link companion

The original GS1920 capture did not record the generic RTM_GETLINK view because
that was not a reader input at the time. When D46 separated bridge identity
from AF_BRIDGE membership, this fixture gained the minimal companion
`link_generic` row identifying `switch` as `linkinfo.type: "bridge"`.

That shape is now **live-verified on the same hardware** rather than synthetic.
A 2026-09-05 probe on this GS1920-24 v1, running OpenWrt SNAPSHOT
r36029-ce22f3ba6c with rtl839x kernel 6.18.44, reported `switch` in generic
RTM_GETLINK with `master: null`, `linkinfo.type: "bridge"`, and an interface
address present. The AF_BRIDGE view of the same device reported
`master: "switch"` and `linkinfo: null`, and `/sys/class/net/switch/bridge`
independently identified it as a bridge.

After installing the current backend, a production snapshot confirmed that the
reported `br.address` is present and equals the DSA-port `topo.address`; eight
FDB observations matching a device address were marked `derived.local: true`.
The removed D47 provenance-split scope fields were absent. The fixture therefore
keeps the redacted bridge address in the generic companion and asserts it as a
reported fact rather than inferring it from the AF_BRIDGE row.

The same checkout's full OpenWrt suite passed 30 ucode/mechanical groups,
including the `null-empty-dump` (D48) and `empty-bridge-local` (D47) regression
fixtures. Node-based presentation tests were skipped because Node was not
installed on the target.
