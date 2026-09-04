# devices/reader-throws

Two readers: one healthy, one that raises. Not a hardware case.

Asserts that one failing reader cannot take down a snapshot — the healthy
reader's data is present and complete — and that the failure is attributed to
the reader that caused it, with its message, rather than appearing as missing
data of unexplained origin.

Note the FDB collection is still `ok`: the rollup takes the most conclusive
honest answer across readers claiming a collection, and one reader did read
it successfully.
