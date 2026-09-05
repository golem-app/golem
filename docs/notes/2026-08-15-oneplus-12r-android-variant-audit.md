# OnePlus 12R Android variant QA — 2026-08-15

## Purpose and decision boundary

This is a physical-device QA audit of the Flutter Android app at `621fad6` on
the branch `qa/oneplus12r-android-variant-audit`. It creates no product ticket,
changes no application behavior, and makes no release decision by itself.

The audit used Mobile MCP for every device interaction and only the local
physical OnePlus 12R (CPH2609, Android 16, 1080 × 2376). No emulator,
simulator, iOS device, remote device, or direct ADB interaction was used.
Evidence excludes device identifiers, account data, IP addresses, credentials,
local filesystem paths, model files, and pre-existing chat contents.

## Sources and environment

- Repository behavior and identifiers: `app/README.md`, current source, ADRs,
  existing integration journeys, and the GOLEM.app organization project.
- Additional acceptance guidance: Flutter Architecture Handbook v5.0,
  explicitly requested for this audit. The user instruction makes it
  applicable even though the maintainer-held reference index labels it
  candidate guidance.
- External documentation: official Flutter build-mode/flavor guidance and
  official Android 48 dp touch-target guidance, both queried through Context7.
- Board review: 76 project items reviewed on 2026-08-15. #116 tracks retirement
  of the legacy `app.golem.flutter` identity. #114 (parallel ranged downloads)
  is still an unrefined Inbox item and was not treated as shipping behavior.
- The machine's global Flutter 3.47.0 / Dart 3.13.0 could not resolve this
  repository because its SDK localization package requires `intl ^0.20.3`
  while the repository pins `intl 0.20.2`. All reported builds and automated
  checks therefore used an isolated, unmodified Flutter 3.44.9 / Dart 3.12.2
  checkout, matching the app's 3.44.x baseline. OpenJDK was 19.0.1.
- The device was available locally before testing, reported no crash records,
  and already held all three GOLEM application identities.

## Result summary

All nine installable Android flavor/mode combinations built, installed, and
launched on the physical phone. Every cell passed its mode smoke; six product
or QA-instrumentation defects and two lower-confidence observations remain.
The production release AAB and APK also passed the repository's native-library
packaging inspection.

`Pass with findings` means the variant was usable and stable for the exercised
journey, while one or more findings below apply. It does not mean the findings
are release-acceptable.

| Flavor | Debug | Profile | Release |
| --- | --- | --- | --- |
| `qa` / `app.golem.qa` | Pass with findings | Pass with findings | Pass with findings |
| `dev` / `app.golem.dev` | Pass with findings | Pass with findings | Pass with findings |
| `production` / `app.golem` | Pass with findings | Pass with findings | Pass with findings |

For each cell the APK was built for arm64, installed through Mobile MCP,
launched, checked for the expected identity/composition and retained state,
rotated portrait/landscape/portrait, backgrounded and resumed, and relaunched.
The final device-wide Mobile MCP crash review remained empty.

## Functional coverage

