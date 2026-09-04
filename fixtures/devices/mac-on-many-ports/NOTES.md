# devices/mac-on-many-ports

Modelled directly on a live GS1920-24 v1 (rtl839x, OpenWrt kernel 6.18) whose
first snapshot exposed a merge defect. Not a hardware class: a regression
fixture for D40.

The device reported `33:33:00:00:00:01` on three interfaces at once — `eth0`,
`switch` and `switch.20` — which is normal, because every multicast group
address is present on every port. The assembler keyed FDB entities on the MAC
alone, so those three observations collapsed into one entity and their
differing `fdb.port` values were reported as a *conflict between `rtnl` and
`rtnl`*. A single reader cannot disagree with itself, so the conflict machinery
was being handed something it was never for.

This fixture covers all three shapes the fix has to get right:

- one address on three ports: three entities, no conflict
- one unicast address on two ports: two entities, and the
  `mac_on_several_ports` hint fires (before the fix that hint could never fire,
  which should have been the clue)
- the same forwarding entry reported twice on one port, once from the hardware
  table as `self` and once from the software bridge as `master`: one entity
  with the flags unioned, and `fdb.bridge` picked up from whichever row
  carried it
