# l2-info v0.1.0-rc3 — release notes

**Status:** third public pre-upstream test release.

RC3 supersedes RC2 for new testing. It keeps RC2's multi-VLAN comparison fix and makes the public candidate identifiable and internally consistent on the device, including when the copied-checkout installer bypasses the package manager.

## Why RC3 exists

A follow-up consistency review found three release/testing problems rather than a new backend-data defect:

- an unresolved effective VLAN was rendered as *none* in the ordinary results table but as `?` in the Changes table, even though `?` already meant an unreported port elsewhere on the same page;
- RC2 changed only `luci-app-l2-info`, but that package still used normal `luci.mk` revision-derived versioning and a copied-checkout install created no package-manager record, so RC1 and RC2 were not self-identifying on-device;
- the reusable release checklist and README still pointed readers toward RC1 or an unspecified revision rather than the current public candidate.

RC3 closes those gaps without changing snapshot acquisition or the backend data contract.

## What changed

### Consistent unresolved-VLAN presentation

A null effective VLAN is now rendered as translated italic *none* in both the ordinary results table and the Changes table. Mixed move evidence therefore reads, for example, `5, none` rather than reusing `?` for a second meaning.

### On-device release identity

`luci-app-l2-info` now declares explicit package metadata:

- `PKG_VERSION:=0.1.0`
- `PKG_RELEASE:=3`

A conventionally built package therefore identifies itself as `0.1.0-r3` instead of relying on `luci.mk`'s source-revision-derived version.

The LuCI app also ships a small release-identity resource. **Device and data-source details** shows the intended public source-tree identity:

`v0.1.0-rc3`

That remains visible for the documented copied-checkout test install without pretending that an application package is installed. For a real package installation, `apk`/`opkg` remains authoritative for installed package versions.

A mechanical test keeps the public tag, LuCI package metadata, installed release resource, installer/uninstaller manifests and current release documentation in sync.

### Release documentation

The README now points ordinary testers directly at `v0.1.0-rc3` rather than a moving `main` checkout. The practical getting-started guide explains where to find the on-device test identity. The forum-test checklist is genuinely reusable while still naming RC3 as the current public candidate. The roadmap no longer defines its scope by the historical RC1 tag.

## What did not change

RC3 does **not** change:

- `l2-info.snapshot` format/version 1;
- backend package version (`l2-info` remains `0.1.0-r1` because its contents are unchanged by RC3);
- rtnetlink acquisition or reader behaviour;
- raw FDB identity, effective-placement identity or move inference;
- port aggregate semantics;
- install/uninstall behaviour apart from shipping/removing the new LuCI release resource;
- the read-only/no-polling model.

The existing hardware validation therefore remains relevant. RC3's functional change is confined to LuCI presentation and release identification.

## Installation

For ordinary testing, use the tagged RC3 checkout:

```sh
cd /tmp/l2-info
sh tools/install-test.sh
```

Then refresh LuCI and open **Status → MAC & VLAN Lookup**. If an existing LuCI login does not reflect newly installed menu files, log out and back in.

For full installation, uninstall, privacy and troubleshooting guidance, see `docs/getting-started.md`.

## Feedback

Please report new testing against `v0.1.0-rc3`. Include the OpenWrt version, device model/target, exact revision/tag copied, snapshot duration, relevant **Device and data-source details**, and what looked wrong or confusing. The **Test release** row corroborates the intended public candidate but does not replace the revision/tag, because local edits or an untagged checkout can retain the build-time label.