| Area | Result | Evidence |
| --- | --- | --- |
| Clean install and first run | Pass with finding F1 | QA and dev were uninstalled before their debug runs. Splash, disclaimer, explicit consent, decline, model choice, progress, verification, and chat unlock were exercised. Dev correctly recommended GGUF; QA did not. |
| Upgrade and persistence | Pass with finding F5 | QA and dev state survived debug → profile → release. Production upgraded over an older installed production build: old chats survived; the obsolete 2.62 GB model was not admitted by the new catalog; a new pinned model was required and verified. |
| Chat essentials | Pass | Starters, keyboard/insets, compose/send, streamed response, reasoning state, real text inference, stop generation, injected engine failure, discard recovery, context exhaustion, and new-chat recovery were exercised. |
| Message lifecycle | Pass | Copy, native share entry/exit, regenerate/action availability, branch, and confirmed deletion of an audit-only chat were exercised. |
| Conversation management | Pass | Drawer, new chat, search, result opening, pin, rename, transcript share entry/exit, action menu, and delete confirmation were exercised. |
| Model choice and downloads | Pass with findings F1, F2, F5 and observation O1 | Full catalog, recommended state, engine exclusions, installed state, pause/resume, foreground/background continuation, cancel surface, verification, per-chat switching, and persisted downloads were covered. |
| Image input | Pass | Android DocumentsUI opened and cancelled cleanly. A real image was attached to dev Gemma, sent, and described locally at 14.0 tok/s. |
| Settings | Pass with finding F3 | Model, response style, Advanced mode, custom system prompt, appearance, language, privacy, storage, and System language/theme reset were exercised. |
| Legal and identity | Pass | Attribution revisions, model repositories, offline license text, open-source licenses, and About copy were inspected. Identities were `Golem QA · app.golem.qa`, `Golem Dev · app.golem.dev`, and `Golem · app.golem`. |
| Internal tools | Pass | Benchmark was present and exportable in QA/dev and absent from production. A simulated QA benchmark completed and opened Android's native share surface. |
| Localization | Pass | English baseline, long Latin Spanish, Japanese, Korean, and Arabic RTL were inspected at 130% app text. Locale persistence and System reset passed. No missing glyph, wrong Han-form, or clipped primary control was observed. |
| Accessibility and layout | Pass with findings F3, F4 and observation O2 | Mobile semantics, light/dark, 130% app text, keyboard, safe areas, portrait and landscape were inspected. Spanish expanded rows correctly; Korean wrapped without clipping; Arabic mirrored navigation and layout correctly. |
| Lifecycle and offline | Pass | Active downloads survived background/resume without reset or duplication. Dev release answered locally with Wi-Fi off on the no-SIM phone, after which Wi-Fi was restored and reconnected. Terminate/relaunch preserved state. |
| Real model path | Pass | Dev Gemma 4 E2B GGUF (3.18 GB) and production Qwen 3.5 2B GGUF (1.58 GB) completed exact-file verification, loaded, answered correctly, accepted image input, and supported cancellation. |
| Storage and privacy | Pass | Storage breakdown, native channel data, cache clearing, save-history confirmation/cancel, chat export share entry, and delete-all confirmation/cancel were exercised. Cache cleared without deleting a model. |
| Native integration | Pass | File picker, share sheet, storage channel, download service, lifecycle, and release-mode local inference showed no missing-plugin or native-asset failure. |
| Stability | Pass | Mobile MCP reported no crash records after the complete campaign. No blank frame or unrecoverable navigation state was observed. |
| Storage pressure | Not destructively simulated | The phone retained ample free space. Low-space UI copy and required headroom were inspected, but filling a shared physical phone solely to force ENOSPC was not proportionate. |

## Build and packaging evidence

- APKs built and installed: QA, dev, and production in debug, profile, and
  release (nine arm64 APKs total).
- Profile APKs were 42.1 MB and release APKs were 30.3 MB as reported by
  Flutter; debug APKs also built successfully.
- Production release AAB built successfully at 28.8 MB as reported by Flutter.
- `tool/check_android_packaging.dart` passed both production release artifacts:
  only `arm64-v8a`; all four native libraries have compliant 16 KB-or-greater
  load alignment; APK libraries are stored/aligned correctly; the bundle asks
  Play for 16 KB-aligned uncompressed libraries; native symbols and the R8 map
  are present; no model weight is packaged.
- No production golden was modified. Build products and downloaded model files
  are not part of this branch.

## Chronological evidence

### Preparation and QA composition

- `main` was clean and synchronized with `origin/main` at `621fad6` before
  `qa/oneplus12r-android-variant-audit` was created. No issue or project item
  was created.
- The QA clean install showed the full first-run disclaimer and deterministic
  no-network consent. Its fake download verified and unlocked chat.
- QA covered Markdown/code rendering, message actions, branch creation, drawer
  search, pin/rename/share, Settings, attribution/licenses, privacy/storage,
  Benchmark, attachment picker, dark mode, 130% app text, Japanese, Korean,
  Spanish, Arabic RTL, and failure/context recovery.
- QA profile and release were installed over the same state. Both retained
  language, theme, text size, custom system prompt, chats, and model state and
  survived rotation/background/relaunch.

