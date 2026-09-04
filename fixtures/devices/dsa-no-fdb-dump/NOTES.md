# devices/dsa-no-fdb-dump

DSA switch whose driver does not implement `port_fdb_dump`. Ports and VLANs
read fine; the FDB dump succeeds and returns nothing.

The whole point: this is byte-identical to an idle switch, so the only honest
status is `indeterminate`. Asserts that, asserts a reason is present, and
asserts no boolean capability claim appears anywhere. `mac_count` is 0 for
every port, which is a count of what was seen and not a claim that nothing is
attached.
