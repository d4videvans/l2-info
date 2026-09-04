# sources/rtnl/self-mastered-bridge

Taken from a live GS1920-24 v1 (rtl839x, kernel 6.18.44), redacted.

Two things this device does that no synthetic fixture had:

1. **The bridge names itself as its own master.** In its AF_BRIDGE link dump
   the bridge — which is called `switch`, not `br-something` — appears with
   `master: "switch"`. The original bridge detection excluded a bridge from the
   ports collection only when it had *no* master, so the bridge was emitted as a
   port of itself and its own `port_count` counted it: 29 ports on a 28-port
   switch.

2. **An unresolved neighbour.** The kernel reported `0.0.0.0` with an all-zero
   hardware address, which the reader turned into a mapping and so invented a
   host that does not exist.

Also present and deliberately kept: every port reports the same
`topo.address`, because on this switch the DSA user ports all carry the
device's base MAC. That is what the kernel says, so it is reported as-is.

## D46 fixture migration note

The original GS1920 capture did not record the generic RTM_GETLINK view because
that was not a reader input at the time. When D46 separated bridge identity
from AF_BRIDGE membership, this fixture gained the minimal companion
`link_generic` row identifying `switch` as `linkinfo.type: "bridge"`.

That companion row is **synthetic** and is not claimed as GS1920 evidence. Its
shape was independently verified on an x86/64 OpenWrt 25.12.5 device (kernel
6.12.94), where every software bridge appeared as `linkinfo.type: "bridge"` in
the generic dump while the AF_BRIDGE view exposed `linkinfo: null` and
self-mastered bridge rows. The AF_BRIDGE and neighbour portions above remain
the original live GS1920 evidence.
