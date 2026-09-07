from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one occurrence, found {count}: {old!r}")
    p.write_text(text.replace(old, new, 1))


main = 'luci-app-l2-info/htdocs/luci-static/resources/view/l2-info/main.js'
replace_once(main,
             "'require l2-info.diff as compare';\n",
             "'require l2-info.diff as compare';\n'require l2-info.release as release';\n")
replace_once(main,
             "out.push(v == null ? el('em', {}, '?') : String(v));",
             "out.push(v == null ? el('em', {}, _('none')) : String(v));")
replace_once(main,
             "\tvar rows = [\n\t\t[ _('Device metadata'),",
             "\tvar rows = [\n\t\t[ _('Test release'), release.tag + ' · luci-app-l2-info ' + release.packageVersion ],\n\t\t[ _('Device metadata'),")

Path('luci-app-l2-info/htdocs/luci-static/resources/l2-info/release.js').write_text(
"""/* SPDX-License-Identifier: Apache-2.0 */
/* Public pre-upstream test identity. Keep packageVersion in sync with the
 * LuCI Makefile; tests/run.sh enforces that relationship and the public docs. */

'use strict';

return {
\ttag: 'v0.1.0-rc3',
\tpackageVersion: '0.1.0-r3'
};
""")

replace_once('luci-app-l2-info/Makefile',
             "LUCI_DEPENDS:=+luci-base +l2-info\n\nPKG_LICENSE:=Apache-2.0",
             "LUCI_DEPENDS:=+luci-base +l2-info\n\n# Public test candidates can differ only in LuCI code. Use explicit package\n# metadata so an installed LuCI package identifies the candidate instead of\n# relying on luci.mk's source-revision-derived version.\nPKG_VERSION:=0.1.0\nPKG_RELEASE:=3\n\nPKG_LICENSE:=Apache-2.0")

replace_once('tools/install-dev-luci.sh',
             "htdocs/luci-static/resources/l2-info/diff.js:/www/luci-static/resources/l2-info/diff.js\n",
             "htdocs/luci-static/resources/l2-info/diff.js:/www/luci-static/resources/l2-info/diff.js\nhtdocs/luci-static/resources/l2-info/release.js:/www/luci-static/resources/l2-info/release.js\n")
replace_once('tools/uninstall-test.sh',
             "/www/luci-static/resources/l2-info/diff.js\n",
             "/www/luci-static/resources/l2-info/diff.js\n/www/luci-static/resources/l2-info/release.js\n")

marker = "\t# Demo rewrites share one authoritative precondition checker with install.\n"
check_block = r'''\t# Public test-release identity: copied-checkout installs bypass the package
\t# manager, so the LuCI page carries the tag as well as the package version.
\t# Keep that identity, package metadata, installer manifests and current docs
\t# in sync so bug reports can name the build actually running.
\tRELEASE_JS="$VIEW/htdocs/luci-static/resources/l2-info/release.js"
\trelease_tag=$(sed -n "s/^[[:space:]]*tag: '\\([^']*\\)'.*/\\1/p" "$RELEASE_JS")
\trelease_pkg=$(sed -n "s/^[[:space:]]*packageVersion: '\\([^']*\\)'.*/\\1/p" "$RELEASE_JS")
\tpkg_version=$(sed -n 's/^PKG_VERSION:=//p' "$VIEW/Makefile")
\tpkg_release=$(sed -n 's/^PKG_RELEASE:=//p' "$VIEW/Makefile")
\texpected_pkg="${pkg_version}-r${pkg_release}"
\trelease_status=1
\tif [ -n "$release_tag" ] && [ "$release_pkg" = "$expected_pkg" ] && \\
\t   grep -Fq "'require l2-info.release as release';" "$VIEW/htdocs/luci-static/resources/view/l2-info/main.js" && \\
\t   grep -Fq "_('Test release')" "$VIEW/htdocs/luci-static/resources/view/l2-info/main.js" && \\
\t   grep -Fq "$release_tag" "$ROOT/README.md" && \\
\t   grep -Fq "$release_tag" "$ROOT/docs/release-checklist.md" && \\
\t   [ -f "$ROOT/docs/release-notes-${release_tag}.md" ] && \\
\t   grep -Fq "release.js:/www/luci-static/resources/l2-info/release.js" "$ROOT/tools/install-dev-luci.sh" && \\
\t   grep -Fq "/www/luci-static/resources/l2-info/release.js" "$ROOT/tools/uninstall-test.sh"; then
\t\trelease_status=0
\tfi
\tcheck "release: public test identity is internally consistent" "$release_status"

'''
replace_once('tests/run.sh', marker, check_block + marker)

replace_once('CONVENTIONS.md',
             "- committed fixture MACs are synthetic/permitted constants;\n- browser hint/export/query/diff tests when Node is available.",
             "- committed fixture MACs are synthetic/permitted constants;\n- public test-release identity, LuCI package metadata and installer/docs references stay in sync;\n- browser hint/export/query/diff tests when Node is available.")