### Dev real-runtime composition

- Dev clean first run recommended Gemma 4 E2B GGUF Q4_K_XL (3.18 GB). Decline
  remained on the model gate.
- The real download paused at 6%, retained 0.20 GB across relaunch, resumed,
  continued in the background, verified each pinned artifact, and finished as
  `Downloaded · 3.18 GB` / `Verified on this device`.
- Main-file throughput varied between roughly 11 and 75 MB/s. The smaller
  secondary artifact spent an extended period near 1.1 MB/s; see O1.
- Real Gemma answered `17 + 24` with `41` at 12.9 tok/s. A long generation was
  stopped immediately without a crash or orphaned assistant turn. A picked
  image was described locally at 14.0 tok/s.
- Dev About truthfully stated `Golem Dev 1.0.0 · app.golem.dev` and the real
  HTTPS-download/local-inference composition. Benchmark was present.
- Profile and release installs retained the verified model and chats. Dev
  release answered `OK` at 11.7 tok/s while Wi-Fi was off and the phone had no
  SIM card.

### Production and release packaging

- Before upgrade, the installed production app had two existing chats and an
  older verified 2.62 GB GGUF artifact. Installing the current production
  debug APK preserved the chats but correctly required a currently pinned
  artifact; the old revision was not falsely accepted as the new model.
- Qwen 3.5 2B GGUF (1.58 GB) was selected, downloaded, and verified. Its main
  artifact reached about 53 MB/s initially; the multi-file sequence verified
  the first artifact before continuing aggregate progress for the second.
- The new production build reopened the retained conversations. New real
  answers were `63` for `9 × 7` at 14.8 tok/s in debug and `11` for `5 + 6` at
  19.6 tok/s in release.
- Production correctly omitted Benchmark and identified itself as
  `Golem 1.0.0 · app.golem` with the real downloader/local-inference statement.
- Production profile and release retained the Qwen model and all chats across
  upgrades, rotation, background/resume, termination, and relaunch.

## Findings

### F1 — Medium — QA recommends an Android-incompatible MLX artifact

- **Affected:** QA clean first run; configuration shared by QA build modes.
- **Reproduction:** uninstall `app.golem.qa`, install QA debug, accept the
  disclaimer, then inspect the featured model and full model chooser.
- **Expected:** the simulated Android product should recommend the Android
  GGUF artifact so QA represents the platform's intended choice.
- **Observed:** Gemma 4 E2B MLX 4-bit (3.58 GB) was featured and marked
  recommended. A clean dev run on the same phone correctly recommended Gemma
  GGUF Q4_K_XL (3.18 GB).
- **Frequency:** 1/1 clean QA run; persisted selection then behaved correctly.
- **Source correlation:** `FakeModelManagementRepository` defaults to
  `gemma4-mlx`, and simulated admission deliberately prefers MLX. This is test
  instrumentation truthfulness, not evidence of a production recommendation
  fault.

### F2 — Medium — QA Qwen 2B response identifies itself as Qwen 4B

- **Affected:** QA deterministic inference with either Qwen artifact whose key
  starts with `qwen35`, including Qwen 3.5 2B.
- **Reproduction:** install/simulate Qwen 3.5 2B, select it for a chat, and send
  a normal prompt.
- **Expected:** the simulated response identifies the selected 2B model, or
  avoids claiming a different model size.
- **Observed:** header and model control said `Qwen 3.5 2B`; response text said
  `Simulated Qwen 3.5 4B here.`
- **Frequency:** 1/1 exercised Qwen 2B generation.
- **Source correlation:** `_profileFor` maps every `qwen35*` key to the 4B name.

### F3 — Medium — every response-style radio announces itself as selected

- **Affected:** all Android variants; response-style accessibility semantics.
- **Reproduction:** open Settings → Response style and inspect the Android
  semantics tree before and after changing the visible selection.
- **Expected:** only the active Precise, Balanced, or Creative option announces
  selected/checked; the other two announce unselected.
- **Observed:** the visual radio state changed correctly, but all three labels
  ended in `selected` in both states.
