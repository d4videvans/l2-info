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

## Testing the LuCI view from a copied checkout

The target device does not need git for UI work either. Copy a current checkout
to the device, then install the backend and view directly from that directory:

```sh
cd /tmp/l2-info                  # or wherever the checkout was copied
sh tools/install-dev-backend.sh
sh tools/install-dev-luci.sh
```

`install-dev-luci.sh` copies the view, its helper modules, menu entry and
read-only ACL, then invalidates LuCI's menu/module caches and reloads rpcd. It is
a development helper rather than a package-manager replacement. Refresh LuCI
and open **Status -> MAC & VLAN Lookup** after it completes.

## Two things that will get a change sent back

**A fixture that supplies a value without asserting it.** That looks like
coverage and is not — see D43, where a note sat in a fixture input for a whole
release without being checked.

**A new field in the snapshot without a decision record.** The vocabulary is
closed on purpose (D24): sources are extensible, field names are not.

## Contributing hardware coverage

The most useful thing anyone can send is a device this project has never run
on. Coverage cannot grow past the maintainers' own hardware otherwise.

The target device does **not** need git. Hardware validation is designed for a
copied checkout: download/extract the desired branch elsewhere, copy the whole
directory to the device (WinSCP, scp, removable media, or any equivalent), then
run:

```sh
cd /tmp/l2-info                  # or wherever the checkout was copied
sh tools/install-dev-backend.sh
sh tools/collect-validation.sh
```

The collector writes a timestamped `/tmp/l2-info-validation-*` directory which
can be copied back off the device. It records board metadata, one production
snapshot, a safe rtnetlink bridge/link probe, optional `bridge -j` cross-checks
when available, and `tests/run.sh` output. It needs no Node or jq. If
`sha256sum` is present it records hashes of the copied and installed backend
files, which provides exact source provenance even though there is no `.git`
directory on the target.

A capture contains real MAC addresses, host names and IP addresses. Read the
redaction section of `docs/fixtures.md` before sending or committing anything,
and note that `.gitignore` deliberately excludes exported snapshots so an
unredacted one cannot be committed by accident. Raw validation bundles are for
private analysis; fixtures committed to the repository must satisfy D15.
