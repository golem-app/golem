# Dependency blockers

After #74 every direct and transitive package in the workspace sat at the
newest version that resolved against the then-pinned Flutter 3.44.9 / Dart
3.12.2 toolchain. #143 moved the pin to Flutter 3.47.1 / Dart 3.13.1 with
`pub get` alone, so the lockfile moved only where the SDK forced it; #154
re-derived every row below from that lockfile and `flutter pub outdated` on
2026-08-23. What remains is the gap to `Latest`, and each gap has a cause
recorded here.

The version columns are a snapshot, not a source of truth — `pubspec.lock` is.
Nothing checks them, so re-derive from the lockfile and from pub.dev before
acting on any row; the chains move when the SDK does.

## The two chains

Almost everything held back traces to one of two constraints. One originates
in the Flutter SDK; the other is this repository's own choice.

### meta — clear; `hooks` is now held by its own exact pin

Flutter 3.44.9 pinned `meta: 1.18.0` exactly, and `hooks` 2.1.0 requires
`meta: ^1.19.0`, so `packages/inferno` held `hooks` at 2.0.2. The SDK now
ships `meta` 1.19.0 and the constraint is gone; `hooks` stays at 2.0.2
because `packages/inferno/pubspec.yaml` pins it exactly (the build hook's
API is the package's contract), and `code_assets` 2.0.0 is a major bump
behind it. Nothing between 2.0.2 and 2.2.0 is consumed here — Inferno has no
`hook/link.dart` — so the pin costs nothing today.

Clears with: a reviewed bump of both pins together, with the hook rebuilt on
every shipped architecture.

### analyzer < 14 — caps the codegen stack, but no longer blocks it

`flutter_test` pins `test_api: 0.7.12` exactly. That selects `test_core`
0.6.18, whose `analyzer: '>=8.0.0 <14.0.0'` caps `analyzer` at 13.3.0 for the
whole workspace. The lockfile still holds 12.1.0, and with it everything that
wants a newer analyzer — because #143 ran `pub get`, never `pub upgrade`:

| Package | Locked | Resolvable now | Latest | Latest needs |
| --- | --- | --- | --- | --- |
| `riverpod_generator` | 4.0.4 | 4.0.8 | 4.0.8 | `analyzer ^13.0.0` |
| `riverpod_annotation` | 4.0.3 | 4.0.6 | 4.0.6 | generator 4.0.8 |
| `flutter_riverpod` / `riverpod` | 3.3.2 | 3.4.2 | 3.4.2 | annotation 4.0.6 |
| `build_runner` | 2.15.1 | 2.16.0 | 2.16.0 | `analyzer >= 13.3.0` |
| `build` | 4.0.7 | 4.0.10 | 4.0.10 | `analyzer >= 13.3.0` |
| `dart_style` | 3.1.8 | 3.1.12 | 3.1.12 | `analyzer >= 13.1.0` |
| `mockito` | 5.6.4 | 5.8.1 | 5.8.1 | `analyzer >= 13.3.0` |
| `analyzer`, `_fe_analyzer_shared` | 12.1.0 / 99.0.0 | 13.3.0 / 103.0.0 | 14.1.0 / 105.0.0 | `test_core` 0.6.19 (`test_api` 0.7.13) |

So the whole table is one reviewed `pub upgrade` away from its resolvable
column; only the last row's `Latest` waits on the SDK. The Riverpod family is
exact-pinned (no caret) because each release exact-pins the next: annotation
4.0.3 requires riverpod 3.3.2, generator 4.0.4 requires annotation 4.0.3. They
move as one set or not at all, and the generated `.g.dart` must be
byte-identical or explained after they do.

Clears with: the next reviewed `pub upgrade` (the table), then the next SDK
bump (the analyzer ceiling itself).

## Upstream, not the SDK

- **`cli_util`** — held at 0.4.2 by `flutter_launcher_icons` 0.14.4, which
  declares `cli_util: ^0.4.1`. 0.14.4 *is* the latest release, so this clears
  only when upstream widens the constraint, not with any SDK bump.
- **`test`** — 1.31.1 rather than 1.31.2, and `test_api` / `test_core` with
  it, because `flutter_test` pins `test_api` exactly. Same origin as the
  analyzer chain.
- **`integration_test`** — ships with the SDK. The pub.dev package of that
  name is discontinued and targets Dart 2, so it is not an upgrade path.

## Transitive consequences, not separate problems

`record_use` (0.6.0 → 1.1.1), `package_config` (2.2.0 → 3.0.0),
`vector_math`, and `matcher` are pulled in by the SDK or by the chains above
and cannot be selected independently. `mockito` is listed in the analyzer
table rather than here: it is unreachable from any source file — it arrives
through `riverpod_generator` — but its gap has the same analyzer cause as the
rest of that table, so it clears with the same upgrade.

## Removed in #74

- **`native_toolchain_c`** — declared in `packages/inferno` but never
  imported; `hook/build.dart` drives the compilers itself.
- **`flutter_localizations`** (and `intl` with it) — removed while the app was
  English-only, then deliberately restored by #71 for generated English and
  Polish catalogs, framework delegates, locale resolution, plurals, and
  locale-aware formatting. Product widgets remain Cupertino-only.

## What is deliberately not removed

`background_downloader`, `markdown`, `highlight`, `go_router`,
`flutter_riverpod`, `crypto`, and the `flutter.dev` plugins are all
load-bearing, and #74 explicitly rejects replacing mature routing, state
management, native plugin, cryptography, or build-hook behavior with
hand-written code to reduce the package count.
