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
> (`app.golem`) flavor on the physical iPhone — that identifier belongs
> to the native app there (and its imported model). The `qa` and `dev`
> flavors are fine to deploy. Simulator use is unrestricted.

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
silently. Builds with an operator-supplied `GOLEM_MODEL_PATH` bypass that
gate entirely — sideloaded paths are the operator's responsibility and go
straight to the engine. `GOLEM_DEVICE_MEMORY_BYTES` is a test-only override for
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

Transfers outlive the app process, so they are **reconciled** rather than
remembered: at startup and on every return to the foreground the app asks the
platform what it still holds for each artifact, adopts a transfer that is still
running instead of starting a second one, resumes a partial where resume data
survived, and turns proven silence into an actionable Paused. Two platform
limits are real and recorded rather than papered over — Android's `force-stop`
cancels the OS jobs until the app is launched by hand, and closing the app from
the iOS App Switcher stops its background downloads outright. The rules are in
`../docs/decisions/0005-download-lifecycle.md`; how they are proven, and which
evidence no test process can produce, is in
`../docs/notes/download-lifecycle.md`.

Which artifact has actually been run on which hardware — and what is therefore
not claimed — is recorded in `../docs/real-model-matrix.md`, together with the
gated instruments that produced it.

Image input follows proven capability, never a model name: only artifacts whose
vision path has been validated accept a picture, and the attach sheet disables
its rows with copy naming the model otherwise. Today that is Gemma 4 E2B on
llama.cpp/GGUF, which loads a pinned `mmproj` projector beside its weights
(selection evidence: `../docs/evals/2026-08-09-gemma4-mmproj-selection.md`;
design: `../docs/decisions/0004-image-input.md`). Attached images are copied
into an app-owned store under application support, referenced by opaque id so
no transcript or export can leak a source path, and collected as soon as no
conversation mentions them. Unlike model weights they are kept in platform
backups — a model is re-fetchable, a photo is not.

