# Golem (Flutter app)

High-fidelity Flutter implementation of Golem. The app ships as four
coexisting build flavors with independent identities, containers, and
launcher icons — three phone flavors on every platform, and one bench that
exists on macOS only:

| Flavor | Display name | Application ID | Icon | Platforms | Role |
| --- | --- | --- | --- | --- | --- |
| `production` | Golem | `app.golem` | Blue | iOS, Android, macOS | Canonical release flavor |
| `qa` | Golem QA | `app.golem.qa` | Grey | iOS, Android, macOS | Canonical automation/QA flavor |
| `dev` | Golem Dev | `app.golem.dev` | Green | iOS, Android, macOS | Developer iteration flavor |
| `lab` | Golem Model Lab | `app.golem.lab` | Red | macOS | The model bench (ADR 0021; "Golem Model Lab" below) |

Select a flavor with the standard workflow — `flutter run --flavor qa`,
`flutter build apk --release --flavor production`,
`flutter build ios --simulator --flavor dev`,
`flutter build macos --flavor qa` — or omit `--flavor` to get
`dev` (`default-flavor` in `pubspec.yaml`). The three phone flavors exist on
iOS, Android, and macOS; `lab` has macOS build configurations, a scheme and a
Dock icon and nothing on the phones. Each flavor stores its own versioned JSON
under its separate application-support container. Flavors share every in-app asset and
theme but differ in identity **and default backend wiring**: `qa` wires all
fakes, while `production` and `dev` wire the real downloader and default to
real inference (see "Deterministic where it matters" below and
`../docs/decisions/0003-flavor-backend-defaults.md`).

