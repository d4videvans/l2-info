# sources/rtnl/fdb-empty

The dump succeeds and returns nothing. This is the case P4 exists for: an idle
bridge and a DSA driver that does not implement `port_fdb_dump` produce
byte-identical evidence, so the only honest status is `indeterminate` — not
`ok` with zero rows, and not `unavailable`.

Asserts the reader says exactly that, and makes no capability claim either way.
