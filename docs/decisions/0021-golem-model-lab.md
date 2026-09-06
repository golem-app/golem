# Golem Model Lab: a fourth flavor that exists on macOS only

Status: decided on `feat/58-lab-flavor`, `feat/58-observation-events` and
`feat/58-lab-bench` (issue #58, epic #40)

## Context

Golem Model Lab (GML) is a desktop bench for the models the phone flavors
ship: pick one of the pinned configurations, chat with it through the same
`InferenceRepository` chat uses, and read load, prefill, decode, latency and
memory measurements off it. The three shipped identities are all phone apps
with a macOS build that opens an iPad-shaped window for layout preview; none
of them is a place for a bench, and the bench must not ride into a store
build. This record covers the flavor, its identity and artwork, its window,
its storage, how its exclusion from every other flavor is proven, the
observation events the bench reads, and the bench itself.

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

### Observation is opt-in and engine-honest

The bench needs live phase, progress and latency observations, and the ticket
forbids inventing them. ABI 6 adds two event kinds — `PROGRESS` and
`TOKEN_TIMING` — that a shim emits only when the request asked
(`reportProgress` on the load payload, an `observe` object on the generate
payload); a request that does not ask gets the ABI-5 stream unchanged. That
is deliberate twice over: chat's requests never change, and the overhead of
observing is measurable against the same engine in the same process.

The capability table in `docs/architecture/inferno.md` is the contract. It
records that only llama.cpp reports load and prefill progress, that prefill
progress counts submitted batches (which run ahead of the backend's compute)
and so is never a rate, and that MLX can stamp only detokenized chunks —
one or more tokens each — so its series is inter-chunk arrival latency and is
never called inter-token latency or turned into a throughput. The per-token
MLX path (`generateTokens`) exists in the library but the shim records it as
miscomputing Gemma 4 prefill, so it stays out.

The repository publishes the engine's phases as `RunPhaseEvent`s and forwards
progress and timing as domain events; chat's reducer and the eval runner
ignore them. A per-run `seed` on `generate` overrides the process-wide one
and turns the determinism probe on for that run, rather than riding the
persisted sampling overrides, whose emptiness drives the Settings reset. The
sampling a request carries is computed by one public function,
`effectiveSampling`, so what the bench shows as an effective value is the
call the engine received, not a second reading of the rules. The macOS
storage channel gains `physicalFootprintBytes` (the process's
`phys_footprint` now) and `deviceProvenance` (model, chip, memory, OS,
thermal state) for the readings every bench measurement carries; the phones
do not answer either, by design.

### The bench

`features/lab/` is the bench (`app/README.md`, "Golem Model Lab"). Its
domain is an immutable `LabRun` — the prompt, a configuration snapshot
frozen when the run started (catalog key, engine, effective sampling as the
broker computed it, the sparse settings that produced it, engine pins,
artifact receipt state, device provenance, start time), the phase, the
reasoning and answer text, bounded telemetry and the final metrics — folded
by a pure reducer. A run passes through exactly one terminal phase: the
reducer refuses to move a terminal run, and the controller tags every stream
with an epoch and drops late events, so a cancelled run that still emits its
metrics is terminated once. Stop keeps the partial output and waits for the
engine's own end of stream rather than inventing one — and whatever ends it
after Stop, a completion or the error both engines raise for a cancelled
load, records as cancelled. Stop is a flag on the run, not a phase: the run
keeps the phase it reached, so a load stopped mid-way shows no prefill or
decode it never did. Telemetry keeps the newest 4,096 instants, their gap
series computed once per batch, and the true count, so a long generation
cannot grow the state per token; the median and stall count of a run longer
than that describe its last 4,096 arrivals, which the README states. The
live decode rate is measured on the instants' own clock, anchored at the
engine's acceptance rather than the run's start (the load sits between), and
its interval runs to now, so the figure sinks while arrivals stall instead
of freezing at the last burst. The controller publishes at most every 60 ms
(phase changes and the terminal event at once), so the transcript and chart
never rebuild per token.

A run in flight locks the Rig. Changing the model, the engine or the settings
under a live run would silently invalidate the comparison, so it is
impossible rather than warned against; a change while idle closes the
conversation and starts a new one, so runs of different configurations never
sit side by side under one heading. A send locks the bench synchronously,
before anything can change what the run measures under; the artifact's
verified state is read from the model store as it stands. The seed a run
records is the one the engine receives: an empty seed inherits the launch
seed (`GOLEM_SAMPLING_SEED`) at the broker, and the snapshot and the
contract chip resolve it the same way.

The Rig shows what the run will carry, computed by the same
`effectiveSampling` the run sends; the phase chips show only what the engine
reported (a submitted count for a prefill in flight, a rate only once the
metrics say so, *chunks* on MLX and *tokens* on llama.cpp); the latency chart
is the gaps between arrivals and is labelled inter-token or inter-chunk by
the engine's kind; the footer holds one figure per phase and a dash where
none was measured. Device provenance sits beside the engine pins in the
sidebar: a Mac's numbers are not a phone's, and every measurement is made
under both.

#### The desktop tier

The bench keeps Golem Navy's ramp and voice at pointer densities
(`lab_theme.dart`): 11.5–13 pt text with tabular figures on every changing
number, 24 pt as the interactive minimum (macOS's own controls sit between
22 and 28 pt; the guideline sweep judges the bench at that size under the
macOS variant), a hover wash and a focus ring on every control through one
`LabFocusable`, keyboard activation on Enter and Space, and ⌘↩ / Esc / ⌘N
for run, stop and new conversation wherever focus is. The composer keeps
focus across a run: it is read-only while locked, never disabled. Reduced
motion swaps the indeterminate load's spinner for a static mark.

Two contrast fixes to the comps: small labels sit on the muted ink, never
the tertiary ink (the handoff's 3.80:1 metric labels), and the filled Stop
and Run buttons draw navy on the accent in dark, where white reads 2.95:1.
Disabled controls keep readable ink on a quiet fill instead of fading. The
Rig and the footer are wraps, not rows: every group truncates to the window
and the band grows a line when the window is narrow or the catalog is long,
which is what lets the same layout hold from 1440 × 900 to 1000 × 640 in
thirteen catalogs and at a 1.6× text scale.

Deviations from the comps, deferred to #59: no suite, history or prompt
navigation, no sweep or plan strip, no saved runs or comparison, and no
tokenizer-derived token count in the prompt tray before a run measured one.
The batch size is shown for llama.cpp only; MLX reports none.

#### Evidence

The host suite renders the bench at both window sizes in light and dark,
walks every state (empty, armed, loading, streaming, completed, cancelled,
failed, settings, tray, missing artifact) under the 24 pt tap-target,
labelled-target and contrast guidelines, drives the keyboard shortcuts,
asserts the run edges are announced exactly once, and lays the bench out in
every catalog at the smallest window. `integration_test/lab_acceptance_test.dart`
is the real-model instrument: all four configurations, two turns each,
engines switched both ways in one process, Stop with partial output, a forced
failure and Retry, the version-2 timing relations on every run, and the
observed stream timed against the silent one on each engine — a repeatable
decode slowdown of five percent or more blocks acceptance. The first record
is `docs/evals/2026-09-05-lab-acceptance-macos.md`: every configuration
passed, 1.4 % on llama.cpp and −0.2 % on MLX.

#### Lifecycle, deliberately narrower than the phone's

The handbook's rule that multi-gigabyte weights must not stay resident while
backgrounded is a phone rule: the background ceiling kills the process. The
lab root handles `detached` (a synchronous engine release, #124) and
`resumed` (a download reconcile) and nothing else — no release on `paused`
and none on memory pressure. A bench keeps its resident model between runs
by design, macOS has no jetsam ceiling, and a release on every window switch
would make every next run a cold one. The bench does terminate a run whose
stream ended without its completion event as *cancelled*, never completed,
so a teardown mid-run cannot read as a measurement.

#### The session bridge, bound by the bench

Model commands ask two things of the session through `ChatSessionBridge`:
the model the engine would load now, and whether a generation is in flight.
Chat answers both from its `ChatState`; the bench answers them as facts — the
armed configuration's key and its lock — through `bindFacts`, so it never
fabricates a chat state to be read through. The ensure-owner hook lives in
the lab's launch overrides (`labLaunchOverrides` names the bench controller
by a container read, the way the consumer composition names chat), so the
first command a launch dispatches builds the bench before it asks, no widget
lifecycle holds the hook, and the lab widget harness carries it.

Stop waits for the engine's own end of stream, which is the honest
terminator; an engine that never sends it would otherwise hold the whole
bench locked, so a ten-second watchdog ends the run as cancelled. Stop is
once per run: a held Escape repeats, and each repeat would re-arm the
deadline.

## Consequences

- Four identities. Every exhaustive switch over `AppIdentity` names the lab;
  the two that existed (`internalToolsEnabled`, the backend default) do.
  The lab composes `auto` like dev — on macOS, llama.cpp with the
  device-tier artifact — only to satisfy the repository's constructor; the
  bench arms configurations by key and never runs the boot-resolved one, and
  no artifact is stamped active for it.
- The lab has no chat, so `launchOverrides(lab: true)` never names
  `ChatController` as the session owner: the lab root passes the bench
  instead, and a model command asking whether a generation is in flight
  reads the bench rather than force-building a chat and its history.
  Overriding the bridge a second time in a separate list is not an option —
  a `ProviderScope` with the same provider twice fails silently under a
  deferred first frame, which is how this was found.
- QA's icon changed on every platform; the flavor's identity, container and
  wiring did not.
- Chat's reasoning card is now `features/chat/widgets/reasoning_card.dart`,
  extracted unchanged so the bench renders reasoning the way chat does; the
  chat goldens did not move.