- **Frequency:** 2/2 inspected states.
- **Source correlation:** `_StyleCard` unconditionally uses the localized
  `selectedOption(...)` string as its semantic label even when `checked` is
  false.

### F4 — Medium — common Android controls are 44 dp, below the 48 dp minimum

- **Affected:** all Android variants; message actions, drawer/new-chat controls,
  composer controls, menus, and other shared chrome.
- **Reproduction:** inspect the source constants and Mobile MCP bounds. Common
  controls were 132 physical pixels on this approximately 3× device, or 44 dp;
  the Back control was 144 pixels, or 48 dp.
- **Expected:** Android interactive targets are at least 48 × 48 dp under the
  current official Android accessibility guidance checked through Context7.
- **Observed:** `GolemSize.hitTarget` is 44 and numerous controls explicitly use
  `Size(44, 44)`. They were operable during this audit but undersized.
- **Frequency:** systematic across the shared widgets inspected.

### F5 — Medium — composer can remain disabled after upgrade model download

- **Affected:** production debug upgrade from an older installed production
  build when a newly pinned model must be downloaded.
- **Reproduction:** upgrade the older production installation, choose Qwen 3.5
  2B, complete both downloads and verification, enter chat, and type a prompt.
- **Expected:** Send becomes enabled as soon as verified onboarding completes.
- **Observed:** the header and model control both showed `Qwen 3.5 2B · on
  device`, but Send remained visibly disabled with non-empty text. Opening the
  model picker and selecting the already-selected Qwen once enabled Send; the
  prompt then answered correctly.
- **Frequency:** 1/1 observed upgrade/download transition; not reproduced on
  later profile/release upgrades. Workaround: reselect the installed model.

### F6 — Low — profile/release builds warn that MaterialIcons is absent

- **Affected:** QA, dev, and production profile/release builds.
- **Reproduction:** build an APK or AAB with tree-shaken icons.
- **Expected:** referenced icon fonts are present or no MaterialIcons codepoint
  is included in the build's icon set.
- **Observed:** every profile/release build warned that MaterialIcons was
  expected but only CupertinoIcons was found. Exercised release UI icons still
  rendered; no missing glyph was seen.
- **Frequency:** all seven tree-shaken artifacts (six APKs and one AAB).
- **Disposition:** build-integrity warning; user-visible impact was not proven.

## Lower-confidence observations

### O1 — secondary model-artifact throughput was much lower than the main file

On the same foreground Wi-Fi session, the dev Gemma main artifact ranged from
roughly 11–75 MB/s while its secondary artifact spent several minutes near
0.9–1.8 MB/s. Production Qwen also verified one artifact before continuing the
aggregate second-file progress. Both downloads completed and hashes verified.
The sample cannot distinguish application scheduling, origin/CDN behavior, and
temporary network conditions, so this is not classified as a defect.

### O2 — some sheet/list rows appear twice in the Android semantics tree

Attachment-source and license rows exposed coincident wrapper and child button
nodes during Mobile MCP inspection. The visible UI and actions were correct.
This may be genuine duplicate semantics or an Android/UIAutomator projection
artifact; a TalkBack pass is required before classifying it.

## Automated verification

All commands used the isolated Flutter 3.44.9 / Dart 3.12.2 SDK:

- `dart format --output=none --set-exit-if-changed .` — pass; 292 files, zero
  changes.
- `dart run tool/check_inferno_imports.dart` — pass.
- `flutter analyze` in `app/` — pass; no issues.
- `dart analyze` in `packages/inferno/` — pass; no issues.
- `flutter test` in `app/` — pass; 935 tests, eight expected opt-in live/model
  fixture skips. Golden tests passed and changed no files.
- `dart test` in `packages/inferno/` — pass; 17 tests, 14 expected model-fixture
  skips. Native build hooks completed; the compiler emitted its existing
  macOS availability and duplicate-library warnings.
- `dart run tool/check_android_packaging.dart` — pass for the production
  release AAB and APK.
- `git diff --check` — pass.

The application source is unchanged, so the handbook's documentation-only
proportionality rule applies to the branch diff. The broader checks above are
supporting evidence for the Android audit, not a claim that the note changes
runtime behavior.

## Final assessment