replace_once('README.md',
             "> not yet been submitted to the OpenWrt package feeds. The installation method\n> below is therefore a reversible test install from this repository.\n",
             "> not yet been submitted to the OpenWrt package feeds. The installation method\n> below is therefore a reversible test install from this repository.\n>\n> **Current public test release:** [`v0.1.0-rc3`](https://github.com/d4videvans/l2-info/releases/tag/v0.1.0-rc3).\n> Use that tag for ordinary testing; `main` may move ahead during development.\n")
replace_once('README.md',
             "Git is **not** required on the OpenWrt device. Download or clone the revision\nyou want to test on another machine, copy the whole checkout to the router\n(for example as `/tmp/l2-info` with `scp` or WinSCP), then run:\n",
             "Git is **not** required on the OpenWrt device. For ordinary public testing,\ndownload or clone the current `v0.1.0-rc3` tag on another machine rather than\nan untagged `main` checkout, copy the whole checkout to the router (for example\nas `/tmp/l2-info` with `scp` or WinSCP), then run:\n")
replace_once('README.md',
             "For an ordinary bug or confusing result, include the OpenWrt version, device\nmodel/target, the exact revision or tag tested, and what the **Device and\ndata-source details** panel says.\n",
             "For an ordinary bug or confusing result, include the OpenWrt version, device\nmodel/target, and what the **Device and data-source details** panel says. On\nRC3 and later that panel includes the public test-release identity and LuCI\npackage version; for a headless/backend-only test, include the exact revision or\ntag copied instead.\n")

replace_once('docs/getting-started.md',
             "The test install copies the same backend and LuCI files that potential future\npackages will contain, but it bypasses the package manager. It is intended for\nevaluation and hardware testing, not as the permanent distribution mechanism.\n",
             "The test install copies the same backend and LuCI files that potential future\npackages will contain, but it bypasses the package manager. It is intended for\nevaluation and hardware testing, not as the permanent distribution mechanism.\n\nThe current public test release is `v0.1.0-rc3`. For ordinary testing, use that\ntag rather than an untagged `main` checkout so the code and reported release\nidentity are reproducible.\n")
replace_once('docs/getting-started.md',
             "The age shown beside the snapshot continues to increase, but that timer does\nnot poll or refresh the device.\n",
             "The age shown beside the snapshot continues to increase, but that timer does\nnot poll or refresh the device.\n\nUnder **Device and data-source details**, the page also shows the public test\nrelease and LuCI package version (for RC3: `v0.1.0-rc3 · luci-app-l2-info\n0.1.0-r3`). That identity is shipped as a LuCI resource, so it remains visible\neven when `tools/install-test.sh` copied the checkout directly and no package\nmanager record exists.\n")
replace_once('docs/getting-started.md',
             "- exact `l2-info` revision or tag tested;\n",
             "- the **Test release** line shown under **Device and data-source details**, or\n  the exact revision/tag copied for a headless/backend-only test;\n")

old_top = """# Forum test release checklist

This is the repository-side checklist for the first public **pre-upstream test
release** of `l2-info`. It is deliberately not forum-post copy.

**RC1 status:** published. This file is retained as a reusable process checklist;
unchecked boxes are procedure prompts, not a live claim that RC1 is unfinished.
The published `v0.1.0-rc1` tag is treated as the immutable source identity for
that release. Documentation-only corrections may land on `main` afterwards
without moving the tag.
"""
new_top = """# Forum test release checklist

This is the repository-side reusable checklist for public **pre-upstream test
releases** of `l2-info`. It is deliberately not forum-post copy.

**Current public test release:** `v0.1.0-rc3`. RC1 and RC2 remain immutable
historical candidates; RC3 supersedes them for new testing. Unchecked boxes are
procedure prompts, not a live claim that the current release is unfinished.
Once published, each release tag is the immutable source identity for that
candidate. Documentation-only corrections may land on `main` afterwards without
moving an existing tag.
"""
replace_once('docs/release-checklist.md', old_top, new_top)
replace_once('docs/release-checklist.md',
             "- [ ] Tag that exact commit as the release candidate (`v0.1.0-rc1`).\n",
             "- [ ] Tag that exact commit with the chosen release-candidate tag.\n")
replace_once('docs/release-checklist.md',
             "- [ ] Use `docs/release-notes-v0.1.0-rc1.md` as the factual basis for any GitHub\n  release notes or announcement text.\n",
             "- [ ] Use the release-notes file named for that tag as the factual basis for any\n  GitHub release notes or announcement text (current: `docs/release-notes-v0.1.0-rc3.md`).\n")

replace_once('docs/roadmap.md',
             "This roadmap records ideas that are useful enough to preserve but are **not part of the v0.1.0-rc1 scope**.",
             "This roadmap records ideas that are useful enough to preserve but are **not part of the current pre-upstream v0.1.0 release-candidate scope**.")
