# sources/rtnl/link-identity-mismatch

Synthetic contract fixture for D46.

It represents two link views that cannot both be true at one instant: the
AF_BRIDGE dump says `lan1` is a member of `br-lan`, while the generic link dump
does not identify `br-lan` as a bridge device.

The reader must not recover by promoting the master reference into bridge
identity, because that would recreate the inference D46 removed. It declares
both `bridges` and `ports` unavailable and continues with the independent
collections.

This is a deliberate inconsistency fixture, not a claimed hardware behavior.
