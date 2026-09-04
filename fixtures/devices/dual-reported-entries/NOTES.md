# devices/dual-reported-entries

From a live GS1920-24 v1 cross-checked against `bridge fdb show` on the same
device. Not a hardware class: the case that cross-check exposed.

On this switch an access-port host is reported **twice, differently**:

```
aa:5d:64:54:e0:15 dev lan2 vlan 5 master switch
aa:5d:64:54:e0:15 dev lan2 self
```

The software bridge carries the VLAN id; the hardware entry has none. That is
the reverse of the assumption behind the original design, which expected the
hardware table to be the VLAN-bearing source.

So the two rows differ in `fdb.vlan` and remain two observations (D42). On a
port with a PVID the second resolves to the same VLAN by inference, which is
why the fixture asserts one entity with `vlan_source: "fdb"` and one with
`"pvid"` — visibly the same host reported two ways, rather than silently
collapsed into one on the strength of a guess.

`lan24` shows the other half: a trunk with no PVID, where a hardware entry
without a VLAN id resolves to nothing at all, and correctly stays `null`.
