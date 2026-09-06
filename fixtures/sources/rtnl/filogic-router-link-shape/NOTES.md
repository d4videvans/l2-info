# sources/rtnl/filogic-router-link-shape

Minimal redacted projection of a live Cudy WR3000P v1 running OpenWrt 25.12.5
on `mediatek/filogic` (kernel 6.12.94), captured 2026-09-05.

This fixture exists for source-shape coverage, not to reproduce the router's
full forwarding table or its site-specific VLAN layout.

The live generic RTM_GETLINK dump adds a useful case beyond the Realtek switch
fixtures:

1. `br-lan` identifies directly as `linkinfo.type: "bridge"` and carries its
   link address.
2. A DSA LAN port identifies as `linkinfo.type: "dsa"` with nested
   `linkinfo.slave.type: "bridge"`.
3. Other real bridge members (`wan` and wireless AP interfaces) have no
   top-level `linkinfo.type` at all; they only carry nested
   `linkinfo.slave.type: "bridge"`.
4. VLAN children such as `br-lan.20` identify as `linkinfo.type: "vlan"` and
   are not bridge ports.

The important contract point is that generic RTM_GETLINK establishes bridge
**identity**. It is not required to classify every member. AF_BRIDGE remains the
membership/VLAN view, so members with no useful generic top-level kind are still
reported correctly as ports while VLAN child devices are not promoted into the
port set.

In the corresponding live production snapshot all collections were `ok`: one
bridge, eight ports, 130 raw FDB observations, 13 neighbours and no conflicts.
`bridge -j fdb show` also returned 130 rows. The assembled FDB contained 127
observations because three same-MAC/same-port/same-VLAN pairs differed only in
reported flags and merged by D40's observation identity rules. In each pair the
surviving union included `self` while `derived.local` remained false, providing
additional live evidence for D47: `self` is not a locality or provenance test.

The production snapshot completed in 233 ms on this router, materially faster
than the roughly 1.2 s Realtek switch captures, though this single comparison is
not treated as a general performance model.
