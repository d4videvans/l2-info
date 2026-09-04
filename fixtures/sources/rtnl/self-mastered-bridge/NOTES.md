# sources/rtnl/self-mastered-bridge

Taken from a live GS1920-24 v1 (rtl839x, kernel 6.18.44), redacted.

Two things this device does that no synthetic fixture had:

1. **The bridge names itself as its own master.** In its AF_BRIDGE link dump
   the bridge — which is called `switch`, not `br-something` — appears with
   `master: "switch"`. The original bridge detection excluded a bridge from the
   ports collection only when it had *no* master, so the bridge was emitted as
   a port of itself and its own `port_count` counted it: 29 ports on a 28-port
   switch.

2. **An unresolved neighbour.** The kernel reported `0.0.0.0` with an all-zero
   hardware address, which the reader turned into a mapping and so invented a
   host that does not exist.

Also present and deliberately kept: every port reports the same
`topo.address`, because on this switch the DSA user ports all carry the
device's base MAC. That is what the kernel says, so it is reported as-is.
