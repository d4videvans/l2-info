# devices/reader-conflict

Two readers that disagree about a port's PVID, and agree about everything
else. Not a hardware case.

Asserts the behaviour D27 specifies: neither value wins. The disputed
attribute is *withdrawn* from `attrs` so nothing can silently read a winner,
every claim is recorded on the entity's `disputed` map, and a `conflicts`
entry names the subject, the attribute and the readers.

It also asserts what follows downstream: with no agreed PVID, the untagged
arrival on that port has no VLAN to resolve against, so `derived.vlan` is
null rather than a coin toss. A conflict propagates as absence, not as a
guess.

The agreeing attribute (`topo.bridge`) keeps its value and records both
sources, which is the other half of the merge rule.
