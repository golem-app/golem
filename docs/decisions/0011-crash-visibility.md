# How Golem learns that it crashed, having chosen not to watch

Status: decided on `chore/28-accessibility-pass` (issue #28)

Golem ships no crash reporter, no analytics SDK, and no telemetry of any kind.
That is not an omission waiting to be corrected before launch — it is the
product. Settings ▸ Privacy & data tells the user, in the app, that Golem
"holds no account and sends no analytics. Chatting needs no network — Golem
goes online only when you ask it to fetch a model." (The sentence once
claimed the app "drops its network permission once a model is downloaded",
which no platform allows and Android's `INTERNET` permission cannot do; #154
reworded it to what the code does.) A crash SDK would make that sentence
false, and there is no honest rewording of it that keeps a reporter: "we only
send stack traces" is still a network call the user did not ask for, from an
app whose entire claim is that inference stays on the device.

The workspace has no such dependency today — `firebase_crashlytics`, `sentry`,
`bugsnag` and their kin appear nowhere in `pubspec.lock` — so this record
exists to make the absence deliberate rather than incidental, and to state what
is given up.

## What the platforms report without an SDK

Both stores already collect crashes from the operating system, under the
user's own opt-in rather than ours.

**Android.** Play Console's Android vitals reports user-perceived crash rate
and ANR rate, gathered by the Android system from users who agreed to share
data, on certified devices, for installs that came from Play. Google treats
1.09% (crashes) and 0.47% (ANRs) as the overall bad-behaviour thresholds, and
8% per device model; exceeding them costs Play visibility, so the signal is
one the store makes us care about whether or not we watch it.

**Apple.** Xcode Organizer's Crashes view shows reports from users who turned
on Share iPhone Analytics *and* Share with App Developers under Privacy &
Security ▸ Analytics & Improvements. TestFlight builds are the exception:
those testers' crash reports come back regardless of that setting, which makes
the TestFlight track the one place Golem can expect near-complete crash
coverage before release.

## What that costs

- **Neither signal is complete.** Both are limited to users who opted in, and
  Play additionally excludes sideloads and uncertified devices — which is every
  build in `docs/real-model-matrix.md` and every APK a developer installs by
  hand. Local device work produces no vitals at all.
- **No breadcrumbs, no context, no session.** A report is a stack trace and a
  device class. There is no way to learn which model was resident, how far into
  a generation the process died, or whether a download was in flight — the
  three things most likely to matter for a crash in this app.
- **It is slow and aggregated.** Both consoles report against rolling windows,
  so a regression is visible in days, not minutes, and never per user.
- **Nothing is attributable.** No user identifier means no way to follow up,
  and no way to tell one user crashing forty times from forty users crashing
  once.

Against a conventional app that trade is bad. Against this one it is close to
free: Golem is a single-process app with no accounts, no server, no
per-user state and no remote configuration, so the class of bug that
telemetry uniquely catches — one that reproduces only under a particular
backend deployment — cannot exist here. What can go wrong is native: a
llama.cpp or MLX crash under a specific model, quantization, or device tier.
Those are reproducible on hardware we hold, and the gated instruments in
`app/integration_test/` exist precisely to reproduce them.

## What makes the free signal usable

A native crash arrives as addresses unless the symbols were uploaded with the
build, and Golem is mostly native under the Dart. That half is already
enforced rather than trusted: `android/app/build.gradle.kts` sets
`debugSymbolLevel = "SYMBOL_TABLE"`, and `tool/check_android_packaging.dart`
reads the built bundle to confirm debug symbols are present for every shipped
ABI and stay under Play's 1.6 GB ceiling — the release-time gate described in
[ADR 0010](0010-android-native-packaging.md). Without it, Play clusters the
same crash separately per architecture and none of the frames name a function.

The iOS equivalent — shipping dSYMs with the App Store upload so Organizer can
symbolicate `libinferno` frames — has no repo-side gate today, because nothing
in this repository builds the uploaded artifact. It is a step in the upload
runbook, and the one loose end in this decision.

## When to revisit

Reverse this if, and only if, a crash lands that the platform consoles cannot
localize and a device in hand cannot reproduce — and even then, prefer an
opt-in, in-app, user-inspectable diagnostic over a third-party SDK that opens
a network path the privacy copy denies. Any such change is a change to the
promise on the Privacy & data screen, and must be made there first.
