# discovery/mixed

Not a hardware case: a directory of reader files exercising every way
discovery can reject one, alongside one that is fine.

Every rejection must be *reported with a reason*, never silently dropped: an
installed but unusable reader has to be visible, or a user debugging missing
data has nothing to look at (P9, docs/readers.md §6).
