# sources/rtnl/sw-bridge-novlan

Software bridge with VLAN filtering off — a plain router or AP. No port
carries `bridge_vlan_info`, and no FDB entry carries `NDA_VLAN`, because the
kernel omits it when the id is zero.

The point of the fixture: this looks identical to a filtering bridge that
happens to have no VLANs configured, *unless* the filtering flag is read from
the bridge itself. It asserts that the reader reads it (P4) rather than
inferring the answer from an absence of VLAN ids.
