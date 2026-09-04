# devices/sw-bridge-novlan

Software bridge with VLAN filtering off. No port carries VLAN membership and
no FDB row carries a VLAN id, so every `derived.vlan` is null with a null
source — there is no PVID to fall back to, and the tool says so rather than
inventing VLAN 1.

Asserts `br.vlan_filtering: false` is present as a read fact. Without it, this
snapshot would be indistinguishable from a filtering bridge with no VLANs
configured, which is the ambiguity P1 exists to forbid.
