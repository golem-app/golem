# Download lifecycle: what is automated, what is hand-driven, what the platforms refuse

Deliverable of #65. Companion to `docs/decisions/0005-download-lifecycle.md`,
which states the rules; this records how they are proven and where proof is not
obtainable.

## The honest split

Eight cells matter: backgrounding, screen lock, process recreation and
connection loss, on Android and iOS. **Six of them cannot be produced from
inside a `flutter test` instrument**, and that is a property of the platforms
rather than a gap to close later:

- A test cannot background itself or lock the screen.
  `tester.binding.handleAppLifecycleStateChanged` only synthesises the Dart
  callback — it proves the `app.dart` → `ModelController` wiring and nothing
  about `URLSession` or `WorkManager`. It must never be reported as device
  evidence.
- Process recreation kills the VM-service connection, so the harness dies with
  the app and reports the run as failed.
- On iOS, driving the app with WebDriverAgent during a `flutter test` run is
  already known to fail teardown here with a live `SemanticsHandle` (see
  `app/README.md`), so the obvious "have WDA press Home mid-test" plan does not
  work.

So the instrument covers connection loss and reattachment within one process;
everything else is the runbook below, driven against a standalone install.

## The automated part

```sh
flutter test integration_test/download_lifecycle_test.dart -d DEVICE \
  --flavor qa --no-uninstall \
  --dart-define=GOLEM_DOWNLOAD_LIFECYCLE=true
```

`--no-uninstall` is mandatory on a phone (#83) or teardown takes the container's
models with it. The instrument downloads only the sub-25 MB files of a pinned
artifact into a throwaway catalog key (`lifecycle-<key>`) and deletes them in
`tearDown`, so nothing already provisioned is disturbed. Override the artifact
with `--dart-define=GOLEM_LIFECYCLE_ARTIFACT=<catalog key>`.

To exercise the stall probe, drop the network by hand while it runs; the
instrument's `stallTimeout` is shortened to 45 s so a run does not sit for the
production five minutes.

## Runbook — Android (OnePlus 12R)

Install a standalone build; `flutter install` must never be used, because it
uninstalls first.

```sh
flutter build apk --release --flavor qa
adb -s SERIAL install -r build/app/outputs/flutter-apk/app-qa-release.apk
adb -s SERIAL shell am start -n app.golem.qa/app.golem.flutter.MainActivity
```

Start a download from Settings ▸ Models, then:

| Condition | Command |
| --- | --- |
| Backgrounding | `adb -s SERIAL shell input keyevent KEYCODE_HOME`, wait, then the `am start` above |
| Screen lock | `adb -s SERIAL shell input keyevent 26` twice, then `adb -s SERIAL shell wm dismiss-keyguard` |
| Process recreation, recoverable | `adb -s SERIAL shell am kill app.golem.qa` — a background-only kill; the WorkManager job survives and keeps transferring |
| Process recreation, hard | `adb -s SERIAL shell am force-stop app.golem.qa` — the stopped state cancels its jobs until a manual launch. **This is the honest limitation:** the transfer does not continue, and the app must converge to an actionable Paused |
| Connection loss | `adb -s SERIAL shell svc wifi disable` / `enable`; if the OPPO build refuses `svc`, `adb -s SERIAL shell cmd connectivity airplane-mode enable` / `disable` |

Reading state without the harness — which is exactly the process-recreation
case. A release APK is not `run-as`-able; install the debug APK of the same
flavor when the container needs inspecting:

```sh
adb -s SERIAL shell run-as app.golem.qa cat files/flutter-model-v2.json
adb -s SERIAL shell run-as app.golem.qa ls -l app_flutter/models/
adb -s SERIAL shell run-as app.golem.qa ls -l files/   # large partials + the plugin's store
adb -s SERIAL shell run-as app.golem.qa ls -l cache/   # small partials
```

## Runbook — iPhone 17

```sh
flutter build ios --release --flavor qa
xcrun devicectl device install app --device UUID \
  build/ios/iphoneos/Runner.app
```

| Condition | How |
| --- | --- |
| Backgrounding | No CLI exists. The operator presses the home indicator. `xcrun devicectl device process suspend` sends SIGSTOP, which freezes the process rather than transitioning it, and iOS may jetsam a stopped app — it is not backgrounding evidence |
| Screen lock | No CLI. The operator presses the side button. Container reads via `ios fsync` fail while locked; unlock before pulling evidence |
| Process recreation | `ios kill app.golem.qa` (needs `ios tunnel start --userspace`), or SIGKILL via `xcrun devicectl device process signal`. **The user-visible case is the App Switcher swipe, which the plugin documents as stopping all scheduled background downloads outright** — that is the honest iOS limitation and it must be produced by hand |
| Connection loss | Airplane Mode by hand, or a Network Link Conditioner profile from Developer settings. `ios devicestate` is unverified on iOS 26 |

```sh
ios tunnel start --userspace          # keep running
ios fsync --app=app.golem.qa tree --path=.
ios fsync --app=app.golem.qa pull \
  --srcPath="Library/Application Support/flutter-model-v2.json" --dstPath=/tmp/
```

`xcrun devicectl device copy` is unreliable here — no directory sources, no
intermediate-directory creation, and a stale `appDataContainer` after reinstall
cycles. Use `fsync`.

## What was actually run

Recorded rather than inferred, 2026-08-10. "Instrument" means the gated test
above; everything else was hand-driven over `adb`.

### Instrument

| Host | Result |
| --- | --- |
| macOS (`-d macos`) | 3/3, 7m43s |
| OnePlus 12R (`-d 386885ed`, `--no-uninstall`) | 3/3, 7m57s |
| iPhone 17 (`-d 00008150-…`, `--no-uninstall`) | 3/3, 7m51s |

Each run downloads real files from Hugging Face through the shipping stack and
deletes them in `tearDown`. Both phones' provisioned models (`gemma4-gguf`,
`qwen35-2b-gguf`) were verified intact afterwards, and `app.golem` on the iPhone
was never touched.

