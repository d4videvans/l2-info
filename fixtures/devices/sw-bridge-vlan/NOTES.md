# devices/sw-bridge-vlan

Software bridge with VLAN filtering on: a router, no switch hardware in the
path. FDB rows carry `fdb.bridge` because the software bridge reports its
master, unlike a DSA hardware entry — so `derived.bridge` comes from the row
here rather than from a join, and both paths are exercised across the fixture
set.

Also asserts the PVID inference on a software bridge, where untagged arrivals
are equally common.
