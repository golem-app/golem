# Golem Flutter

High-fidelity Flutter implementation of Golem. The iOS and Android
application identifier is `app.golem.flutter`; the display name is
**Golem Flutter**. It stores its own versioned JSON under its separate
application-support container.

## Deterministic by default

Every build defaults to the simulated backend: no HTTP client, Hugging Face
integration, USB importer, bundled model weights, or hardware performance
measurement. Every model transition and generated token is deterministic
simulation, and model screens say so in the UI. A real local runtime exists
behind one explicit opt-in: `lib/broker/` adapts `package:inferno` (see the
root README) and is selected only by building with
`--dart-define=GOLEM_INFERENCE_BACKEND=llama|mlx` plus
`--dart-define=GOLEM_MODEL_PATH=…`. No other app code may import Inferno;
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
  events. `FakeInferenceRepository` is the default; the broker's
  `InfernoInferenceRepository` is the opt-in real runtime. Reasoning is never
  copied into later prompt context.
- `ModelManagementRepository`: selected backend, MLX download/pause/resume/verify,
  TurboFieldfare import/verify, and runtime state, all persisted simulations.
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
`confirm-delete`, `open-settings`, `backend-option-mlx`,
`backend-option-turbofieldfare`, `mlx-download-button`,
`mlx-download-cancel-button`, `model-import-button`, `runtime-toggle-button`,
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
hooks and requires `flutter config --enable-native-assets` once per machine;
the default fake-backend workflow does not need it.

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
  --dart-define=GOLEM_STREAM_DELAY_MS=250 \
  -d "$GOLEM_SIMULATOR_ID"
flutter build ios --simulator
```

Install the build over the existing **Flutter** app (never touch `app.golem`):

```sh
xcrun simctl install "$GOLEM_SIMULATOR_ID" build/ios/iphonesimulator/Runner.app
```

Use Mobile MCP for launch, element inspection, interaction, screenshots, and native
share-sheet review after installation. Android startup, the shared integration
journey, and launcher/splash presentation have also been verified on a OnePlus
12R running Android 16; Android release signing remains intentionally unconfigured.
