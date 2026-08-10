# The launch bootstrap: what may fail before the first frame, and how

Status: decided on `chore/66-launch-bootstrap` (issue #66)

Before this decision, backend resolution, three application-directory
lookups, the preferences read, and the downloader start were all awaited
before `runApp`. A throw or a hang left the user on the native launch screen
indefinitely, and the splash's Try again reran none of the real work — the
startup gate's failure states were reachable only through injected scenario
defines.

## The shape

`main()` calls `runApp` immediately with a bootstrap root that owns the
fallible composition (`app/lib/app/launch_composition.dart`). While the
composition runs, the splash frame paints; on failure a classified pane
offers Try again, which reruns the real composition; on success the one
`ProviderScope` mounts with the composed overrides and the startup gate's
scripted theatre takes over under identical visuals. The bootstrap layer is
Riverpod-free — the scope does not exist until composition succeeds — and its
copy claims nothing about a model, because the backend may be exactly what
failed to resolve.

## Classification, bounds, and the retry-or-fallback decision per task

| Task | Classification | Bound | Decision |
| --- | --- | --- | --- |
| Dart-define `StateError`s (backend policy, inference composition) | Invalid configuration | synchronous | Terminal pane, no Try again: retry cannot repair a define. The developer text goes to `FlutterError.reportError`, never onto the surface. |
| Application-directory lookups | Environmental, required | composition deadline | Failure pane + Try again, rerunning the whole composition. |
| Preferences read | Optional with safe default | composition deadline | Silent degrade to defaults (unchanged); the Appearance screen owns the per-surface read failure and retry. |
| Downloader start | Optional service | own 5 s bound | Degrade and continue; the abandoned future is ignored and the repository's next call retries the start. A refused or hung platform channel never blocks chat. |
| Whole required composition | — | 8 s deadline | `TimeoutException` → failure pane + Try again. |
| Any other `Exception` | Unknown, environmental | composition deadline | Failure pane + Try again. |

The 8 s deadline is a real deadline over real work — deliberately not
`StartupSequence.timeout`, which is scripted scenario delay. It wraps only
the required stages: the downloader stage runs after it under its own bound
and can only degrade. Because `Future.timeout` abandons rather than cancels,
a timed-out attempt keeps running past its deadline — so each composition
carries a generation, and a superseded attempt aborts at the stage boundary
before downloader construction. Only the live attempt may construct the
downloader against the plugin's process-wide singletons; a retry can never
race a second instance. The downloader's own `start()` is bounded inside the
wrapper too, so an initialization the launch stopped waiting for still
resolves and clears its cached slot — the repository's next call genuinely
retries the start.

## What this does not change

The startup gate's scripted theatre — `StartupController`,
`StartupSequence`, the `GOLEM_MISSING_MODEL` / `GOLEM_SPLASH_FAILURE` /
`GOLEM_SPLASH_TIMEOUT` scenarios — is untouched, keeping widget tests,
goldens, and the journey deterministic. That leaves two owners of the splash
frame with different retry semantics: the bootstrap pane retries the real
composition, the theatre's failed scenario retries a script. The split is
deliberate — the theatre exists for deterministic demos and tests, and
folding real work into it would sacrifice exactly that — but it means splash
failure copy lives in two places, and a device tap on `splash-retry` proves
whichever layer is showing, not both. Corrupt-store quarantine remains the
repositories' business and never throws at launch. Release-mode evidence
uses `GOLEM_LAUNCH_FAILURES=<n>`: the first n real compositions throw, so a
single process demonstrates failure, Try again, and recovery on a device.
