# sources/rtnl/nl-error

The FDB dump fails at the netlink layer while the link dump succeeds.

Asserts the two are reported independently, and that a failed read is
`unavailable` with the kernel's own message rather than an empty table — the
distinction the single read seam exists to preserve (D18).