The flavorless `Debug`/`Release`/`Profile` configurations — what a direct
`xcodebuild -scheme Runner` selects — carry qa's bundle id, display name, and
launcher artwork, so **no build path produces an app outside the shipped
set** (#116).

Their Dart half is not equally fixed, and this is a trap worth knowing. Those
configurations inherit `Flutter/Generated.xcconfig`, which the last
`flutter build` wrote — including its `FLAVOR` and the `FLUTTER_APP_FLAVOR`
dart-define. So `appFlavor`, and with it the backend wiring, the in-app icon,
and the internal-tool gates, is whatever that earlier build named;
`AppIdentity.forFlavor` returns `qa` only when no flavor was baked at all.
Run `xcodebuild -scheme Runner` after `flutter build ios --flavor dev` and you
get a bundle labelled **Golem QA** that installs over the QA container and
runs `dev`'s real inference and real downloader. Prefer `flutter build
--flavor <name>`; if you must use a bare `xcodebuild`, run the matching
`flutter build ... --flavor qa` immediately before it.

> **Physical devices:** build and install through `tool/device_install.sh`
> (repo root), never by hand. It refuses to install anything but a freshly
> built, correctly signed bundle whose id matches the flavor, clears the
> stale Swift module cache an SDK bump leaves behind, and stamps the commit
> into Settings ▸ About so a tester can see which build is in hand. A bare
> `xcodebuild` once installed a morning-old binary for QA.

## Deterministic where it matters

The composition rule, stated once: the `qa` flavor — which is also where
flavorless builds land — wires **all fakes** (inference, model management,
benchmark), so goldens, journeys, and CI stay deterministic and never
touch the network. `production` and `dev` wire the real implementations —
the pinned Hugging Face downloader and, by default, real local inference.
Explicit dart-defines override the flavor default in any build; an
override to real inference carries model management to the real
implementation with it, so a real engine is never fed by the download
simulation.

One device-shaped exception (#148): on a **simulator or emulator**, `dev`
joins `qa` on the fakes rather than fetching weights nothing there can load,
so a plain `flutter run` is safe on both. It applies only to a build that
named no model configuration: `production` is excluded — its composition stays
a build-time fact — and any of `GOLEM_INFERENCE_BACKEND`,
`GOLEM_MODEL_ARTIFACT`, or `GOLEM_MODEL_PATH` keeps the real path, in which
case the device classification below refuses the transfer instead. That last
part includes `qa`: `--flavor qa --dart-define=GOLEM_INFERENCE_BACKEND=auto`
is refused on a simulator rather than offered a download it could not use.

Backend resolution (`lib/broker/backend_policy.dart`, decided in
`../docs/decisions/0003-flavor-backend-defaults.md`):
`GOLEM_INFERENCE_BACKEND` accepts `fake`, `llama`, `mlx`, and `auto`;
unset falls to the flavor default (`auto` on production/dev, `fake` on
qa). `auto` composes MLX on iOS, llama/GGUF on Android, and llama/GGUF on
macOS. It selects Gemma 4 E2B at ≥ 7 GiB reported physical memory and the
lighter Qwen 3.5 2B below or when memory is unknown, deriving the model path, broker
profile, and active catalog artifact together. A fresh real-backend install
enters first-run onboarding before chat. It explains that inference stays on
device, selects a pinned artifact from the same device tier and engine policy
as launch, states the exact catalog size, and asks for explicit consent with
the 500 MiB free-space margin plus a static Wi-Fi/cellular warning. Declining
starts no transfer and leaves setup blocking the entire app shell. Pause,
failure, interruption, deletion, and invalidation behave the same way until a
compatible artifact is verified. Settings and missing-model
recovery use the same consent dialog, so nothing multi-gigabyte starts
silently from another UI path. The qa flavor presents the full catalog and
simulates the flow deterministically with no network or weight files. Existing
installs skip the introduction but not the usable-model invariant. An
operator-supplied `GOLEM_MODEL_PATH` skips consumer onboarding only after the
engine successfully loads it for the current process.

That model choice is one half of a single **device classification** taken once
at launch (#27, `../docs/decisions/0007-supported-device-policy.md`): the same
reading decides whether this device is admitted to running a model at all.
Below the floor — nominal 4 GB, read as 4 GiB on Apple and 3 GiB on Android —
or on an arm64 Android CPU without the dot-product extension the shipped
kernels require, or on a simulator or emulator running a real backend, the app
downloads and loads nothing and says why in a blocking startup surface that
wraps every route. Persisted chats, preferences, and
files are untouched;
memory that cannot be read classifies as supported, never as refused. The
App Store enforces its half through `UIRequiredDeviceCapabilities`
(`iphone-ipad-minimum-performance-a12`); Play's RAM floor is a console-side
device-catalog exclusion rule, recorded in `../docs/device_floor.md` because
no manifest can express it. In `qa` and `dev`,
`GOLEM_DEVICE_MEMORY_BYTES` and `GOLEM_DEVICE_ENGINE_UNSUPPORTED` are
test-only overrides for exercising the tiers and the two hardware refusals on
devices that cannot produce them; production ignores both defines. The
virtual-device refusal needs no override — a `production` build, or any
explicit engine define, produces it directly on the simulator and the
emulator, where it also preempts the other two.

Model **downloads** are real in the `dev` and `production` flavors:
Settings lists the pinned catalog (`lib/broker/model_catalog.dart`,
mirroring the Inferno manifest) and downloads artifacts from Hugging Face
with SHA-256 verification of every file once the whole artifact has arrived,
pause/resume, cancel, disk-space preflight, and delete. Downloads install under
`Documents/models/<catalog-key>/` — resolvable as
`documents:models/<catalog-key>/<file>`. They are excluded from platform
backups like everything else the app stores (iOS/macOS
`NSURLIsExcludedFromBackupKey` on both storage roots at launch, Android
`allowBackup="false"` plus extraction rules for device transfer; ADR 0016).

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
conversation mentions them. Like every other store they stay out of platform
backups: nothing Golem holds leaves the phone
(`../docs/decisions/0016-release-bundle-declarations.md`), and Export every
chat is the way to carry a history to a new device.

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
`lib/features/`, each owning its controllers and derivations in
`features/<name>/application/` with committed `.g.dart` parts (legal,
preferences, models — including storage accounting — chat, settings,
onboarding, benchmark, eval). Those are also the layers of a recorded
import direction, in that order: a feature imports strictly downward and never
sideways, `core/` imports no feature at all, and only `lib/app/` and `main.dart`
may name every feature. `../tool/check_feature_imports.dart` and
`test/feature_import_boundary_test.dart` enforce it; the reasoning, including
why the Models screen is a Settings screen, is in
[ADR 0015](../docs/decisions/0015-feature-layering.md).

Shared immutable models, the Golem Navy design tokens
(`lib/core/theme/` — colors, type ramp, radii/spacing/sizes, elevation and
motion, light + dark), the platform-chrome layer (`lib/core/chrome/` —
`GolemChrome` resolves cupertino or android chrome from the target platform
and drives the nav bar, menu, alert, sheet, action list, badge, and buttons;
layout, color, and type stay identical across platforms), and repository
contracts live under `lib/core/`. No feature builds a platform button
directly: a label is a `GolemButton`, a glyph a `GolemIconButton`, and a
tappable row or chip a `GolemTappable`, which is the one place the platform tap
minimum is stated. `test/chrome_boundary_test.dart` enforces that, and the
sizes it owns are why `features/` holds no hard-coded 44 or 48.
`lib/core/providers/app_providers.dart` holds only what is genuinely shared:
the launch seams wired by `launchOverrides`, the boot-constant derivations,
and the session bridges through which one feature's controller offers
capabilities to another without a feature→feature import (#88). The visual
design was handed off as a set of mockups the maintainer holds outside this
repository; the Golem Navy tokens under `lib/core/theme/` are their
committed form.

One artifact transfer is projected once, by
`features/models/artifact_transfer.dart`: the percentage, the pace figures,
the phase's affordance and why it is blocked. First run, Settings ▸ Models,
the chat setup banner and the model picker all read that one answer — the two
card surfaces through `TransferCard` at two densities, the rest through
`LabeledProgress`, which is also the only place a progress bar states its
accessible reading. Verification is a determinate phase of its own (#143):
the repository transfers every file first and hashes them all afterwards,
counting hashed bytes in `ArtifactStatus.verifiedBytes` (in-memory, never
persisted), so the projection reads each phase's own counter, the pace
notifier opens a fresh window at the phase edge, and the chip quotes MB/s for
a download but only names a verification — a hash throughput would read as a
download that slowed down. Within one attempt the bar never steps back; the
one path that returns from verifying to downloading is a sideloaded file that
fails its hash and is re-fetched. Two things stay per surface, on purpose:
the copy (the same decision is "Resume download" under a full-width primary
and "Resume" inside a picker row, so the projection carries the action and
not the sentence), and whether a blocked offer is dimmed or withheld — the
picker withholds it per
[ADR 0007](../docs/decisions/0007-supported-device-policy.md),
Settings dims it and prints the reason in its own order, because an unresolved
repository is the more specific problem there. Only the busy slot's sentence
is shared; a second copy of the rest would be copy nobody reads.

- `ChatController`: authoritative chats and active selection for the live
  session, with an orthogonal recovery notice when durability falls behind.
  `ChatHistoryRepository` commits its versioned, atomic JSON snapshots; a failed
  write never rolls back or blocks the live conversation.
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
  `app.golem/storage` platform channel. The seam is identity-aware:
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

The app includes the launch failure pane, empty chat with starter chips,
markdown transcript with syntax-highlighted code cards, reasoning and answer
streaming (a pulsing dot until the first token, then a live generating pill),
stop and failure recovery with the ephemeral stopped-tokens caption, message
actions (copy, regenerate,
branch-from-here, share, delete), edit-and-truncate, the sectioned edge-swipe
conversation drawer with pinning and a storage meter that frames Golem's
usage against the free space left (the two figures Settings ▸ Storage leads
with), full-screen cross-chat
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
cache with per-model delete and a cache clear. That screen's promise that
Golem sends no analytics is load-bearing: the app ships no crash reporter or
telemetry of any kind, and relies on Play vitals plus Apple's opt-in crash
reports instead — the trade, and what it costs, is recorded in
[ADR 0011](../docs/decisions/0011-crash-visibility.md). A resolved custom
repository
downloads, verifies, and activates through the same paths as a pinned one; the
fake simulates the whole flow, and an unresolved entry still refuses to download
because its file list is synthesized. What a resolution is allowed to trust,
and the five bounds on reading a stranger's server, are recorded in
[ADR 0014](../docs/decisions/0014-hub-read-client.md).

Assistant messages render a scoped markdown subset (paragraphs, emphasis,
inline code, one-level lists, fenced code with a fixed dark card in both
themes) through `features/chat/widgets/markdown/`; parsing is memoized per
message so only the streaming bubble re-parses. Nothing marks the tail of a
streamed answer — no caret. A caret is a terminal's convention, and the one
that shipped had to be dropped onto a line of its own whenever the answer
ended in a list or a code card, which left an empty bubble holding a floating
blue rectangle (#147). Before the first token the bubble carries one pulsing
accent dot; after it there is nothing but the text.

A streamed answer's opening is provisional for a moment. Gemma starts a turn on
the visible channel and only then labels the run as reasoning, at which point
the broker retracts what it already published (`AnswerResetEvent`,
`broker/gemma4_chat_template.dart`). The bubble therefore holds a streaming
answer's first text for 220 ms and paints it only once it has survived, so a
retracted opening never reaches the transcript and the dot stays put through
prompt processing and thinking alike. A settled message paints at once.

The transcript holds still while an answer streams. On send, the question the
reader just asked is anchored: a trailing spacer takes up the viewport
remainder below the turn, which makes the end of the scrollable *be* the
anchored position, so the one instruction "go to the end" both holds the
question at the top and, once the turn outgrows the screen and the spacer is
spent, follows the tail. The spacer exists only for a turn started in this
session — an opened, switched-to, or restored conversation renders with none —
and the anchor is measured from the question's own render box after each
frame, never persisted. Following detaches on any upward drag and is handed
back only when the reader themselves comes to rest at the end or taps
`jump-to-latest`; content growth and programmatic jumps never re-attach it.
Free text selection is deliberately absent — copy actions cover it on both
chromes. Toasts are the
chrome layer's `showGolemToast` (iOS pill / Android bar, no actions).

The per-chat model selection persists on the conversation (`modelKey`) and a
real engine honors it: the next send unloads and loads the chosen artifact
through the residency owner. Because the **engine** is a build-time composition
(`auto` is MLX on iOS and llama.cpp/GGUF on Android/macOS), only artifacts that engine can load *and*
that are installed may be chosen — so every label may name the choice
immediately without promising weights the next send would refuse. Sampling,
response style, and capability all follow the chosen model's profile, not the
build's boot profile.

What the sheet *says* about that choice is decided in
`features/chat/model_choice.dart`, a pure policy the widget only paints
(#79, `../docs/decisions/0008-model-presentation.md`). A row leads with the
model's name, its size on disk, whether it reads pictures, and a decode rate
**only where a generation measured one** — labelled `simulated` under the fake,
never "on this phone" — over one sentence on what the model is for
(`ModelCatalogEntry.summary`, declared beside the pins in
`lib/broker/model_catalog.dart`). The exact artifact — `GGUF · Q4_0 ·
<repository>` — appears only under **Advanced mode**, which is why display
names no longer carry a quantization and two entries of one family may share
one; the format token is appended only when two rows on screen share a name.

One row carries a `RECOMMENDED` badge and the reason, read from the artifact
`resolveBackendPolicy` already resolved rather than from a second reading of
the device rule, so the badge and the model that loads cannot disagree. A
refused device is recommended nothing.

A row that is not installed is not inert: it offers `Download · <size>`, then
progress with Pause, then Resume or Retry, through the same `ModelController`
methods Settings drives — cancel and delete stay in Settings. An artifact that
is installed but built for the other engine is listed last with copy naming the
engine this build runs, rather than vanishing; what is neither installed nor
loadable stays out but is counted. A whole-sheet refusal — an unsupported
device, or an operator `GOLEM_MODEL_PATH`, which names the file the build pins
because a sideload has no catalog key to switch back to — is stated once in the
footnote while each row says only that it is refused.

Stable keys/semantics preserve the native automation vocabulary. The most useful
identifiers are `launch-splash`, `chat-composer`, `send-button`, `stop-button`,
`reasoning-toggle`, `reasoning-card-header` (the transcript card's own
disclosure, which reports Expanded/Collapsed as its semantic value; cards
arrive collapsed and, while live, show a three-line `reasoning-peek` that is
excluded from semantics),
`composer-attach`, `composer-model-chip`,
`starter-chip-<name>`, `typing-indicator` (the pre-token dot),
`generating-pill`, `stopped-caption`,
`message-copy-<id>`, `message-regenerate-<id>`, `message-share-<id>`,
`message-menu-<id>` plus `menu-message-{copy,regenerate,branch,share,delete}`,
`code-block`/`code-copy`, `attach-sheet` plus
`attach-{photo-library,take-photo,files}`, `composer-attachments` plus
`composer-attachment-remove-<index>`, `model-picker-sheet`,
`model-picker-<catalogKey>` (the selection target — the row's card is not
itself a button, so a download inside it cannot swallow the tap),
`model-picker-download-<catalogKey>` (Download / Resume / Retry),
`model-picker-pause-<catalogKey>`,
`model-picker-artifact-<catalogKey>` (Advanced mode only),
`model-picker-manage`, `golem-toast`,
`open-drawer`, `drawer-search-button`, `new-chat-drawer`,
`conversation-<id>`, `conversation-menu-<id>` plus
`menu-{pin-toggle,rename,share-transcript,delete}`, `storage-meter`,
`search-field`, `search-cancel`, `search-results`, `search-result-<id>`,
`search-empty`, `rename-sheet`, `rename-field`, `rename-counter`,
`confirm-delete`, `open-settings`,
`model-attribution-row`, `open-source-licenses-row`, `licenses-list`,
`license-<name>` plus `license-text-<name>`,
`settings-{model,style,system-prompt,appearance,privacy,storage}-row`,
`advanced-mode-switch`, `about-row`, `about-sheet`, `about-license`
(the sheet's license line, which opens the source repository),
`models-tab-{all,installed}`, `model-card-<key>`, `model-status-<key>`,
`model-download-<key>`, `model-pause-<key>`, `model-cancel-<key>`,
`model-progress-<key>` (the download bar, whose percentage is a semantic
value because the bar itself paints one and says none),
`model-delete-<key>`, `confirm-model-delete` (catalog keys: `gemma4-mlx`,
`gemma4-gguf`, `qwen35-2b-mlx`, `qwen35-2b-gguf`, `qwen35-mlx`, `qwen35-gguf`,
plus derived `custom-<repository-slug>` entries),
`custom-repo-{engine-mlx,engine-gguf,field,revision,resolve,add,error,detail}`
(`resolve` reads the repository, `add` commits what it found, and `add` only
exists once a resolution is on screen), `download-active-model`
(the chat failure banner's consent CTA when a real backend's model is not
downloaded yet), `device-unsupported-notice`,
`model-device-refusal-<key>` and `runtime-device-refusal` (the
supported-device refusals, which replace the download button and the runtime
toggle rather than disabling them), `style-{precise,balanced,creative}`,
`gen-temperature-<profile>`, `gen-top-p-<profile>`,
`gen-top-k-<profile>`, `gen-max-tokens-<profile>` and
`gen-context-<profile>` (steppers expose `-minus`/`-plus` suffixed
buttons; the sampling card edits the active profile),
`gen-reset-<profile>` (profile keys: `gemma4`, `qwen35`),
`system-prompt-field`, `system-prompt-reset`,
`theme-{system,light,dark}`, `text-scale-slider` and the `text-size-control`
node that names it,
`toggle-{metrics,reasoning,haptics,save-history}`, `confirm-history-off`,
`export-chats`, `delete-all-chats`, `confirm-delete-all`, `storage-bar`,
`storage-model-<key>`, `storage-delete-<key>`, `clear-cache`,
`runtime-toggle-button`,
`open-benchmark`, `benchmark-case-picker`, `benchmark-phase-picker`,
`benchmark-run-button`, `benchmark-stop-button`, and `benchmark-export-button`.
The benchmark keys, route, repository, and prompt assets exist only in `qa`
and `dev`; production does not register or bundle that internal surface.

Launch failure is injectable at compile time:

```sh
flutter run --flavor qa --dart-define=GOLEM_LAUNCH_FAILURES=1
```

`GOLEM_LAUNCH_FAILURES=<n>` makes the first n **real** launch compositions
throw, so one process demonstrates the failure pane, Try again, and recovery
(`../docs/decisions/0006-launch-bootstrap.md`). There is no Flutter splash
otherwise: the first frame waits for the composition, so a launch goes from the
native launch screen straight to the shell, with no hold, progress bar, or
spinner in between (`../docs/decisions/0018-no-splash-wait.md`). The injector
is identity-gated: `qa` and `dev` retain it in debug and release builds, while
production ignores the define.

## Generate and verify

Through the pinned SDK — `.fvmrc` names it, `fvm install` materialises it, and
the repo README's Toolchain section covers setup. Every `flutter`/`dart`
command below and elsewhere in this file assumes it, whether or not the `fvm`
prefix is written out.

```sh
fvm flutter pub get
fvm dart run build_runner build
fvm dart run tool/prepare_launcher.dart
fvm dart run flutter_launcher_icons
fvm dart run flutter_native_splash:create
fvm dart run tool/prepare_ios_launch.dart
fvm dart format --output=none --set-exit-if-changed .
fvm flutter analyze
fvm flutter test
(cd .. && fvm dart run tool/check_inferno_imports.dart)
(cd .. && fvm dart run tool/check_feature_imports.dart)
(cd .. && fvm dart run tool/check_toolchain.dart)
(cd ../packages/inferno && fvm dart test)
```

Every `flutter run`, `flutter build`, and host `flutter test` executes the
Inferno build hooks, whichever flavor is named: the hook's only gate is that
code assets are being built, and `package:inferno` is an unconditional
dependency. The `qa` flavor is fake at runtime, never at build time — its
macOS bundle still needs the staged MLX resources the hook produces. Native
assets are on by default in the pinned SDK, so no `flutter config` switch is
needed. Android builds additionally need NDK
`29.0.14206865` (`sdkmanager "ndk;29.0.14206865"`) — the hook refuses any
other revision, because Flutter otherwise picks whichever NDK is newest on
the machine and the compiler behind every shipped kernel changes with it.

### The Play release artifact

```sh
flutter build appbundle --release --flavor production
flutter build apk --release --flavor production   # sideload/emulator copy
(cd .. && dart run tool/check_android_packaging.dart)
```

`--flavor production` is not optional; `default-flavor` is `dev`. Every Android
build carries `arm64-v8a` alone (`defaultConfig.ndk.abiFilters`), so
`--target-platform android-arm64` changes nothing about what ships and only
saves two llama.cpp cross-compiles — and no Android emulator below arm64 will
install any flavor.

`check_android_packaging.dart` is the release-time gate for Play's
native-library rules: 16 KB page alignment on every 64-bit library, the
uncompressed page-aligned packaging behind it, the ABI set, the
crash-symbolication uploads Play warns about when they are missing, and the
absence of packaged model weights. It reads the built artifact rather than the
build files, which is the only way to catch a toolchain default changing
underneath. Run it after any llama.cpp or NDK pin bump; the reasoning is in
[ADR 0010](../docs/decisions/0010-android-native-packaging.md).

The pubspec declares `uses-material-design: true` even though no app surface
draws a Material glyph: `go_router` and `background_downloader` carry
MaterialIcons codepoints the icon tree-shaker cannot prove unreachable, so
without the declaration every release build warned about a font nothing had
declared. Declaring it costs 1,324 bytes after shaking and silences the
warning; `platform_assets_test.dart` keeps it, and keeps `lib/` free of any
`material.dart` import.

`dart run tool/prepare_launcher.dart` derives every flavor's Android
launcher inputs from the tracked native artwork in `assets/source/`
(`golem_icon_<flavor>_1024.png`), sampling each adaptive-icon gradient from
the artwork itself, and writes the per-flavor macOS Dock iconsets
(`macos/Runner/Assets.xcassets/AppIcon-<flavor>.appiconset`) directly —
Apple-style rounded squares on a transparent margin — because
flutter_launcher_icons can only emit one fixed macOS catalog. One
`dart run flutter_launcher_icons` invocation then generates the three phone
flavors from the `flutter_launcher_icons-<flavor>.yaml` configs (their
presence makes the tool ignore any pubspec block): the
`AppIcon-<flavor>.appiconset` catalogs on iOS and the
`android/app/src/<flavor>/res` source sets on Android. A macOS-only flavor
(`lab`) gets its Dock iconset and in-app tile from `prepare_launcher.dart`
alone and has no launcher-icons config, because there is no phone product
flavor for one to feed. The QA artwork is the red source desaturated —
tile, gradient and tinted mascot to grey, sparkle, ring and matte untouched
— and the lab carries the red artwork unchanged (ADR 0021). The launch
screen is deliberately identical for every flavor.

The launch failure pane uses mascot-only transparent artwork over a Golem navy
(`#060D1F`) surface, without an app-icon tile, frame, or backing panel. The
launcher-icon matte deliberately stays on the older `#0F1524` navy — icon
artwork is regenerated only by an artwork change. The
native iOS launch screen is the hand-owned, solid-navy
`GolemLaunchScreen.storyboard` with no image: the iOS 26 launch-snapshot
renderer draws storyboard launch images at the wrong scale and flattens their
transparency to white — and a launch carries no artwork anyway: the navy
holds only until the composed shell is the first Flutter frame
(`../docs/decisions/0018-no-splash-wait.md`). `flutter_native_splash` runs with `ios: false` and
`tool/prepare_ios_launch.dart` guards the wiring.
`platform_assets_test.dart` guards the navy image-free storyboard, splash
alpha, mascot transparency, the Android-only navy-matted launcher icon, and
the unmodified source artwork used for the iOS icon. Both launcher sources
derive from the tracked artwork in `assets/source/`.

User-facing copy uses Flutter's source-generated ARB/gen-l10n path. English is
the source and fallback; Polish, neutral Latin American Spanish, Brazilian
Portuguese, Japanese, Indonesian, Hindi, neutral international French,
Vietnamese, Turkish, Korean, and Modern Standard Arabic are complete and
selectable from Settings → Language alongside System default. Explicit choices
are stored in app preferences. See `../docs/localization.md` for each language's
terminology, exclusions, required Portuguese fallback mirror, plural rules,
and the checklist future agents follow when adding another language.

Golden tests use the iPhone 17 logical viewport (402 × 874). Every surface
records light and dark under iOS chrome, and the chrome-visible surfaces
(chat, Settings, Benchmark) add an `-android` light variant — the platform
axis rides `TargetPlatformVariant` in `test/support/harness.dart` (widget
tests report android by default, so goldens pin the platform explicitly).
Sheets (rename, model picker, attach) record android in both appearances:
the drag handle is the android-only painted element whose tint differs.
They cover empty/populated chat, reasoning, the markdown
transcript, search, the composer sheets, the sectioned conversation
drawer, rename overlay, every settings surface (root, models, response
style, appearance, privacy, storage, system prompt, model attribution, and
the declared open-source licenses list, with its kind labels — with iOS-only
Advanced variants for the root, custom repository, and sampling states),
Benchmark, and both unsupported-device surfaces (chat and models, iOS-only
in light and dark). The model picker records twice: the simulated catalog
under both chromes (recommended-and-selected, mid-download, and offered
downloads in one seed), and `model-picker-real-<brightness>` under a real
llama build with Advanced on, which is the only way to record the states an
engine composition produces — the recommendation's device-tier reason, an
installed artifact of the other engine explaining itself, the count of what
is not listed, and the artifact line. The widget suite also runs Flutter's
tap-target, semantic-label, and contrast checks. The target check runs under
**both** chromes against the minimum the running platform promises — 48 on
Android, 44 on iOS, the same answer `GolemChrome.minimumTapTarget` gives
widgets — because asserting the iOS guideline alone left the shared chrome 4dp
short on Android for as long as it existed (#118). Every settings surface is
enrolled alongside chat, the drawer, and the legal screens, which is why
segments and switches carry full targets and footnotes use
muted rather than tertiary ink. One class the guideline cannot see: it skips
any node touching the view boundary, so the navigation bar's own controls are
never measured by it — and they are held to 44 regardless, because
`CupertinoNavigationBar` fixes its content slot at that height. Every major surface — chat empty, seeded and
with a code card, the open drawer, the composer's sheets, and every settings
screen — additionally pumps at a 1.6× text scale, because the app's own slider
reaches 1.3× and the platform factor multiplies on top of it; an overflow
throws, so a clean pump is the assertion.

What a screen reader is told is asserted separately in
`test/accessibility_test.dart`, none of it being visible to a golden: that a
toast and each edge of a generation are announced, that the busy composer reads
as read-only rather than disabled, and that switches, the text-size slider, the
reasoning disclosure, a download's progress, and each message are named exactly
once.

## What earns a test

The suite is audited rather than trusted (#120). Two instruments answer the
question a coverage percentage cannot:

```sh
# Both live at the repo root, so both are run from there.
(cd .. && dart run tool/test_coverage_map.dart)  # what each file covers alone
(cd .. && dart run tool/check_goldens.dart)      # every golden is still compared
```

`test_coverage_map.dart` runs the suite one file at a time and reports
`unique(F)` — the `lib` lines that file executes and every other file leaves at
zero — plus the three files it overlaps most, so a consolidation can be aimed.
Read its output the way it is written: **`unique(F) = 0` is a candidate, never a
verdict.** Two tests can execute identical lines and assert different things, and
the audit found that is usually what is happening here. The verdict comes from
breaking the behavior a file claims and seeing whether anything else fails —
`provider_policy_test.dart` covers nothing uniquely and still earns its place,
because dropping one `retry: noRetry` fails 32 suites and it is the one that
names which provider lost it.

The rules a new test is held to:

- **One behavior, one owner file.** Add to the file that owns the surface. The
  cross-cutting sweeps — `widget_and_golden_test.dart`, `accessibility_test.dart`,
  `localization_test.dart`, `bidi_presentation_test.dart` — enrol surfaces
  wholesale by lens, and that overlap is deliberate: they ask a different
  question of the same screen.
- **It must be able to fail.** Break the thing it names and watch it go red
  before committing. A test that passes either way is worse than no test,
  because it reads as coverage.
- **Say what it catches that nothing else does.** Duplication is not
  automatically waste — a unit test that pins an algebra keeps the failure
  locus small when the end-to-end controller test would also have caught it —
  but the second guard should be a choice, not an accident.
- **Cover the decision, not the plumbing.** Where a rule can be pulled out of a
  plugin-bound adapter it is (`artifact_adoption_policy.dart`,
  `artifact_task_metadata.dart`), and the adapter's remaining shell is left
  uncovered on purpose rather than wrapped in a mock of someone else's plugin.
- **Delete goldens by evidence.** Golden names are interpolated, so
  `check_goldens.dart` is the only way to know an image is still reached.

`tool/mutation/decision_logic.xml` holds the bounded mutation set — the files
that decide things, paired with the suites that reach them. It is the guard
against tests that cannot fail, and is re-run when that set changes.

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
flavor right after building it; the three phone flavors coexist side by side:

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
on iOS. In `qa` and `dev`, `INFERNO_METRICS` lines appear on the `flutter run`
console, or on stdout when launching the built binary directly
(`build/macos/Build/Products/Release-qa/golem_flutter.app/Contents/MacOS/golem_flutter`).
The same identity gate controls `INFERNO_FAILURE` and `INFERNO_PROBE`;
production emits none of the three Dart diagnostic prefixes, regardless of
build mode. Native engine error transport remains unchanged.

For cross-device determinism probes, build with
`--dart-define=GOLEM_SAMPLING_SEED=<n>`: every completed generation then
logs one `INFERNO_PROBE` line hashing the raw pre-parser output, and
`integration_test/real_backend_probe_test.dart` drives one seeded
generation through the chat UI with a fixed prompt. Findings live in
`../docs/notes/determinism-probe.md`.

## Golem Model Lab (macOS)

The fourth flavor is the bench for the models the phone flavors ship, and it
exists on macOS only (ADR 0021):

```sh
flutter run -d macos --flavor lab          # or: flutter build macos --flavor lab
```

It opens landscape at 1440 × 900, clamped to the screen and resizable down
to 1000 × 640, and remembers that frame separately from the consumer window
(`GolemWindowProfile` in the built Info.plist, filled from the
`GOLEM_WINDOW_PROFILE` build setting). It composes the real engines like
`dev` and shares the consumer app's repositories, but none of its routes: no
first-run gate, no chat, and nothing downloads because the lab opened.

Its container is its own. Application support is bundle-scoped everywhere,
but on this unsandboxed target `getApplicationDocumentsDirectory()` is the
real `~/Documents`, shared by every flavor, so the lab keeps `Documents`
under its support directory and its downloader lands files there too:

```text
~/Library/Application Support/app.golem.lab/Documents/models/<catalog-key>/
```

Provision a fetched artifact without a download — hard links from
`../packages/inferno/build/models/` are instant on the same volume — and the
lab's Download verifies it in place. Fetch by key first
(`dart run tool/fetch_model.dart qwen-gguf` in `../packages/inferno`; the tool
writes every file of an artifact, projector included, under
`build/models/<repository name>/`), then link:

```sh
LAB="$HOME/Library/Application Support/app.golem.lab/Documents/models"
M=../packages/inferno/build/models/Qwen3.5-4B-qat-GGUF
mkdir -p "$LAB/qwen35-gguf"
ln "$M"/Qwen3.5-4B-qat-Q4_0.gguf "$M"/Qwen3.5-4B.mmproj-q8_0.gguf "$LAB/qwen35-gguf/"
```

(`../packages/inferno/lib/src/model_manifest.dart` is the authority on file
names; a projector fetched separately through `qwen-mmproj` lives under its
own repository name instead.) The gated proof that the plugin's destination and the repository's
agree runs on a lab build against exactly that layout:

```sh
flutter test integration_test/lab_storage_test.dart -d macos --flavor lab \
  --dart-define=GOLEM_LAB_STORAGE=true
```

The lab's Dart never reaches a store build: `kLabBuild` is a compile-time
constant and the lab root is referenced only behind it. The proof reads what
the compiler kept — build the production flavor with size analysis and run
the checker over the retained-object profile (`snapshot.<arch>.json`; on a
flavored macOS build the tool exits 1 *after* writing it, looking for an
unflavored product path, and the profile is complete):

```sh
rm -rf build/size-macos build/size-android build/size-ios   # never read a stale profile
flutter build macos --release --flavor production --analyze-size \
  --code-size-directory=build/size-macos
flutter build apk --release --flavor production --analyze-size \
  --target-platform android-arm64 --code-size-directory=build/size-android
flutter build ios --release --no-codesign --flavor production --analyze-size \
  --code-size-directory=build/size-ios
(cd .. && dart run tool/check_lab_exclusion.dart \
  app/build/size-macos app/build/size-android app/build/size-ios)
```

`integration_test/release_hygiene_test.dart` takes `GOLEM_EXPECTED_LAB=true`
on a lab build and expects it false on every other flavor.

## Real-model acceptance (device)

`integration_test/device_acceptance_test.dart` runs one device/engine cell end
to end — install (verifying bytes already in the container, or downloading them
for real), a text turn, a per-chat switch to a second artifact and a turn on it,
an image turn, and history read back off disk:

```sh
flutter test integration_test/device_acceptance_test.dart -d <device> \
  --flavor qa --no-uninstall --dart-define=GOLEM_INFERENCE_BACKEND=auto \
  --dart-define=GOLEM_DEVICE_ACCEPTANCE=true \
  --dart-define=GOLEM_ACCEPT_PRIMARY=gemma4-mlx \
  --dart-define=GOLEM_ACCEPT_SECONDARY=qwen35-2b-mlx \
  --dart-define=GOLEM_ACCEPT_IMAGE=true
```

Use the corresponding `gemma4-gguf` / `qwen35-2b-gguf` keys on Android.

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
tool/device_install.sh ios qa <devicectl-UUID>       # from the repo root
tool/device_install.sh android qa <adb-serial>
tool/device_install.sh ios production <UUID> --dart-define=GOLEM_INFERENCE_BACKEND=auto
```

The script upgrades in place (`devicectl device install app` / `adb install
-r`), and prints the commit it stamped into the build; Settings ▸ About shows
the same stamp on the phone.

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

One more operational fact: a qa/dev release build's `debugPrint` is
os_log-privacy-redacted in an `ios syslog` capture, so read `GOLEM_CELL` and
`INFERNO_METRICS` from the test harness console instead. Results live in
`../docs/real-model-matrix.md`.

## Download throughput bench

`integration_test/download_bench_test.dart` measures sustained download
throughput through the `ArtifactFileDownloader` seam — the production plugin
transport (`current`), a `ParallelDownloadTask` prototype (`parallelN`), and
an in-process `dart:io` transport (`httpN`, the curl stand-in on iOS) — in
interleaved time-capped windows against one pinned artifact:

```sh
flutter test integration_test/download_bench_test.dart -d <device> \
  --flavor qa --no-uninstall --dart-define=GOLEM_DOWNLOAD_BENCH=true
```

Optional defines: `GOLEM_BENCH_ARTIFACT` (default `qwen35-2b-gguf`),
`GOLEM_BENCH_WINDOW_S` (45), `GOLEM_BENCH_ROUNDS` (3),
`GOLEM_BENCH_TRANSPORTS` (`current,parallel4,http1,http4`),
`GOLEM_BENCH_COMPLETE=<transport>` (one full download, verified against the
pinned size and SHA-256), `GOLEM_BENCH_BACKGROUND=true` (device only; the HUD
asks for the app to be backgrounded and the run reports the average across the
suspension gap). Results are `DOWNLOAD_BENCH` key=value lines on the harness
console; bytes land in a throwaway `bench-<key>` directory that teardown
deletes. The host-side baselines (`curl`, `wget`, URLSession) live in
`../tool/bench_host_download.dart` and `../tool/urlsession_bench.swift`;
recorded results in `../docs/notes/download-throughput.md`. CI never sets the
defines, so the instrument self-skips there and downloads nothing.

## Model evaluation harness (macOS)

`integration_test/model_eval_test.dart` turns model and quantization
decisions into recorded evidence: it runs the fixed prompt set in
`lib/features/eval/domain/eval_spec.dart` against every requested
artifact × engine combo, scores the parsed answer channel with
deterministic checks, captures full broker metrics (decode/prompt tok/s,
time to first token, peak footprint) under fixed seeds, tags them with the
timing-semantics version the engines reported and refuses to publish a report
that mixes two (`../docs/decisions/0020-generation-timing-semantics.md`), and
writes `report.json` plus a committable `report.md` per run. Fetch the pinned artifacts first
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

## License

The app is `AGPL-3.0-only`, © 2026 Jan Slominski — see the repository
[`LICENSE`](../LICENSE) and the root README's License section. The Golem
name, mascot, and launcher artwork are reserved
([`TRADEMARKS.md`](../TRADEMARKS.md)); a distributed fork rebrands first.
