# Contributing

For simply trying the project on an OpenWrt device, start with
[`docs/getting-started.md`](docs/getting-started.md). This document is for code,
documentation and hardware-evidence contributions.

Read `docs/principles.md` and the current `docs/decisions.md` before changing
behaviour. `CONVENTIONS.md` maps the design rules to working practices and
mechanical checks. The original long-form decision history remains in
`docs/decisions-history.md`.

## Before opening a pull request

Run:

```sh
sh tests/run.sh
```

Everything available locally must pass. With a locally built ucode:

```sh
UCODE=~/ucode/build/ucode UCODE_LIB=~/ucode/build sh tests/run.sh
```

Node is optional in the local/device runner. When absent, browser-side
hint/export/query/diff tests are explicitly reported as skipped rather than
passed. CI always supplies Node and makes those tests mandatory.

Using `sh tests/run.sh` is intentional: copied/archive checkouts do not need to
preserve executable bits.

Repository CI additionally validates fixture JSON, runs current LuCI
ESLint/i18n/POT checks and builds both intended packages in the official OpenWrt
SDK. Green CI is integration evidence; it is not a substitute for testing an
unseen physical driver.

## Testing a checkout on OpenWrt

The friendly tester path installs backend and (when LuCI is present) the view:

```sh
cd /tmp/l2-info
sh tools/install-test.sh
```

Remove it with:

```sh
sh tools/uninstall-test.sh
```

For focused development the lower-level helpers remain available:

```sh
sh tools/install-dev-backend.sh
sh tools/install-dev-luci.sh
```

The scripts are copied-checkout helpers, not package-manager replacements. The
backend helper verifies runtime ucode modules before copying anything and
reloads rpcd in the safe core-before-reader order.

## Two common mistakes

### Supplying fixture data without asserting it

If a fixture deliberately contains a value, its expectation should normally
assert the consequential contract. Otherwise the input only looks like
coverage. D43 was found this way when a reader note existed in fixture input but
was not asserted.

### Adding vocabulary locally

Sources are extensible; the snapshot vocabulary is not. A new collection,
subject kind, attribute or non-existing derived value is a format/design change
first (`docs/snapshot-format.md` + decision), then code.

## Contributing hardware coverage

Hardware outside the existing validation matrix is especially useful.

The target does not need git. Copy a checkout to the device, install it, then
collect one read-only evidence bundle:

```sh
cd /tmp/l2-info
sh tools/install-test.sh
sh tools/collect-validation.sh
```

The collector records board metadata, runtime-module checks, one production
snapshot, a safe rtnetlink link probe, optional `bridge -j` cross-checks, hashes
and the repository test output.

**Its output is raw.** It may contain real MAC addresses, IP addresses and
hostnames. Do not post the bundle publicly or commit it as a fixture. Read
`docs/fixtures.md` and `docs/getting-started.md` first; begin a public report
with device/target/kernel, exact revision/tag, snapshot duration and the
collection/reader status summary.

D21's proposed redacted capture helper does not exist yet.

## Adding a reader

Follow `docs/readers.md` exactly. In particular:

- readers are trusted installed package code, not sandboxed plugins;
- `read(ctx)` uses the supplied source primitives so fixture replay stays total;
- rows emit only registered `subject` + `attrs`;
- assembler owns `derived` and `source`;
- manifest `provides`, status return and package dependencies must agree;
- at least one source fixture is mandatory.

A new reader should not require a reader-id branch in the core.

## Documentation changes

`CONVENTIONS.md` owns the documentation map. If implementation changes a settled
fact, update the owning document in the same change rather than adding a second
contradictory description elsewhere.

User-facing installation/behaviour belongs in `docs/getting-started.md`; deep
rationale belongs in the decision/history documents.
