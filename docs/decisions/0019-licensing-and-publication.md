# ADR 0019: Licensing, publication, and the restored CI

- Status: accepted
- Date: 2026-09-05
- Issue: #12

## Context

The repository was private with no license file and its one workflow, `CI`,
disabled since 2026-08-05 (#31): on the org's free plan, private-repo macOS
minutes bill at 10× against 2,000 included minutes with a $0 spending limit,
and a single Apple job consumed ~150 of them. Going public restores
unmetered standard runners, but a public repository with no license is
"all rights reserved" in a tree whose app already tells users, in fourteen
locales, that Golem is open source. Before the flip the owner had to decide
what the license is, what it does not cover, what a contribution grants,
and what a store binary's terms rest on — and the tree and its history had
to be reviewed for anything that must not be published.

## Decisions

### First-party code is AGPL-3.0-only

Everything the repository authors — the Flutter app, Inferno, the tooling
under `tool/`, the documentation — is licensed under the GNU Affero General
Public License version 3 **only**. The copyright holder is Jan Slominski.
The verbatim license text sits at the repository root and again in
`packages/inferno/`, because pub tooling and anyone vendoring the package
read a package's own `LICENSE`; `legal_surfaces_test.dart` holds the two
files identical. Notices live in the three READMEs and the macOS
`PRODUCT_COPYRIGHT` string (which had named a bundle id as the owner, with
"All rights reserved" after it). There are no per-file headers: the
repository's convention is that a comment states what the code cannot, and
a two-line header on several hundred files would state what the root
`LICENSE` already does.

"Only" rather than "or any later version": a later AGPL is a license nobody
has read yet, and the holder can adopt one deliberately when it exists.
Strong copyleft is the point — a derived work distributed to others, or run
for others over a network (§13), owes its source under the same terms —
while commercial use, forks, and redistribution that comply remain
permitted.

### The app names its license

The About sheet ends with an `AGPL-3.0-only` line that opens the source
repository. It is an SPDX identifier and a host name, so it is not a catalog
string. The Open-source licenses screen stays what ADR 0009 made it — a
disclosure of the third-party software Golem chose — and does not list the
app itself; the in-app notice is the About line, and the full text is the
repository's.

### Brand assets are reserved

The Golem name, the mascot, and every launcher, Dock, splash, and in-app
identity artwork derived from it are copyright Jan Slominski, all rights
reserved, and are **not** part of the AGPL grant. `TRADEMARKS.md` lists the
paths, what anyone may do with them (build, run, modify, test, contribute,
refer to Golem truthfully) and what needs written permission (distribute a
modified version under the name or with the artwork, or use either as
another product's identity). A fork that ships renames and replaces the
artwork; `platform_assets_test.dart` pins today's artwork, so that rebrand
is a visible change, not an accident. The record says nothing about how the
artwork was made, only who holds it.

### Contributions arrive under a CLA with a relicensing grant

`CLA.md` grants the steward a perpetual, irrevocable, sublicensable
copyright and patent license to distribute a contribution **under any
terms**, and commits the steward to also releasing every accepted
contribution under the project's public license. The contributor keeps
ownership. Acceptance is the statement in the pull request template, and
the pull request is the record; there is no bot, and a bot would be a
convenience over this text, not a substitute for it. The grant is what
preserves the ability to offer the code under other terms — the store terms
below, or another license later — once code the holder did not write is in
the tree. Contributions under the AGPL alone would end that ability with
the first merged patch.

### Store binaries rest on the holder's own rights, not on the AGPL

The FSF's GPL FAQ states the rule: the developer of a GPL-covered program is
not bound by the license they grant to others. The App Store and Google
Play binaries are therefore distributed by the copyright holder under the
stores' terms, and the AGPL is the license the public receives for the
source. This holds only while two conditions do:

1. **Every third-party component in the binary is permissively licensed.**
   The FSF's App Store enforcement (GNU Go, 2010) turned on a third party's
   GPL code inside the store binary; a copyleft dependency or a copyleft
   snippet would put Golem in that position. The review below finds none.
2. **Every contribution arrives under `CLA.md`.** A merged contribution
   under the AGPL alone would be third-party copyleft code in the binary.

A future copyleft dependency, or a contribution accepted without the CLA,
reverses this decision for the store builds, not the license alone.

AGPL §13 attaches to a modified version that users interact with over a
network. Golem performs no network interaction on the user's behalf beyond
fetching model files the user asked for; the clause is inert for the app as
shipped and binds only someone who runs a modified Golem as a service.

### Dependency review

Every locked package and every declared native upstream was classified on
2026-09-05 against `pubspec.lock` and `native/apple/Package.resolved`:

| Class | Count | Kinds |
| --- | ---: | --- |
| pub packages in the workspace lockfile | 159 | BSD-3-Clause 124 · MIT 20 · Apache-2.0 7 · SDK-vendored (BSD-3) 8 |
| llama.cpp graph (ADR 0009) | 4 | MIT · MIT · `MIT OR Unlicense` · `Unlicense OR MIT-0` |
| MLX Swift graph (ADR 0009) | 16 | MIT 4 · Apache-2.0 6 · `Apache-2.0 WITH Swift-exception` 6 |

No GPL, LGPL, MPL, CC-BY-SA, proprietary, or unlicensed component. Apache-2.0
is one-way compatible: Apache-licensed code may be included in an AGPLv3
work (the ASF's own statement), and the AGPL is the license of the combined
work. `image` (dev dependency, launcher generation only) carries a second
notice file for its ported JPEG and WebP codecs, Apache-2.0 and BSD-3; it
does not reach a shipping binary. Model weights are not part of the review:
they are downloaded after consent and never redistributed (ADR 0009).

### Publication review

Reviewed before the flip: the tracked tree (791 files), every commit
reachable from `main` and from the 72 `refs/pull/*/head` refs on origin
(583 commits), and every blob in the object store. No Team ID, device
identifier, serial, LAN address, token, keystore, provisioning profile,
`.env`, or developer home path; commit identities use the GitHub noreply
form. The pairing-identity file and the `references/` handoff material
were never committed. The largest blob is a 1.12 MB app icon. The Team ID
is also absent from every issue and pull-request comment, which become
public with the repository.

One finding: the long benchmark fixture quoted a third-party README
verbatim (a public Apache-2.0 project) without attribution. It was replaced
with an original document of the same length band, which is all the
deterministic benchmark reads from it. The earlier revisions stay in
history; Apache-2.0 permits that redistribution, and the attribution it
asks for is the one this record and the replacement now make moot.

Two facts of the flip are recorded rather than fixed: the pull-request refs
already on origin become fetchable, so a future purge could not stop at
`main`; and `app/README.md` no longer points at the maintainer-held design
handoff, which stays outside the repository.

### CI: public, enabled, and building the QA macOS app

Standard GitHub-hosted runners, macOS included, are free for public
repositories; larger runners are not, and `ci.yml` uses none. The workflow
is re-enabled unchanged except for one step at the end of the Apple job:

```yaml
- name: QA macOS app build (runs the Inferno hooks and the resource-staging phase)
  run: flutter build macos --debug --flavor qa
  working-directory: app
```

What the step proves that `flutter test` and `dart test` do not: the
Runner target itself assembles — scheme `qa`, configuration `Debug-qa`,
ad-hoc signing, no team — and its last build phase, "Stage Inferno Apple
Resources", finds the bundles the hook wrote under
`packages/inferno/build/apple-resources/macosx/` and copies them into the
app. The phase is unconditional and hard-fails, so a hook that stopped
producing resources for arm64 macOS would fail this step and nothing
earlier. The `qa` flavor does not skip the hook: the hook's only gate is
that code assets are being built, and native assets are on by default on
the pinned stable SDK — three documents said otherwise and were corrected
with this change.

The step follows the engine checks, as the ticket asks. It costs one
llama.cpp recompile there: `dart test` in `packages/inferno` builds for
macOS deployment target 12 and `flutter build macos` for 13, in one CMake
directory whose key omits the version. Placing the step directly after the
app suite would have shared that build; the ticket's order is kept and the
minute is recorded rather than optimized away.

Timing on this Mac (Apple silicon, Xcode 26.6, warm hook cache):
`flutter build macos --debug --flavor qa` — 47 s wall clock, the
three Inferno bundles (`mlx-swift_Cmlx`, `swift-transformers_Hub`,
`swift-crypto_Crypto`) staged beside the plugin bundles in
`golem_flutter.app/Contents/Resources/`, bundle `app.golem.qa` "Golem QA",
ad-hoc signature, no team identifier.

Hosted timing is recorded in the pull request for #12 from its first
`pull_request` run (macos-26-arm64, Xcode 26.6). The Apple job's
`timeout-minutes: 60` stands; the previous runs (3.44.8 era) took
12–15 minutes and the new step was estimated at 2–5.

Sequencing: the workflow was enabled while the repository was still private
for one `pull_request` run — included minutes, a $0 limit that cannot bill
— then the repository was made public after the pull request merged, with
the workflow left enabled.

## Consequences

- A new dependency is classified before it is added; anything not
  permissive reopens the store-binary decision above.
- A contribution is not merged without the CLA statement in its pull
  request.
- Brand assets change only through the owner; a rebrand is a fork's job.
- ADR 0001's "requires `flutter config --enable-native-assets`" is
  superseded by the SDK default; the note there says so.
- The ADR 0009 disclosure screen is unchanged: the app's own license is a
  README and About matter, not a third-party notice.
- This record documents engineering evidence and distribution handling; it
  is not legal advice.

## Sources reviewed

- GNU AGPL v3 text: <https://www.gnu.org/licenses/agpl-3.0.txt>
- FSF GPL FAQ, "Is the developer of a GPL-covered program bound by the
  GPL?": <https://www.gnu.org/licenses/gpl-faq.en.html#DeveloperViolate>
- FSF, "More about the App Store GPL Enforcement" (2010):
  <https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement>
- ASF, Apache License v2.0 and GPL compatibility:
  <https://www.apache.org/licenses/GPL-compatibility.html>
- GitHub, about billing for GitHub Actions (standard runners free in public
  repositories):
  <https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions>
- GitHub, setting repository visibility:
  <https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility>
- GitHub runner image `macos-26-arm64` README (Xcode 26.6 default):
  <https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md>
- Flutter flavors on iOS and macOS:
  <https://docs.flutter.dev/deployment/flavors-ios>
