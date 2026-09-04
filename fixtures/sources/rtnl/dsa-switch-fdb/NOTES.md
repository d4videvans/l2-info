# sources/rtnl/dsa-switch-fdb

Synthetic, modelled on a 24-port realtek DSA switch with bridge VLAN
filtering: `lan1` a trunk carrying seven VLANs with no PVID, `lan2`/`lan3`
access ports with PVID 20, and a `switch` conduit interface.

Shapes taken from verified kernel behaviour, not invented:

- hardware entries carry `NTF_SELF` (0x02) and **no** `master`, because
  `dsa_user_port_fdb_do_dump()` emits only `NDA_LLADDR` and `NDA_VLAN`
- one address appears twice, once from hardware and once from the software
  bridge with `NTF_MASTER` (0x04), as assisted learning on the CPU port
  produces
- protocol multicast rows sit on the conduit interface as self/permanent with
  no VLAN id at all
- `aa:bb:cc:44:55:66` on `lan2` has no `vlan` key: an untagged arrival, which
  the kernel emits without `NDA_VLAN`

Asserts that the reader reports all of this and infers none of it.
