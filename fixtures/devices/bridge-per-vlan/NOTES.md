# devices/bridge-per-vlan

One bridge per VLAN, with tagging at the netdev layer (`eth0.10`, `eth0.20`)
rather than by bridge VLAN filtering. Each bridge has filtering off and its
own single internal VLAN, so the VLAN ids present are not 802.1Q tags and must
not be read as segment membership.

Asserts multiple bridge rows each with their own port_count, and that no
`derived.vlan` is invented for rows whose port has no PVID. The 802.1Q tag
lives in the interface *name* here, which this tool reports and deliberately
does not parse — inferring a VLAN id from a string would be a classification
(P2), and the tag is already visible to anyone reading the port column.
