# devices/dsa-switch-fdb

DSA switch whose driver reports its hardware table. Input is the normalised
output of `sources/rtnl/dsa-switch-fdb`, so this fixture tests the assembler
rather than the parsing: merging, scope rollup, the PVID inference and its
provenance, protocol-address classification, and per-port counts.

The assertions worth reading:

- `aa:bb:cc:44:55:66` arrived untagged, so `derived.vlan` is 20 from the port
  PVID with `vlan_source: "pvid"` — the single permitted inference, marked
- `derived.bridge` on a hardware entry is joined from the port, because the
  kernel does not report it on the row
- protocol multicast rows are classified, not dropped
- `lan1` observes no MACs: a trunk with everything learned on the far side
