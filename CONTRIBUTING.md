# Contributing to Golem

Golem is a Flutter app (`app/`) and an on-device inference package
(`packages/inferno/`) in one pub workspace. The two READMEs describe how the
pieces fit; this file is only about how a change reaches `main`.

## Before you start

- Open or find an issue first for anything beyond a typo. The maintainer
  triages issues on the GOLEM.app project board; a pull request without an
  agreed issue may be closed unread.
- Contributions are accepted under the [Contributor License
  Agreement](CLA.md). Read it once; the pull request template records your
  acceptance.
- The Golem name and artwork are reserved ([`TRADEMARKS.md`](TRADEMARKS.md));
  do not submit changes to the brand assets unless an issue asks for them.

## Toolchain

The Flutter SDK is pinned in `.fvmrc` and read by `fvm`; every command in
the READMEs assumes it (`fvm install`, then `fvm flutter …` / `fvm dart …`,
or put `.fvm/flutter_sdk/bin` on `PATH`). Every build runs Inferno's native
build hooks, which need CMake and, on Apple hosts, Xcode; Android needs the
NDK revision named in `app/README.md`.

## The gate

A pull request is ready when the whole local gate is green. From the repo
root:

```sh
(cd app && fvm flutter pub get && fvm dart run build_runner build)
fvm dart format --output=none --set-exit-if-changed .
fvm dart run tool/check_inferno_imports.dart
fvm dart run tool/check_feature_imports.dart
fvm dart run tool/check_toolchain.dart
(cd app && fvm flutter analyze && fvm flutter test)      # goldens compare on macOS
(cd packages/inferno && fvm dart analyze && fvm dart test)
```

CI (`.github/workflows/ci.yml`) runs the same checks minus `build_runner`,
whose output is committed, and adds what a laptop rarely repeats: the
Inferno native suites against fetched toy fixtures, and
`flutter build macos --debug --flavor qa` on the Apple job. A change to the
Inferno hook or to the Apple resource-staging phase is worth running that
build locally too (`app/README.md`, "macOS verification").

Goldens are rendered on macOS at the iPhone 17 viewport; regenerate with
`--update-goldens` only on macOS, only for a deliberate visual change, and
review the diff. Anything that touches native inference, downloads, or
platform surfaces is verified on a device, and the pull request says which.

## Branches, commits, pull requests

- Branch from an up-to-date `main` as `<type>/<issue>-<slug>`
  (`feat/12-model-catalog`).
- Commit messages follow Conventional Commits with an optional scope:
  `feat: …`, `fix(app): …`, `chore(ci): …`, `docs: …`, `refactor: …`,
  `test: …`. The subject says what changed; the body says why. Commits
  carry their author only — no tool or assistant attribution trailers.
- One pull request per issue, against `main`, with `Closes #<n>`, a short
  summary of behaviour, and the verification you actually ran (test counts,
  golden changes, device results). Keep the description stable once review
  starts; answer feedback with new commits and review replies, and never
  force-push a reviewed branch.
- Prefer extending the test file that owns a surface over adding a new one;
  `app/README.md` ("What earns a test") explains the bar.

## Reporting a security problem

See [`SECURITY.md`](SECURITY.md). Do not open a public issue for a
vulnerability.
