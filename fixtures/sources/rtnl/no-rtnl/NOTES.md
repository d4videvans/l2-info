# sources/rtnl/no-rtnl

`ucode-mod-rtnl` is absent from the process, so the reader has no netlink
primitive at all.

Asserts every claimed collection is declared `unavailable` with that reason.
This is the failure the package dependency makes impossible in practice
(docs/readers.md §6) — tested anyway, because a reader must be honest about a
missing primitive rather than assuming its own dependencies.