### Hand-driven, OnePlus 12R

Artifact: `qwen35-gguf` (2.91 GB, 2 files), chosen because it is not installed —
nothing already provisioned was disturbed. Build:
`--flavor qa --dart-define=GOLEM_INFERENCE_BACKEND=auto`, installed with
`adb install -r`. State read straight from the container between steps.

| Condition | Observed |
| --- | --- |
| Backgrounding | `downloading` throughout; 50 → 74 MB while backgrounded, 78 MB after returning |
| Screen lock | `downloading` throughout; 78 → 112 MB while locked, 122 MB after unlocking |
| Process recreation (SIGKILL) | Transfer outlived the process — 139 → 145 MB with no pid. Relaunch reconciled to **`downloading`**, not Paused, and progress continued: 165 MB before the kill, 212 MB after relaunch |
| `am force-stop` | Transfer froze at 103.6 MB. Relaunch resumed **from the partial**, not from zero: 123.5 MB |
| Connection loss | `svc wifi disable` + `svc data disable`: bytes froze at 139.5 MB, phase held `downloading` for the full 2 min observed — correct, the stall probe is deliberately above the plugin's own retry ladder. Restoring the network resumed the transfer |
| Pause | Confirmed by the platform before persisting: `paused` at 289 MB, card reads "Paused at 0.29 GB · Resume Download" |
| Pause across process recreation | SIGKILL + relaunch left it `paused` at 294 MB — no spurious restart |
| Cancel and Discard | `notDownloaded`, 0 bytes, install directory gone, and **zero** `com.bbflight.background_downloader*` staging files left in `files/` or `cache/` |

**`am kill` does not work here.** It is refused while a transfer runs, because
the download worker holds the process above cached importance — the pid survives
the command. Use SIGKILL via `run-as app.golem.qa kill -9 <pid>` to produce a
genuine process recreation on this device.

### Found by this run, and fixed

Reporting progress from resume data alone made a live 145 MB transfer read as
50 MB after a process kill, and again as 78 MB when the network came back — a
progress bar that jumps backwards reads as lost work. Resume data records where
a *resumed* transfer would restart and is frozen at the last pause; the tracking
record follows a live one. The snapshot now takes the larger of the two, which
is what the 165 → 212 MB result above verifies.

### Not produced

The four hand-driven conditions were **not** run on the iPhone in this session.
Backgrounding and screen lock have no CLI at all and need the owner's hands;
process recreation needs `ios tunnel` plus WDA to start a download first, and
WDA cannot be driven during a `flutter test` run here. The iPhone's evidence is
therefore the instrument above plus the shared repository and policy suites — a
real gap, stated rather than papered over. The App Switcher swipe in particular
is documented upstream as stopping background downloads outright and has not
been observed on this device.
