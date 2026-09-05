# sources/rtnl/zero-fdb-placeholder

Minimal regression extracted from a live Linksys SPNMX56 on OpenWrt 25.12.5
(`qualcommax/ipq50xx`, kernel 6.12.94), captured 2026-09-05.

The live AF_BRIDGE FDB dump contained large runs of identical rows whose
hardware address was `00:00:00:00:00:00`. They appeared on the three DSA LAN
ports with VIDs 66, 67 and 68 even though those VIDs were absent from the
corresponding bridge VLAN membership.

The key evidence was a second dump moments later. The production snapshot had
seen 753 raw FDB rows; the later `bridge -j fdb show` had 1,423. In that later
dump 1,303 rows were all-zero placeholders. After removing only rows whose MAC
was all-zero, exactly 120 non-zero `(MAC, port, VLAN)` identities remained —
and those were exactly the same 120 non-zero identities already present in the
earlier snapshot. Only the count of zero rows changed.

An FDB row cannot satisfy the `{mac}` subject contract without a usable address
identity. The rtnl reader therefore drops an all-zero FDB lladdr at the source
boundary, matching its existing treatment of incomplete all-zero neighbour
entries. This is deliberately narrow: a non-zero MAC carrying an otherwise
unexpected VID is still reported as observed.

The fixture repeats the zero row several times and places a non-zero row on the
same port and VID. It asserts that only the zero identity is discarded, so the
regression cannot accidentally become a VLAN or port filter.