The Android build is broadly functional across all nine variants on the
physical OnePlus 12R, including real pinned downloads, verification, offline
inference, image input, upgrades, and production release packaging. It is not
finding-free: F3 and F4 are shared accessibility defects, F5 is a production
upgrade usability defect, F1/F2 undermine QA truthfulness, and F6 should be
resolved or explicitly proven harmless before relying on clean release logs.

No fix was made and no ticket was created, per the requested scope. This branch
is a durable, sanitized QA record; the findings need normal board intake before
application code changes begin.

## Dispositions

Recorded when the findings were closed under #118, on the same OnePlus 12R and
on a physical iPhone 17. Every claim below was re-observed on a device unless
it says otherwise.

- **F1 — fixed, and a decision recorded.** The simulation now recommends the
  artifact of the engine this platform's real build composes: iOS MLX, Android
  and macOS GGUF. QA stays deliberately hardware-independent — it still shows
  and runs the whole catalog on any phone — but the engine is a build
  composition, identical for qa and production on one platform, so featuring
  an artifact the build cannot execute made QA a misleading proxy for the
  product. The engine is resolved once, in `resolveBackendPolicy`, and
  admission consumes that answer rather than taking a second one. Verified: the
  Android QA picker's `RECOMMENDED` badge now sits on Gemma 4 E2B · GGUF.
- **F2 — fixed.** The simulated identity comes from
  `ModelCatalogEntry.displayName` instead of a three-case prefix match, and the
  invented decode rate is per family and size. Verified: Qwen 3.5 2B answers
  "Simulated Qwen 3.5 2B here." at 24.6 tok/s, above Gemma's 21.4 rather than
  below it.
- **F3 — fixed.** Only the chosen response style announces itself as selected,
  and the row is named once rather than twice. Verified in both selection
  states. The same audit turned up three surfaces that announced *nothing*
  about selection — the MLX/GGUF engine chips, the first-run model rows, and
  the drawer's active conversation — and those were closed with it.
- **F4 — fixed, with one measured exception.** Shared controls resolve
  `GolemChrome.minimumTapTarget`, and the platform-blind `GolemSize.hitTarget`
  token is gone. Verified at 144 px (48 dp) across message actions, drawer and
  new-chat controls, composer controls, menus, search, code-block chips, and
  the Advanced sampling steppers — which were 38 × 30, below even the iOS
  minimum. **Exception:** the navigation bar's own controls (Back,
  `open-drawer`, `new-chat-header`) measure 48 × 44 dp. `CupertinoNavigationBar`
  fixes its content slot at `kMinInteractiveDimensionCupertino` (44) with no
  parameter to change it, so their height cannot exceed 44 while the Android
  chrome uses that widget. This is unchanged by #118 — the audit's "Back was
  144 pixels" measured its width — and closing it means giving the Android
  chrome its own taller bar, which is a chrome change rather than a hit-box
  one. Not attempted here; it needs its own ticket.
  Note the widget suite cannot catch this class on its own:
  Flutter's tap-target guidelines skip any node touching the view boundary, and
  in the test viewport the bar has no status-bar inset to hold it clear.
- **F5 — fixed.** The composer resolves its gate through `effectiveModelKey`,
  the same resolution `ChatController.send` performs. Verified on Android with
  the setup banner still asking to finish Gemma 4 E2B while Qwen 3.5 2B was
  installed and selected: Send stayed enabled and the turn answered. The
  original production upgrade path was not re-observed — reproducing it needs a
  multi-gigabyte re-download and the deletion of a verified model — so the
  device evidence is the simulated equivalent plus unit coverage of both
  divergence directions.
- **F6 — resolved rather than proven harmless.** `uses-material-design: true`
  declares the font `go_router` and `background_downloader` reference. The
  warning is gone from a fresh QA release build and the font tree-shakes from
  1,645,184 bytes to 1,324. `tool/check_android_packaging.dart` still passes.
- **O1 — unchanged.** Still an observation, still with #114.
- **O2 — not reclassified.** The duplicated sheet and list nodes were not put
  through a TalkBack and VoiceOver pass here, so the observation stands as
  written and is not closed by #118.
