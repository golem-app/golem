# Golem Flutter

High-fidelity Flutter implementation of Golem. The app ships as three
coexisting build flavors with independent identities, containers, and
launcher icons:

| Flavor | Display name | Application ID | Icon | Role |
| --- | --- | --- | --- | --- |
| `production` | Golem | `app.golem` | Blue | Canonical release flavor |
| `qa` | Golem QA | `app.golem.qa` | Red | Canonical automation/QA flavor |
| `dev` | Golem Dev | `app.golem.dev` | Green | Developer iteration flavor |

Select a flavor with the standard workflow — `flutter run --flavor qa`,
`flutter build apk --release --flavor production`,
`flutter build ios --simulator --flavor dev`,
`flutter build macos --flavor qa` — or omit `--flavor` to get
`dev` (`default-flavor` in `pubspec.yaml`). The same three flavors exist on
iOS, Android, and macOS. Each flavor stores its own versioned JSON under its
separate application-support container. Flavors share every in-app asset and
theme but differ in identity **and default backend wiring**: `qa` (and the
flavorless test identity) wires all fakes, while `production` and `dev`
wire the real downloader and default to real inference (see "Deterministic
where it matters" below and
`../docs/decisions/0003-flavor-backend-defaults.md`). The flavorless
legacy identity `app.golem.flutter` (**Golem Flutter**) remains reachable
only through direct `xcodebuild -scheme Runner` builds and is never used for
QA or automation.

> **Physical iPhone caution:** never install the `production`
> (`app.golem`) or `dev` (`app.golem.dev`) flavor on the physical iPhone —
> those identifiers belong to the native app there. Simulator use is
> unrestricted.

## Deterministic where it matters

The composition rule, stated once: the `qa` flavor and flavorless
test-harness builds wire **all fakes** (inference, model management,
benchmark), so goldens, journeys, and CI stay deterministic and never
touch the network. `production` and `dev` wire the real implementations —
the pinned Hugging Face downloader and, by default, real local inference.
Explicit dart-defines override the flavor default in any build; an
override to real inference carries model management to the real
implementation with it, so a real engine is never fed by the download
simulation.

Backend resolution (`lib/broker/backend_policy.dart`, decided in
`../docs/decisions/0003-flavor-backend-defaults.md`):
`GOLEM_INFERENCE_BACKEND` accepts `fake`, `llama`, `mlx`, and `auto`;
unset falls to the flavor default (`auto` on production/dev, `fake` on
qa). `auto` composes the llama/GGUF artifact of the device-policy model —
Gemma 4 E2B at ≥ 7 GiB reported physical memory, the lighter Qwen 3.5 4B
below or when memory is unknown — deriving the model path, broker
profile, and active catalog artifact together. A fresh real-backend
install downloads its model **on first need behind an explicit consent
tap** in the chat failure banner; nothing multi-gigabyte ever starts
silently. `GOLEM_DEVICE_MEMORY_BYTES` is a test-only override for
exercising both policy branches on hardware.

Model **downloads** are real in the `dev` and `production` flavors:
Settings lists the pinned catalog (`lib/broker/model_catalog.dart`,
mirroring the Inferno manifest) and downloads artifacts from Hugging Face
with per-file SHA-256 verification, pause/resume, cancel, disk-space
preflight, and delete. Downloads install under
`Documents/models/<catalog-key>/` — resolvable as
`documents:models/<catalog-key>/<file>` — and are excluded from platform
backups (iOS/macOS `NSURLIsExcludedFromBackupKey`, Android
`dataExtractionRules`).

