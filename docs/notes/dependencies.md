# Dependency blockers

After #74 every direct and transitive package in the workspace sits at the
newest version that resolves against the pinned Flutter 3.44.8 / Dart 3.12.2
toolchain — `flutter pub outdated` reports `Current == Upgradable ==
Resolvable` for every row. What remains is the gap to `Latest`, and each of
those gaps has a cause recorded here.

The version columns below are a snapshot, not a source of truth — `pubspec.lock`
is. Nothing checks them, so re-derive from the lockfile and from pub.dev before
acting on any row; the chains move when the SDK does.

## The two chains

Almost everything held back traces to one of two constraints, and both
originate in the Flutter SDK rather than in this repository.

### meta 1.18.0 — blocks the build hooks

`flutter/packages/flutter/pubspec.yaml` and `.../flutter_test/pubspec.yaml`
both pin `meta: 1.18.0` exactly. `hooks` 2.1.0 requires `meta: ^1.19.0`, so
`packages/inferno` holds `hooks` at 2.0.2.

The only change between 2.0.2 and 2.1.0 is graduating
`LinkInput.recordedUses` out of experimental — a link-hook API. Inferno has
no `hook/link.dart`, only `hook/build.dart`, so nothing here consumes it and
the pin costs nothing today.

Clears with: an SDK bump (#38).

### analyzer < 13 — blocks the codegen stack

`flutter_test` pins `test_api: 0.7.11` exactly. That selects `test_core`
0.6.17, whose `analyzer: '>=8.0.0 <13.0.0'` caps `analyzer` at 12.1.0 for the
whole workspace. `test` is in the graph regardless of Riverpod, because
`packages/inferno/pubspec.yaml` declares it directly.

Held back by this, all at their ceiling:

| Package | Held at | Latest | Needs |
| --- | --- | --- | --- |
| `riverpod_generator` | 4.0.4 | 4.0.8 | `analyzer ^13.0.0` |
| `riverpod_annotation` | 4.0.3 | 4.0.6 | forces generator 4.0.8 |
| `flutter_riverpod` / `riverpod` | 3.3.2 | 3.4.2 | pinned by annotation 4.0.3 |
| `build_runner` | 2.15.1 | 2.16.0 | `analyzer >= 13.3.0` |
| `build` | 4.0.7 | 4.0.10 | `analyzer >= 13.3.0` |
| `dart_style` | 3.1.8 | 3.1.12 | 3.1.9+ needs `analyzer ^13.0.0` |
| `mockito` | 5.6.4 | 5.8.1 | 5.8.1 needs `analyzer >= 13.3.0` |
| `analyzer`, `_fe_analyzer_shared` | 12.1.0 / 99.0.0 | 14.1.0 / 105.0.0 | the cap itself |

The Riverpod family is exact-pinned (no caret) because each release
exact-pins the next: annotation 4.0.3 requires riverpod 3.3.2, generator
4.0.4 requires annotation 4.0.3. They move as one set or not at all.

Clears with: an SDK bump (#38).

## Upstream, not the SDK

- **`cli_util`** — held at 0.4.2 by `flutter_launcher_icons` 0.14.4, which
  declares `cli_util: ^0.4.1`. 0.14.4 *is* the latest release, so this clears
  only when upstream widens the constraint, not with #38.
- **`test`** — 1.31.0 rather than 1.31.2, and `test_api` / `test_core` with
  it, because `flutter_test` pins `test_api` exactly. Same origin as the
  analyzer chain.
- **`integration_test`** — ships with the SDK. The pub.dev package of that
  name is discontinued and targets Dart 2, so it is not an upgrade path.

## Transitive consequences, not separate problems

`record_use` (0.6.0 → 1.1.0), `package_config` (2.2.0 → 3.0.0),
`vector_math`, and `matcher` are pulled in by the SDK or by the chains above
and cannot be selected independently. `mockito` is listed in the analyzer
table rather than here: it is unreachable from any source file — it arrives
through `riverpod_generator` — but its gap has the same analyzer cause as the
rest of that table, so it clears with #38 too.

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
