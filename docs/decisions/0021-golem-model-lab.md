# Golem Model Lab: a fourth flavor that exists on macOS only

Status: decided on `feat/58-lab-flavor` (issue #58, epic #40)

## Context

Golem Model Lab (GML) is a desktop bench for the models the phone flavors
ship: pick one of the pinned configurations, chat with it through the same
`InferenceRepository` chat uses, and read load, prefill, decode, latency and
memory measurements off it. The three shipped identities are all phone apps
with a macOS build that opens an iPad-shaped window for layout preview; none
of them is a place for a bench, and the bench must not ride into a store
build. This record covers the flavor, its identity and artwork, its window,
its storage, and how its exclusion from every other flavor is proven. The
observation events and the bench itself are recorded below as they land.

## Decision

### The identity

- A fourth `AppIdentity`, `lab` — **Golem Model Lab**, `app.golem.lab` —
  with build configurations, a scheme and a Dock iconset in the macOS
  project only. iOS and Android have no `lab` product flavor, no source
  set, and no launcher inputs: `tool/prepare_launcher.dart` keeps a separate
  macOS-only flavor list that writes the Dock iconset and the in-app tile and
  nothing else, and `platform_assets_test.dart` asserts the phone artwork
  does not exist. The asymmetry is the product: phones are what the lab
  measures for, not where it runs.
- `internalToolsEnabled` is true: the lab is a measurement tool and keeps the
  `INFERNO_METRICS` / `INFERNO_FAILURE` / `INFERNO_PROBE` sinks. It does not
  compose the simulated benchmark (`composesSimulatedBenchmark`): a bench
  that measures real engines has no route for a simulation.
- The lab takes the red icon QA used to carry; QA moves to a grey one on
  every platform. The grey source is derived from the red artwork by a
  luminance-preserving desaturation of its red-hued pixels — the tile, its
  gradient and the tinted mascot — leaving the amber sparkle, the white ring
  and the matte untouched, so the three phone flavors keep one family
  likeness and the lab reads as the odd one out. The tint assertions moved
  from "one channel leads" to a per-flavor tint, `neutral` for QA.

### The window

`MainFlutterWindow.swift` opens one of two profiles, chosen by the
`GolemWindowProfile` Info.plist key that each build configuration fills from
`GOLEM_WINDOW_PROFILE`: `tablet` (the iPad Pro 11" portrait default, 480×640
minimum, the `GolemMainWindow` autosaved frame) for every consumer flavor and
the flavorless build, and `desktop` (1440×900 clamped to the visible screen,
1000×640 minimum, `GolemLabWindow`) for the lab. A build setting rather than
a bundle-identifier comparison, because the identifier is a fact about the
product and the window shape is a decision about it; `AppInfo.xcconfig`
carries the `tablet` default the same way it carries the flavorless bundle
id.

### The container

`getApplicationSupportDirectory()` is bundle-scoped everywhere, but
`getApplicationDocumentsDirectory()` on an unsandboxed Mac is the user's real
`~/Documents`, shared by every flavor — so a bundle identifier alone isolates
nothing there, and a lab download would land in the consumer flavors'
`models/`. The lab keeps `Documents` under its own support container:
`~/Library/Application Support/app.golem.lab/Documents`, with the models
under it. `storageLayoutFor` is the one place that decides.

The decision has two halves that must agree. The repository verifies, sizes
and deletes at its injected `documentsDirectory`; the download plugin resolves
its own base directory and places files itself. `BackgroundArtifactDownloader`
therefore takes the root and a subdirectory in the plugin's terms
(`applicationSupport` + `Documents` for the lab), and
`integration_test/lab_storage_test.dart` proves on a real lab build that a
provisioned artifact verifies in place through the plugin's own path with no
transfer. The consumer flavors are byte-identical: `documents` + `''`.

The phone flavors' macOS builds still share `~/Documents/models/` and mark
the user's real `~/Documents` as excluded from backup at every launch. That
is a bug of its own, out of this record's scope; the fix is a
`Platform.isMacOS` documents root under application support with a one-time
migration of downloaded weights.

### Excluded from every other flavor

`kLabBuild` is `appFlavor == 'lab'` — a compile-time constant, because
`appFlavor` is one — and every reference to the lab root sits inside an
`if (kLabBuild)` statement in the composition root. Constant-condition
elimination on an `if` is the mechanism `kReleaseMode` relies on, so the
lab's code never reaches another flavor's AOT snapshot. A separate entry
point was considered and rejected: every `flutter run --flavor lab` would
need a target flag, and a forgotten flag would silently build the consumer
app under the lab identity.

The proof is read off the compiler rather than trusted:
`tool/check_lab_exclusion.dart` reads the retained-object profile a
`--release --analyze-size` build writes and fails on any Library or Script
from `lib/features/lab/` or the lab root. Release-only, so it runs by hand
per change on the three production targets and is recorded in the pull
request;
CI builds the lab flavor in debug alongside QA so the fourth configuration
cannot rot. The host suite pins `kLabBuild` false and the consumer root under
the `dev` identity host tests run as, and the integration release-hygiene
test asserts `isLab` against `GOLEM_EXPECTED_LAB` on the compiled flavor.

### Layering

`lab` is a new top row in `tool/check_feature_imports.dart` (ADR 0015): it
reads the eval prompt suites and chat's presentation, so it sits above both,
and nothing imports it but its own root under `app/`.

## Consequences

- Four identities. Every exhaustive switch over `AppIdentity` names the lab;
  the two that existed (`internalToolsEnabled`, the backend default) do.
  The lab composes `auto` like dev — on macOS, llama.cpp with the
  device-tier artifact — only to satisfy the repository's constructor; the
  bench arms configurations by key and never runs the boot-resolved one, and
  no artifact is stamped active for it.
- The lab has no chat, so `launchOverrides(lab: true)` leaves the chat
  session bridge unbound: a model command asking whether a generation is in
  flight gets "no" instead of force-building `ChatController` and reading a
  chat history the lab never shows. Overriding the bridge a second time in a
  separate list is not an option — a `ProviderScope` with the same provider
  twice fails silently under a deferred first frame, which is how this was
  found.
- QA's icon changed on every platform; the flavor's identity, container and
  wiring did not.
