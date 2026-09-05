# devices/dual-reported-entries

From a live GS1920-24 v1 cross-checked against `bridge fdb show` on the same
device. Not a hardware class: the case that cross-check exposed.

On that switch an access-port host was reported **twice, differently**:

```
aa:5d:64:54:e0:15 dev lan2 vlan 5 master switch
aa:5d:64:54:e0:15 dev lan2 self
```

The two raw rows differ in `fdb.vlan` and remain two observations (D42). On a
port with a PVID the second resolves to the same VLAN by inference, which is
why the fixture asserts one entity with `vlan_source: "fdb"` and one with
`"pvid"` — visibly the same address reported two ways, rather than silently
collapsed into one on the strength of a guess.

D47 narrows the interpretation of this shape. On the GS1920, the device/driver
context motivated investigating distinct switch and bridge reporting paths;
but x86 software-only bridge validation later proved that `self` plus no
`fdb.bridge` is **not portable evidence of hardware provenance**. This fixture
therefore pins the duplicate observations and their differing fields, not a
general hardware/software classification.

`lan24` shows the other half: a trunk with no PVID, where a row without a VLAN
id resolves to nothing at all and correctly stays `null`.