Per-model **generation settings** (temperature, top-p, top-k, max tokens,
context length) live in Settings ▸ Response style's Advanced sampling
section, persist sparsely to `flutter-prefs-v1.json` (only user-set
values; recommended defaults stay in the broker profiles), and merge onto
the profile defaults at generation time — provable from the effective
sampling fields on each `INFERNO_METRICS` line. **Response styles**
(Precise / Balanced / Creative, per profile) map onto explicit sampling
values in `core/domain/response_style_mapping.dart` and layer *under*
those hand-set overrides, knob by knob; Balanced means the profile
defaults. The Advanced-mode **system prompt** renders as the leading
system turn of the chat template on real engines and is acknowledged by
the fake. App-wide preferences (theme, text size, transcript toggles,
save-history, Advanced mode, response styles, custom repositories)
persist separately to `flutter-ui-prefs-v1.json` with the same sparse
schema-v1 atomic-write discipline. Qwen's thinking-mode sampling is pinned against
overrides (off-spec thinking looped during the #33 bring-up); token
budgets apply to both modes, and the UI keeps max tokens at least a
512-token prompt reserve below the context length, clamped across both
reasoning modes (default cap 8192 for both models).

Cable-provisioned models keep working: any file pushed under `Documents/`
(`ios fsync push`, `adb` + `run-as`) still loads through `GOLEM_MODEL_PATH`,
and delete/cancel only ever remove the app-managed `models/<catalog-key>/`
directories. Pushing an artifact's files into its `models/<catalog-key>/`
layout and tapping Download verifies the pushed bytes and installs them with
no network use (skip-if-valid) — an offline sideload path.

The real local runtime lives in `lib/broker/`, which adapts
`package:inferno` (see the root README). Under `auto` the model path,
profile, and artifact resolve together and cannot disagree.
`GOLEM_MODEL_ARTIFACT` selects an exact pinned catalog key (including Qwen
2B versus 4B), derives its profile when none is supplied, and rejects an
engine or explicit-profile mismatch. `GOLEM_MODEL_PATH` remains the separate
operator-sideload contract and must be paired manually with
`GOLEM_MODEL_PROFILE` (`gemma4` or `qwen35`); because a sideload has no catalog
proof, it stays text-only, claims no catalog key, and is labeled by its own file
name rather than the pinned artifact its profile implies. Artifact and path
overrides are mutually exclusive.
No other app code may import Inferno;
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
`lib/features/`; shared immutable models, the Golem Navy design tokens
(`lib/core/theme/` — colors, type ramp, radii/spacing/sizes, elevation and
motion, light + dark), the platform-chrome layer (`lib/core/chrome/` —
`GolemChrome` resolves cupertino or android chrome from the target platform
and drives the nav bar, menu, alert, sheet, action list, and primary button;
layout, color, and type stay identical across platforms), repository
contracts, and generated Riverpod providers live under `lib/core/`. The
design source of truth is the handoff under `references/ui_redesign/` at the
repo root.

- `ChatHistoryRepository`: versioned, atomic JSON persistence plus an in-memory
  test implementation. It is the source of truth for chats and active selection.
- `InferenceRepository`: prepare, unload, cancel, and cancellable streamed
  events with optional per-model sampling overrides.
  `FakeInferenceRepository` backs qa/test builds; the broker's
  `InfernoInferenceRepository` is the production/dev default (flavor
  policy above). Reasoning is never copied into later prompt context.
- `SettingsRepository`: sparse per-model generation overrides, persisted
  as schema-v1 JSON with the same atomic-write discipline.
- `PreferencesRepository`: app-wide preferences (appearance, transcript,
  privacy, Advanced mode, response styles, custom repositories) in a
  second schema-v1 store, so neither file's schema constrains the other.
- `ModelManagementRepository`: per-artifact download/pause/cancel/delete over
  the injected catalog plus runtime state, persisted as schema-v2 JSON. The
  fake simulates the same catalog; `RealModelManagementRepository` downloads
  via `background_downloader` behind the `ArtifactFileDownloader` seam, with
  free-space probing and backup exclusion on the
  `app.golem.flutter/storage` platform channel. The seam is identity-aware:
  every call names an `ArtifactFileRef`, and `inspect` reports what the OS
  still holds, so a stop issued after a relaunch reaches the transfer the
  previous process started. Which transfer a platform task belongs to travels
  in the task's `metaData`, never in its id — `0005-download-lifecycle.md`
  explains why the obvious alternative is unsafe.
- `BenchmarkRepository`: deterministic result generation and JSON export, always
  marked simulated.
- Generated `AsyncNotifier` command controllers serialize chat/model mutations,
  cancel work at lifecycle boundaries, and reject stale completions with epochs.
  Focus, text, scroll, disclosure, and drawer animation remain widget-local state.

The Riverpod runtime, annotation, and generator are pinned exactly, and move
only as one set, because each release exact-pins the next. The set sits at the
ceiling the pinned SDK allows. Exact versions live in the workspace lockfile
at `../pubspec.lock`; the constraint chain that sets the ceiling, and the
blocker holding every other package back from its latest release, are recorded
once in `../docs/notes/dependencies.md`.

## Screens and identifiers

The app includes the model-aware launch splash, empty chat with starter chips,
markdown transcript with syntax-highlighted code cards, reasoning and answer
streaming (blinking caret + live generating pill), stop and failure recovery
with the ephemeral stopped-tokens caption, message actions (copy, regenerate,
branch-from-here, share, delete), edit-and-truncate, the sectioned edge-swipe
conversation drawer with pinning and a storage meter, full-screen cross-chat
search, the per-chat model picker, image attachment from the photo library,
camera, or a file — gated on what the selected model can actually read —
confirmation toasts, the redesigned minimal Settings (root rows plus Models,
Response style, System prompt, Appearance, Privacy & data, and Storage
sub-screens, with an Advanced mode switch gating the sampling controls, the
system prompt, and the custom-repository loader, which resolves a repository to
an immutable commit and shows its files and prompt profile before anything is
added), runtime controls, Benchmark,
JSON export, and the native share sheet. Privacy & data can stop saving chat
history (confirming, then emptying the on-disk store), export every chat as
JSON, and delete all chats; Storage breaks usage into models, chats, and
cache with per-model delete and a cache clear. A resolved custom repository
downloads, verifies, and activates through the same paths as a pinned one; the
fake simulates the whole flow, and an unresolved entry still refuses to download
because its file list is synthesized.

Assistant messages render a scoped markdown subset (paragraphs, emphasis,
inline code, one-level lists, fenced code with a fixed dark card in both
themes) through `features/chat/widgets/markdown/`; parsing is memoized per
message so only the streaming bubble re-parses. Free text selection is
deliberately absent — copy actions cover it on both chromes. Toasts are the
chrome layer's `showGolemToast` (iOS pill / Android bar, no actions).

The per-chat model selection persists on the conversation (`modelKey`) and a
real engine honors it: the next send unloads and loads the chosen artifact
through the residency owner. Because the **engine** is a build-time composition
(`auto` composes llama.cpp/GGUF), the picker offers only artifacts that engine
can load *and* that are installed — so every label may name the choice
immediately without promising weights the next send would refuse. A model that
is not downloaded stays disabled and points at Settings ▸ Models; under an
operator `GOLEM_MODEL_PATH` the sheet refuses entirely and names the file the
build pins, because a sideload has no catalog key to switch back to. Sampling,
response style, and capability all follow the chosen model's profile, not the
build's boot profile.

Stable keys/semantics preserve the native automation vocabulary. The most useful
identifiers are `launch-splash`, `chat-composer`, `send-button`, `stop-button`,
`reasoning-toggle`, `composer-attach`, `composer-model-chip`,
`starter-chip-<name>`, `generating-pill`, `stopped-caption`,
`message-copy-<id>`, `message-regenerate-<id>`, `message-share-<id>`,
`message-menu-<id>` plus `menu-message-{copy,regenerate,branch,share,delete}`,
`code-block`/`code-copy`, `attach-sheet` plus
`attach-{photo-library,take-photo,files}`, `composer-attachments` plus
`composer-attachment-remove-<index>`, `model-picker-sheet`,
`model-picker-<catalogKey>`, `model-picker-manage`, `golem-toast`,
`open-drawer`, `drawer-search-button`, `new-chat-drawer`,
`conversation-<id>`, `conversation-menu-<id>` plus
`menu-{pin-toggle,rename,share-transcript,delete}`, `storage-meter`,
`search-field`, `search-cancel`, `search-results`, `search-result-<id>`,
`search-empty`, `rename-sheet`, `rename-field`, `rename-counter`,
`confirm-delete`, `open-settings`,
`settings-{model,style,system-prompt,appearance,privacy,storage}-row`,
`advanced-mode-switch`, `about-row`, `about-sheet`,
`models-tab-{all,installed}`, `model-card-<key>`, `model-status-<key>`,
`model-download-<key>`, `model-pause-<key>`, `model-cancel-<key>`,
`model-delete-<key>`, `confirm-model-delete` (catalog keys: `gemma4-mlx`,
`gemma4-gguf`, `qwen35-mlx`, `qwen35-gguf`, plus derived
`custom-<repository-slug>` entries),
`custom-repo-{engine-mlx,engine-gguf,field,revision,resolve,add,error,detail}`
(`resolve` reads the repository, `add` commits what it found, and `add` only
exists once a resolution is on screen), `download-active-model`
(the chat failure banner's consent CTA when a real backend's model is not
downloaded yet), `style-{precise,balanced,creative}`,
`gen-temperature-<profile>`, `gen-top-p-<profile>`,
`gen-top-k-<profile>`, `gen-max-tokens-<profile>` and
`gen-context-<profile>` (steppers expose `-minus`/`-plus` suffixed
buttons; the sampling card edits the active profile),
`gen-reset-<profile>` (profile keys: `gemma4`, `qwen35`),
`system-prompt-field`, `system-prompt-reset`,
`theme-{system,light,dark}`, `text-scale-slider`,
`toggle-{metrics,reasoning,haptics,save-history}`, `confirm-history-off`,
`export-chats`, `delete-all-chats`, `confirm-delete-all`, `storage-bar`,
`storage-model-<key>`, `storage-delete-<key>`, `clear-cache`,
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

The in-app splash uses mascot-only transparent artwork over a Golem navy
(`#060D1F`) surface, without an app-icon tile, frame, or backing panel. The
launcher-icon matte deliberately stays on the older `#0F1524` navy — icon
artwork is regenerated only by an artwork change. The
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

Golden tests use the iPhone 17 logical viewport (402 × 874). Every surface
records light and dark under iOS chrome, and the chrome-visible surfaces
(chat, Settings, Benchmark) add an `-android` light variant — the platform
axis rides `TargetPlatformVariant` in `test/support/harness.dart` (widget
tests report android by default, so goldens pin the platform explicitly).
Sheets (rename, model picker, attach) record android in both appearances:
the drag handle is the android-only painted element whose tint differs.
They cover splash, empty/populated chat, reasoning, the markdown
transcript, search, the composer sheets, the sectioned conversation
drawer, rename overlay, every settings surface (root, models, response
style, appearance, privacy, storage, system prompt — with iOS-only
Advanced variants for the root, custom repository, and sampling states),
and Benchmark. The widget suite also runs Flutter's iOS 44-point target,
semantic-label, contrast, and enlarged-text checks; the settings root,
appearance, and privacy screens are enrolled alongside chat, which is
why segments and switches carry full 44-point targets and footnotes use
muted rather than tertiary ink.

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

## Real-model acceptance (device)

`integration_test/device_acceptance_test.dart` runs one device/engine cell end
to end — install (verifying bytes already in the container, or downloading them
for real), a text turn, a per-chat switch to a second artifact and a turn on it,
an image turn, and history read back off disk:

```sh
flutter test integration_test/device_acceptance_test.dart -d <device> \
  --flavor qa --no-uninstall --dart-define=GOLEM_INFERENCE_BACKEND=auto \
  --dart-define=GOLEM_DEVICE_ACCEPTANCE=true \
  --dart-define=GOLEM_ACCEPT_PRIMARY=gemma4-gguf \
  --dart-define=GOLEM_ACCEPT_SECONDARY=qwen35-2b-gguf \
  --dart-define=GOLEM_ACCEPT_IMAGE=true
```

**`--no-uninstall` is not optional on a phone.** `flutter test` uninstalls the
app on teardown by default and takes the container's models with it, which is
what used to make every run pay a full multi-gigabyte provisioning pass. With
the flag the app and its documents survive, so provisioning is once per device
and every later run installs from bytes already present. Desktop targets are
unaffected either way — a macOS "uninstall" is a no-op.

**`flutter install` wipes the container too, and has no such flag.** It
uninstalls the old version before installing, so it destroys provisioned
models even when the install then fails — the app comes back empty. Use it on
a provisioned phone only if you intend to re-provision. To replace the binary
and keep `Documents/`, build and install without uninstalling:

```sh
flutter build ios --release --flavor qa            # or: build apk --flavor qa
xcrun devicectl device install app --device <UUID> \
  build/ios/iphoneos/Runner.app                    # Android: adb install -r
```

`devicectl device install app` and `adb install -r` both upgrade in place.

Provisioning is therefore a separate, deliberate step, and the offline path is
the default: an unprovisioned artifact fails fast and names the directory to
fill rather than quietly spending five gigabytes. Sideload the pinned files
(`../packages/inferno/lib/src/model_manifest.dart` is the authority on names and
byte counts; `dart run tool/fetch_model.dart gguf` in `../packages/inferno`
fetches them to the Mac) into `models/<catalog-key>/` under the app's documents
directory. One bootstrap run creates those directories for you:

```sh
# Android — flutter test builds debug, so the QA package is run-as-able
adb -s <serial> push <file> /data/local/tmp/
adb -s <serial> shell run-as app.golem.qa \
  cp /data/local/tmp/<file> app_flutter/models/<catalog-key>/

# iOS — one file per invocation; devicectl will not copy a directory
xcrun devicectl device copy to --device <UUID> --user mobile \
  --domain-type appDataContainer --domain-identifier app.golem.qa \
  --source <file> --destination Documents/models/<catalog-key>/<name>
```

The next run hashes them in place against the pinned SHA-256s, writes the
receipt, and installs with no network at all; the run after that finds the
receipt and does neither. To fetch from Hugging Face for real instead — the
path the matrix's downloaded cells claim — add
`--dart-define=GOLEM_ACCEPT_DOWNLOAD=true`.

Every gated instrument paints its progress on the device it occupies
(`integration_test/support/acceptance_hud.dart`): current step, live bytes
against the artifact total, and an elapsed clock, so a working run and a hung
one no longer look the same. It is test-only and never linked into `lib/`, which
`test/inferno_import_boundary_test.dart` enforces. Read it off the screen rather
than attaching an observer — a WebDriverAgent session (Mobile MCP against a real
iPhone) turns on iOS accessibility, and the semantics handle that opens fails
the run at teardown with "A SemanticsHandle was active at the end of the test"
after every assertion has already passed.

One more operational fact: a release build's `debugPrint` is
os_log-privacy-redacted in an `ios syslog` capture, so read `GOLEM_CELL` and
`INFERNO_METRICS` from the test harness console instead. Results live in
`../docs/real-model-matrix.md`.

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
