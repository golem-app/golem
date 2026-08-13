# On-device Hugging Face download throughput (#36, round 2)

Measured 2026-08-13 against the pinned Qwen 3.5 2B GGUF weights
(`unsloth/Qwen3.5-2B-GGUF` @ `f6d5376be1ed`, 1.21 GB; the 4B
`YoozLabs/Qwen3.5-4B-qat-GGUF` @ `2d52e26bd96b`, 2.54 GB, only where a run
had to outlive a window), all clients on the same Wi-Fi, 45-second capped
windows, decimal MB/s. Unlike the 2026-08-08 round, every in-app figure is
instrumented — windowed byte deltas off the download layer's own progress
stream (`DOWNLOAD_BENCH` lines from `app/integration_test/download_bench_test.dart`)
— never read off the UI.

## Matrix

| Client | Samples (MB/s) | Mean |
| --- | --- | --- |
| macOS `curl`, single connection | 24.8 · 17.6 · 26.3 (bracket 27.8) | ~23 |
| macOS `wget`, single connection | 31.2 · 22.7 · 27.8 | ~27 |
| macOS URLSession `.default` (Swift CLI) | 24.6 · 32.4 · 51.2 | ~36 |
| macOS URLSession `.background` (Swift CLI) | 29.3 · 47.8 · 40.2 | ~39 |
| macOS `curl`, 3 ranged connections | 62.8 · 64.1 · 66.5 | **~64 aggregate** |
| macOS `curl`, 6 ranged connections | 81.3 · 75.2 · 101.5 | **~86 aggregate** |
| macOS in-app `current` (plugin) | 30.9 · 37.3 | ~34 |
| macOS in-app `parallel4` (ParallelDownloadTask) | 57.4 · 52.4 | ~55 |
| macOS in-app `http4` (in-process ranged dart:io) | 60.7 · 60.6 | ~61 |
| OnePlus 12R `/system/bin/curl`, single connection | 11.0 · 16.3 · 25.3 | ~17.5 |
| OnePlus 12R `curl`, 3 ranged connections | one run | ~38 wall |
| OnePlus 12R in-app `current`, foreground | 49.1 · 46.6 · 35.2 | **~44** |
| OnePlus 12R in-app `parallel4`, foreground | 45.4 · 40.1 · 46.8 | ~44 |
| OnePlus 12R in-app `current`, **backgrounded** | one 225 s window | **~1.2** |
| iPhone 17 in-app `current`, foreground | 44.4 (steady 54.1) | **~44** |
| iPhone 17 in-app `parallel4`, foreground | 36.6 (steady 43.3) | ~37 |
| iPhone 17 in-app `http1` (curl stand-in), foreground | 41.6 | ~42 |
| iPhone 17 in-app `current`, **backgrounded** | 1.05 GB over 225 s suspension | **~3.8** |

In-app Android `http1`/`http4` (in-process dart:io) measured 4–6 MB/s under
the debug-JIT test harness — recorded as **not comparable** rather than as a
transport verdict; a profile-mode re-run is follow-up work if an in-process
transport is ever a candidate on Android.

## Attribution

