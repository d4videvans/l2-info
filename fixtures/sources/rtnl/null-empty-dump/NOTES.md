# Successful null rtnl dump

Synthetic source-contract fixture pinned from live x86/64 OpenWrt 25.12.5
(kernel 6.12.94) evidence and verified against the current ucode-mod-rtnl
implementation.

`rtnl.request()` leaves its multipart result as null when a dump completes
successfully without any valid rows. `rtnl.error()` remains null. The reader
must therefore normalise **null result + no error** to an empty successful dump,
not to `unavailable`.

The live trigger was an IPv4/IPv6 neighbour read on a software bridge with no
neighbour rows. Before the fix, `l2-info` reported `neighbours: unavailable`
with `netlink dump returned no result and no error`; moments later the same
reader returned `ok` when neighbour rows existed.

This fixture deliberately uses the same null-success shape for the AF_BRIDGE
FDB read as well, because the rtnl request semantics are common to every dump.
The FDB collection remains `indeterminate` when the successful dump has zero
rows; neighbours are `ok` with zero rows.