Per-model **generation settings** (temperature, top-p, top-k, max tokens,
context length) live in Settings' Generation section, persist sparsely to
`flutter-prefs-v1.json` (only user-set values; recommended defaults stay
in the broker profiles), and merge onto the profile defaults at
generation time — provable from the effective sampling fields on each
`INFERNO_METRICS` line. Qwen's thinking-mode sampling is pinned against
overrides (off-spec thinking looped during the #33 bring-up); token
budgets apply to both modes,
and the UI keeps max tokens at least a 512-token prompt reserve below
the context length, clamped across both reasoning modes (default cap
8192 for both models).

Cable-provisioned models keep working: any file pushed under `Documents/`
(`ios fsync push`, `adb` + `run-as`) still loads through `GOLEM_MODEL_PATH`,
and delete/cancel only ever remove the app-managed `models/<catalog-key>/`
directories. Pushing an artifact's files into its `models/<catalog-key>/`
layout and tapping Download verifies the pushed bytes and installs them with
no network use (skip-if-valid) — an offline sideload path.

The real local runtime lives in `lib/broker/`, which adapts
`package:inferno` (see the root README). Under `auto` the model path,
profile, and artifact resolve together and cannot disagree. The explicit
`llama|mlx` opt-in keeps today's contract: **`GOLEM_MODEL_PATH` and
`GOLEM_MODEL_PROFILE` are a matched pair** — the profile
(`gemma4` default, `qwen35`; registry in `lib/broker/model_profile.dart`)
supplies the chat template, stop policy, sampling defaults, and
reasoning parsing, and nothing cross-checks it against the model file —
pointing a Qwen artifact at the default Gemma profile silently renders
the wrong template. Explicit real-backend builds must set both. No other
app code may import Inferno;
`../tool/check_inferno_imports.dart` and `test/inferno_import_boundary_test.dart`
enforce that. Benchmark exports contain both:

```json
{
  "simulated": true,
  "validation": "UI simulation only — not hardware validated"
}
```

The Flutter app never migrates, opens, or otherwise reads another app's data.

## Architecture

`CupertinoApp.router` and GoRouter own navigation. Features live under
`lib/features/`; shared immutable models, Glacier tokens, repository contracts,
and generated Riverpod providers live under `lib/core/`.

- `ChatHistoryRepository`: versioned, atomic JSON persistence plus an in-memory
  test implementation. It is the source of truth for chats and active selection.
- `InferenceRepository`: prepare, unload, cancel, and cancellable streamed
  events with optional per-model sampling overrides.
  `FakeInferenceRepository` backs qa/test builds; the broker's
  `InfernoInferenceRepository` is the production/dev default (flavor
  policy above). Reasoning is never copied into later prompt context.
- `SettingsRepository`: sparse per-model generation overrides, persisted
  as schema-v1 JSON with the same atomic-write discipline.
- `ModelManagementRepository`: per-artifact download/pause/cancel/delete over
  the injected catalog plus runtime state, persisted as schema-v2 JSON. The
  fake simulates the same catalog; `RealModelManagementRepository` downloads
  via `background_downloader` behind the `ArtifactFileDownloader` seam, with
  free-space probing and backup exclusion on the
  `app.golem.flutter/storage` platform channel.
- `BenchmarkRepository`: deterministic result generation and JSON export, always
  marked simulated.
- Generated `AsyncNotifier` command controllers serialize chat/model mutations,
  cancel work at lifecycle boundaries, and reject stale completions with epochs.
  Focus, text, scroll, disclosure, and drawer animation remain widget-local state.

Riverpod 3.0.3 is pinned because it is the newest stable runtime/generator set that
resolves with Flutter 3.44.8's pinned analyzer/test packages. Exact transitive
versions are committed in the workspace lockfile at `../pubspec.lock`.

## Screens and identifiers

The app includes the model-aware launch splash, empty and populated chat, reasoning
and answer streaming, live/final metrics, stop and failure recovery, copy,
regenerate, edit-and-truncate, the edge-swipe conversation drawer, Settings model
simulations, runtime controls, Benchmark, JSON export, and the native share sheet.

Stable keys/semantics preserve the native automation vocabulary. The most useful
identifiers are `launch-splash`, `chat-composer`, `send-button`, `stop-button`,
`reasoning-toggle`, `open-drawer`, `drawer-search`, `new-chat-drawer`,
`conversation-<id>`, `conversation-menu-<id>`, `rename-sheet`, `rename-field`,
`confirm-delete`, `open-settings`, `model-card-<key>`, `model-status-<key>`,
`model-download-<key>`, `model-pause-<key>`, `model-cancel-<key>`,
`model-delete-<key>`, `confirm-model-delete` (catalog keys: `gemma4-mlx`,
`gemma4-gguf`, `qwen35-mlx`, `qwen35-gguf`), `download-active-model` (the
chat failure banner's consent CTA when a real backend's model is not
downloaded yet), `gen-temperature-<profile>`, `gen-top-p-<profile>`,
`gen-top-k-<profile>`, `gen-max-tokens-<profile>` and
`gen-context-<profile>` (steppers expose `-minus`/`-plus` suffixed
buttons), `gen-reset-<profile>` (profile keys: `gemma4`, `qwen35`),
`runtime-toggle-button`,
`open-benchmark`, `benchmark-case-picker`, `benchmark-phase-picker`,
`benchmark-run-button`, `benchmark-stop-button`, and `benchmark-export-button`.

Startup failure modes are injectable at compile time:

```sh
flutter run --dart-define=GOLEM_MISSING_MODEL=true
flutter run --dart-define=GOLEM_SPLASH_FAILURE=true
flutter run --dart-define=GOLEM_SPLASH_TIMEOUT=true
```

The production-style splash always holds for at least 1.4 seconds; the missing-model
scenario adds a three-second setup hold.

## Generate and verify

Use the installed Flutter 3.44.8/Dart 3.12.2 SDK as-is:

```sh
flutter pub get
dart run build_runner build
dart run tool/prepare_launcher.dart
dart run flutter_launcher_icons
dart run flutter_native_splash:create
dart run tool/prepare_ios_launch.dart
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
(cd .. && dart run tool/check_inferno_imports.dart)
(cd ../packages/inferno && dart test)
```

Building or running with a real inference backend executes the Inferno build
hooks and requires `flutter config --enable-native-assets` once per machine.
That now includes plain `flutter run`/`flutter build` (the `dev` flavor
defaults to `auto`); only qa-flavor builds and host `flutter test` stay on
the hook-free fake path.

`dart run tool/prepare_launcher.dart` derives every flavor's Android
launcher inputs from the tracked native artwork in `assets/source/`
(`golem_icon_<flavor>_1024.png`), sampling each adaptive-icon gradient from
the artwork itself, and writes the per-flavor macOS Dock iconsets
(`macos/Runner/Assets.xcassets/AppIcon-<flavor>.appiconset`) directly —
Apple-style rounded squares on a transparent margin — because
flutter_launcher_icons can only emit one fixed macOS catalog. One
`dart run flutter_launcher_icons` invocation then generates all three
flavors from the `flutter_launcher_icons-<flavor>.yaml` configs (their
presence makes the tool ignore any pubspec block): the
`AppIcon-<flavor>.appiconset` catalogs on iOS and the
`android/app/src/<flavor>/res` source sets on Android. The launch splash is
deliberately identical for every flavor.

The in-app splash uses mascot-only transparent artwork over a Glacier navy
(`#0F1524`) surface, without an app-icon tile, frame, or backing panel. The
native iOS launch screen is the hand-owned, solid-navy
`GolemLaunchScreen.storyboard` with no image: the iOS 26 launch-snapshot
renderer draws storyboard launch images at the wrong scale and flattens their
transparency to white, so all launch artwork is deliberately left to the
Flutter splash. `flutter_native_splash` runs with `ios: false` and
`tool/prepare_ios_launch.dart` guards the wiring.
`platform_assets_test.dart` guards the navy image-free storyboard, splash
alpha, mascot transparency, the Android-only navy-matted launcher icon, and
the unmodified source artwork used for the iOS icon. Both launcher sources
derive from the tracked artwork in `assets/source/`.

User-facing copy is intentionally hardcoded English; there is no
ARB/gen-l10n layer to keep half-wired. If a
second locale ever materializes, reintroduce `l10n.yaml` + `generate: true`
and migrate the presentation strings then.

Golden tests use the iPhone 17 logical viewport (402 × 874) in light and dark
appearances. They cover splash, empty/populated chat, reasoning, the native-style
conversation drawer, rename overlay, Settings states, and Benchmark. The widget
suite also runs Flutter's iOS
44-point target, semantic-label, contrast, and enlarged-text checks.

## iPhone 17 simulator verification

Only use the single already-booted iPhone 17 simulator. Never boot or select a
different simulator, Android target, or physical iPhone for this project.

```sh
export GOLEM_SIMULATOR_ID="$(xcrun simctl list devices | awk '/iPhone 17 .*Booted/{gsub(/[()]/, "", $NF); print $NF; exit}')"
test -n "$GOLEM_SIMULATOR_ID"

flutter test integration_test/app_journey_test.dart \
  --flavor qa \
  --dart-define=GOLEM_STREAM_DELAY_MS=250 \
  -d "$GOLEM_SIMULATOR_ID"
flutter build ios --simulator --flavor qa
```

QA is the canonical flavor for automated integration and visual testing.
Every flavor build lands at the same `Runner.app` path, so install each
flavor right after building it; the three flavors coexist side by side:

```sh
xcrun simctl install "$GOLEM_SIMULATOR_ID" build/ios/iphonesimulator/Runner.app
```

Use Mobile MCP for launch, element inspection, interaction, screenshots, and native
share-sheet review after installation. Android startup, the shared integration
journey, and launcher/splash presentation have also been verified on a OnePlus
12R running Android 16; Android release signing remains intentionally unconfigured.

## macOS verification

The macOS target mirrors the mobile flavors and exists for two jobs:
previewing tablet-proportioned layout without an iPad, and running real-model
inference at desktop GPU speed. **Mac GPU numbers are for correctness and
iteration speed only — never quote them as mobile performance.**

```sh
flutter run -d macos                      # dev flavor via default-flavor
flutter build macos --flavor qa           # or production / dev
flutter test integration_test/app_journey_test.dart -d macos --flavor qa
```

The window opens at the iPad Pro 11" logical portrait size (834 × 1194),
clamped to the screen and freely resizable down to 480 × 640
(`macos/Runner/MainFlutterWindow.swift`); the frame autosaves per identity.
The App Sandbox is **deliberately disabled** in both entitlement files: this
is a development target that must read model files from arbitrary local
paths. Distribution hardening (sandbox, notarization, signing) is a later,
separate effort. Because the sandbox is off,
`getApplicationDocumentsDirectory()` resolves to the real `~/Documents` —
prefer absolute `GOLEM_MODEL_PATH` values on macOS:

```sh
flutter run -d macos --flavor qa \
  --dart-define=GOLEM_INFERENCE_BACKEND=llama \
  --dart-define=GOLEM_MODEL_PATH=/abs/path/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
```

Both engines run GPU-accelerated on Apple silicon: llama.cpp with Metal
(enabled for every Apple target by Inferno's build hook) and MLX exactly as
on iOS. `INFERNO_METRICS` lines appear on the `flutter run` console, or on
stdout when launching the built binary directly
(`build/macos/Build/Products/Release-qa/golem_flutter.app/Contents/MacOS/golem_flutter`).

For cross-device determinism probes, build with
`--dart-define=GOLEM_SAMPLING_SEED=<n>`: every completed generation then
logs one `INFERNO_PROBE` line hashing the raw pre-parser output, and
`integration_test/real_backend_probe_test.dart` drives one seeded
generation through the chat UI with a fixed prompt. Findings live in
`../docs/notes/determinism-probe.md`.

## Model evaluation harness (macOS)

`integration_test/model_eval_test.dart` turns model and quantization
decisions into recorded evidence: it runs the fixed prompt set in
`integration_test/eval/eval_spec.dart` against every requested
artifact × engine combo, scores the parsed answer channel with
deterministic checks, captures full broker metrics (decode/prompt tok/s,
TTFT, peak footprint) under fixed seeds, and writes `report.json` plus a
committable `report.md` per run. Fetch the pinned artifacts first
(from `../packages/inferno`: `dart run tool/fetch_model.dart gguf` and
`dart run tool/fetch_model.dart mlx`), then one command evaluates both
engines:

```sh
flutter test integration_test/model_eval_test.dart -d macos --flavor qa \
  --dart-define=GOLEM_EVAL_GGUF=/abs/path/model.gguf \
  --dart-define=GOLEM_EVAL_MLX=/abs/path/mlx-model-dir
```

Both defines accept comma-separated lists (that is the quant-comparison
mode); either may be omitted. `GOLEM_EVAL_OUT` overrides the report
directory (default: the system temp dir — the exact paths are printed as
`GOLEM_EVAL_REPORT` lines), and `GOLEM_EVAL_TEMPLATE` selects the model
profile (default `gemma4`; the harness consumes the broker's profile
registry in `lib/broker/model_profile.dart` directly, so an evaluation
exercises exactly the template, stop policy, sampling defaults, and parser
the app ships). The suite self-skips when
no artifact is requested, and it must never be wired into CI. Keep
evidence worth citing (quant choices, pin bumps, ADRs) as committed
reports under `../docs/evals/`. The spec's `anchor-jupiter` prompt
reuses the determinism probe's exact prompt and sampling, so its
`fnv1a64` hash cross-references `../docs/notes/determinism-probe.md`.
Mac numbers serve answer quality and relative comparison only — never
quote them as mobile performance.