1. **The 2026-08-08 "in-app is 0.4–0.6 MB/s" Android finding does not
   reproduce in the foreground.** Instrumented, the production
   `background_downloader` path saturates the link (~44 MB/s mean, beating
   on-device curl's ~17.5) three interleaved times in a row. The prior number
   was read off the model card during what was almost certainly a
   **backgrounded or background-paced** stretch — see 3.
2. **Per-stream CDN throughput is capped and noisy** (11–51 MB/s across every
   single-connection client and platform today; 1.3–2.8 MB/s on 2026-08-08).
   Ranged parallelism raises the aggregate 2–4× and, as importantly, averages
   the per-stream lottery away. Both rounds agree on this even though the
   absolute numbers moved by an order of magnitude between days.
3. **Backgrounding is the real cliff on Android: ~45 MB/s → ~1 MB/s** (a
   30–45× penalty, OxygenOS background pacing of the transfer service). The
   two contradictory prior claims — PR #37's ~16 MB/s and the old note's
   ~0.4–0.6 MB/s — are both consistent with this once foreground state is
   controlled for, which neither of them did.
4. **iOS has no foreground penalty either**: the plugin's background
   `URLSession` runs at link speed (~44–54 MB/s) while the app is active, and
   the #15-era "1.5 MB/s foreground" was network conditions, not the stack.
   Suspended, nsurlsessiond's discretionary pacing drops it to ~3.8 MB/s — a
   ~12× cliff, matching the #15-era 3.4 MB/s almost exactly.
5. **The foreground/background split is the story on both platforms**:
   OnePlus ~44 → ~1.2 MB/s (~35×), iPhone ~44 → ~3.8 MB/s (~12×). Transport
   choice barely matters next to keeping the app in the foreground.

## The >9-minute Android auto-resume race (#37 review watch item)

Attempted twice, unreproduced, not disproven — full account in
`download-lifecycle.md` (§ #36 round 2 additions). The code path stands; the
mitigation that matters is that at measured foreground rates every pinned
artifact finishes far inside 9 minutes.

## Recommendation

**Keep the current `background_downloader` single-task transport. The
throughput problem is not the transport — it is background pacing, on both
platforms.** Foreground, the shipping stack saturates the link on the OnePlus
(~44 MB/s, beating raw curl) and the iPhone (~44–54 MB/s); suspended, the OS
drops it to ~1.2 MB/s (Android, ~35×) and ~3.8 MB/s (iOS, ~12×). No
transport swap recovers that — nsurlsessiond's discretionary pacing and
OxygenOS's background throttling are platform policy.

What to ship instead, as the follow-up ticket:

1. **A foreground-fast download experience**: while a download runs, tell the
   user plainly that keeping the app open makes it several times faster
   (measured: 12–35×), and keep the existing background continuation as the
   graceful fallback. This converts the finding directly into user-visible
   speed at near-zero engineering risk.
2. **Optionally, hybrid parallel ranged transfers for the weights files** as
   insurance against slow-CDN days (the 2026-08-08 round measured 1.3–2.8
   MB/s per stream with ~10× parallel headroom; today single streams did
   11–51 MB/s and parallelism bought nothing at the link ceiling). The
   constraints are now priced, on-device: only LFS/CAS files chunk (small
   repo files have no Content-Length and refuse ranges), chunked parents need
   their own `inspect`/adoption arithmetic, and the plugin's reserved `chunk`
   group must stay clear of `golem-models`. The spike's
   `ParallelArtifactDownloader` (test support) passes all three lifecycle
   proofs on both phones in this hybrid shape.

The winner being the incumbent, the hand-driven lifecycle evidence from the
2026-08-10 round (backgrounding, lock, SIGKILL, force-stop, connection loss,
pause semantics) remains the transport's device evidence; nothing about it
changed in this round.

## How to reproduce

Host baselines (from the repo root; downloads go to a temp dir and are
deleted; `--window 5 --rounds 1` for a smoke pass):

```sh
dart run tool/bench_host_download.dart --rounds 3 --window 45
swift tool/urlsession_bench.swift <pinned-url> --mode default --window 45 --repeat 3
swift tool/urlsession_bench.swift <pinned-url> --mode background --window 45 --repeat 3
```

In-app, through the real `ArtifactFileDownloader` seam (macOS or a device;
`--no-uninstall` is mandatory on a phone):

```sh
flutter test integration_test/download_bench_test.dart -d <device> \
  --flavor qa --no-uninstall --dart-define=GOLEM_DOWNLOAD_BENCH=true
```

`GOLEM_BENCH_TRANSPORTS`, `GOLEM_BENCH_WINDOW_S`, `GOLEM_BENCH_ROUNDS`,
`GOLEM_BENCH_ARTIFACT`, `GOLEM_BENCH_BACKGROUND`, and
`GOLEM_BENCH_COMPLETE=<transport>` (full download + SHA-256 verification)
narrow or extend the matrix; every window emits one `DOWNLOAD_BENCH` line on
the harness console. Mind Hugging Face's patience: one full matrix pulls the
1.21 GB artifact a dozen times, so prefer single rounds and short windows
when iterating.
