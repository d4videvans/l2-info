# sources/rtnl/dsa-switch-fdb

Synthetic, modelled on a 24-port Realtek DSA switch with bridge VLAN
filtering: `lan1` a trunk carrying seven VLANs with no PVID, `lan2`/`lan3`
access ports with PVID 20, and a `switch` conduit interface.

The row shapes are grounded in observed and source-verified DSA/kernel
behaviour, but D47 is important when interpreting them: `NTF_SELF`, master
presence/absence and `fdb.bridge` shape are reported facts, **not portable
hardware/software provenance labels**.

The fixture therefore pins these observable behaviours:

- some FDB rows carry `NTF_SELF` (0x02) and no master/bridge association;
- one address is reported twice with different forwarding-table details,
  including one row with `NTF_MASTER` (0x04);
- protocol multicast rows sit on the conduit interface as self/permanent with
  no VLAN id at all;
- `aa:bb:cc:44:55:66` on `lan2` has no `vlan` key, so the reader preserves that
  absence and the assembler may later resolve a VLAN from the reported PVID.

The original GS1920 investigation motivated looking at separate switch and
bridge reporting paths, but later software-bridge and Filogic-router evidence
showed that the same flag/row shapes are not sufficient to infer origin. In
particular, the Filogic capture produced remote client observations with the
same MAC/port/VLAN both with and without `self`; after D40 merge the `self` flag
remained while `derived.local` correctly stayed false.

The fixture asserts that the reader reports the kernel fields and does not
classify their provenance.
