# devices/empty-bridge-local

Synthetic device-level contract case derived from the x86/64 OpenWrt 25.12.5
validation on kernel 6.12.94.

The live experiment showed an empty Linux bridge with its own unicast FDB
observation. With no member port there was no `topo.address` carrying the
bridge's link MAC, so D44's original port-only join marked that observation
non-local. After `eth0` was enslaved, the bridge and member both reported the
same link address and the existing port-address join correctly made it local.

This fixture pins the corrected rule: a bridge's generic RTM_GETLINK address is
reported as `br.address`, and `derived.local` joins against reported bridge and
port addresses alike. It deliberately does **not** infer locality from
`fdb.port` naming a bridge or from `self` flags.

It also asserts that the removed D42 `entries_switch_reported` /
`entries_bridge_reported` scope fields stay absent. All identifiers are
synthetic under D15.
