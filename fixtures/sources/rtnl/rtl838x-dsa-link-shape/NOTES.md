# sources/rtnl/rtl838x-dsa-link-shape

Minimal redacted projection of a live Zyxel GS1900-8HP B1 running OpenWrt
25.12.5 on Realtek RTL8380M rev C (`realtek/rtl838x`, kernel 6.12.94), captured
2026-09-05.

This fixture exists for source-shape coverage, not to reproduce the device's
full forwarding table.

The live generic RTM_GETLINK dump showed three facts worth pinning:

1. `switch` identifies itself directly as `linkinfo.type: "bridge"` and carries
   its link address, confirming D46/D47 on rtl838x as well as rtl839x.
2. DSA user ports identify as `linkinfo.type: "dsa"` while nested
   `linkinfo.slave.type` is `"bridge"`. The nested value describes the slave's
   bridge participation and must **not** promote the port itself to bridge
   identity.
3. The VLAN child `switch.20` identifies as `linkinfo.type: "vlan"` and is not
   a bridge or bridge port. AF_BRIDGE supplies the actual bridge-port set.

The live device also reports distinct sequential link addresses on its eight
DSA user ports, unlike the GS1920-24 v1 where every user port reports the same
base address. The two synthetic addresses in this fixture preserve that
relationship without retaining hardware identifiers (D15).

In the corresponding live production snapshot all collections were `ok`, the
reader reported one bridge/eight ports/141 raw FDB observations/eight
neighbours, and `bridge -j fdb show` also contained 141 rows. The assembled FDB
contained 137 observations because two sets of byte-for-byte duplicate raw FDB
rows collapsed during merge. The distinct per-port device addresses were
recognised as local, and FDB observations on `switch.20` did not cause it to be
reported as a bridge port.
