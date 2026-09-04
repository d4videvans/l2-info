# Contributing

Read `docs/principles.md` first, then `docs/decisions.md`. The rules there are
enforced mechanically where that is possible, and a change that conflicts with
a settled decision needs that decision superseded in the register — in the same
change — rather than worked around in code.

`CONVENTIONS.md` has the working detail: which document owns which fact, how to
add a field, a reader, a device class or a hint, and the list of mechanical
checks with the principle each one enforces.

## Before opening a pull request

```sh
sh tests/run.sh
```

Everything must pass, including the mechanical checks. With a locally built
ucode rather than a device's:

```sh
UCODE=~/ucode/build/ucode UCODE_LIB=~/ucode/build sh tests/run.sh
```

Node is optional for the development runner and executes the hint, export,
query/filter and diff/scope unit tests. When it is absent the runner reports
those tests unrun rather than passed. CI must provide Node, so these tests are
not optional in automated validation.

Using `sh tests/run.sh` is deliberate even if the executable bit is present in
a git checkout: it also works after zip/archive round-trips which may not
preserve that bit.

## Two things that will get a change sent back

**A fixture that supplies a value without asserting it.** That looks like
coverage and is not — see D43, where a note sat in a fixture input for a whole
release without being checked.

**A new field in the snapshot without a decision record.** The vocabulary is
closed on purpose (D24): sources are extensible, field names are not.

## Contributing hardware coverage

The most useful thing anyone can send is a device this project has never run
on. Coverage cannot grow past the maintainers' own hardware otherwise.

A capture contains real MAC addresses, host names and IP addresses. Read the
redaction section of `docs/fixtures.md` before sending anything, and note that
`.gitignore` deliberately excludes exported snapshots so an unredacted one
cannot be committed by accident.
