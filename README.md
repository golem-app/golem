# Golem (Flutter)

High-fidelity Flutter implementation of Golem. The repository is a pub
workspace with two members:

- [`app/`](app/) — the Flutter application. The `qa` flavor and test
  builds are fully deterministic simulations; `production` and `dev`
  default to real on-device inference with pinned, verified model
  downloads. The app ships no model weights.
- [`packages/inferno/`](packages/inferno/) — the on-device inference
  package: a pure Dart FFI boundary over llama.cpp and MLX Swift shims.
  See [`docs/architecture/inferno.md`](docs/architecture/inferno.md) and
  the decision notes in [`docs/decisions/`](docs/decisions/).

Only [`app/lib/broker/`](app/lib/broker/) may import `package:inferno`;
`tool/check_inferno_imports.dart` enforces that boundary in CI, and
`tool/check_feature_imports.dart` enforces the app's own feature-import
direction ([ADR 0015](docs/decisions/0015-feature-layering.md)). The broker
owns Gemma chat templating, reasoning-tag parsing, and stop-token policy —
engines receive fully rendered prompts and emit raw text.

The app ships as three coexisting phone flavors — `production` (**Golem**,
`app.golem`, blue icon), `qa` (**Golem QA**, `app.golem.qa`, grey icon), and
`dev` (**Golem Dev**, `app.golem.dev`, green icon) — selected with
`--flavor` (plain commands default to `dev`). QA is the canonical flavor
for automated testing; see [`app/README.md`](app/README.md). The same
flavors exist on iOS, Android, and the macOS desktop target, which opens
as an iPad-shaped resizable window, runs both real engines GPU-accelerated
(llama.cpp-Metal and MLX), and deliberately disables the App Sandbox for
development; Mac results validate correctness, never mobile performance.
A fourth flavor, `lab` (**Golem Model Lab**, `app.golem.lab`, red icon),
exists on macOS only: the desktop bench for the models the phone flavors
ship, kept out of every other build by a compile-time constant
([ADR 0021](docs/decisions/0021-golem-model-lab.md)).

Backend selection is flavor-coupled with dart-define overrides
(`docs/decisions/0003-flavor-backend-defaults.md`): `qa` and test builds
keep the deterministic fake, while `production` and `dev` default to
`auto` — MLX on iOS, llama.cpp/GGUF on Android, and the existing llama.cpp
default on macOS — with the device-policy model (Gemma 4 E2B at ≥ 7 GiB
reported memory, Qwen 3.5 2B below). The app shell opens only after a
compatible model is explicitly downloaded and verified. An explicit define
always wins in any flavor:

```sh
flutter run --release \
  --dart-define=GOLEM_INFERENCE_BACKEND=llama \
  --dart-define=GOLEM_MODEL_ARTIFACT=qwen35-2b-gguf

# Or run an operator-supplied sideload with an explicit prompt profile:
flutter run --release \
  --dart-define=GOLEM_INFERENCE_BACKEND=llama \
  --dart-define=GOLEM_MODEL_PROFILE=gemma4 \
  --dart-define=GOLEM_MODEL_PATH=documents:models/gemma.gguf
```

`GOLEM_MODEL_PATH` is an absolute path, or `documents:<relative>` resolved
against the app documents directory; `auto` derives it from the catalog.
`GOLEM_MODEL_ARTIFACT` instead selects an exact installed catalog key and
cannot be combined with `GOLEM_MODEL_PATH`.
Every flavor build executes the Inferno build hooks — `qa` is fake at
runtime, not at build time — and native assets are on by default in the
pinned SDK, so no `flutter config` switch is needed.

## Toolchain

The Flutter version is pinned in [`.fvmrc`](.fvmrc), and that file is the only
place it is written: [fvm](https://fvm.app) reads it locally and
`subosito/flutter-action` reads the same file in CI, so the two cannot drift.
`tool/check_toolchain.dart` is the single implementation of that rule — a
literal version anywhere in `.github/workflows/`, an unbounded pubspec
constraint, a tracked `.fvm/`, or an SDK that is not the pinned one all fail
it. Every CI job runs it, and `app/test/toolchain_pin_test.dart` runs it too so
`flutter test` catches drift on its own. Goldens are rasterized by the SDK, so
an unpinned machine silently produces pixel diffs that mean nothing.

```sh
brew tap leoafarias/fvm && brew install fvm   # once per machine
fvm install                                   # materialises .fvmrc's version
```

Every `flutter` and `dart` command in this repository's documentation runs
through that SDK — either prefix it (`fvm flutter test`) or put the checkout on
PATH for the session:

```sh
export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
```

Verify (from the repo root):

```sh
cd app && fvm flutter pub get && fvm flutter analyze && fvm flutter test && cd ..
fvm dart run tool/check_inferno_imports.dart
fvm dart run tool/check_feature_imports.dart
fvm dart run tool/check_toolchain.dart
cd packages/inferno && fvm dart test
```

Before a Play upload, and after any llama.cpp or NDK pin bump, also check the
built Android artifact against Play's native-library rules — see
[`app/README.md`](app/README.md#the-play-release-artifact):

```sh
fvm dart run tool/check_android_packaging.dart
```

See [`app/README.md`](app/README.md) for the app architecture, the asset
and splash pipeline, screen/automation identifiers, and the iPhone 17
simulator verification workflow.

## License

Copyright © 2026 Jan Slominski.

Everything in this repository — the Flutter app under `app/`, Inferno under
`packages/inferno/`, and the tooling and documentation around them — is free
software licensed under the GNU Affero General Public License, version 3
only (`AGPL-3.0-only`; the text is in [`LICENSE`](LICENSE)), with one
exception: the Golem name, mascot, and launcher artwork listed in
[`TRADEMARKS.md`](TRADEMARKS.md) are reserved and not part of that grant.
The software comes with no warranty, and there is no "or any later version"
option.

The engines and packages Golem builds on keep their own licenses and
notices. Settings ▸ Open-source licenses discloses what each build links —
the pinned llama.cpp graph everywhere, the MLX Swift graph on the Apple
silicon builds that carry it — and the direct pub dependencies, with the
audit in [ADR 0009](docs/decisions/0009-model-and-software-attribution.md).
Model weights are never redistributed; their terms are named in Settings ▸
Model attribution.

Contributions are accepted
under [`CLA.md`](CLA.md); [`CONTRIBUTING.md`](CONTRIBUTING.md) has the
workflow. The reasoning, the dependency review, and the store-distribution
basis are recorded in
[ADR 0019](docs/decisions/0019-licensing-and-publication.md).
