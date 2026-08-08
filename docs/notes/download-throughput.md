# On-device Hugging Face download throughput (#36)

Measured 2026-08-08 on the pinned Qwen 3.5 4B GGUF
(`YoozLabs/Qwen3.5-4B-qat-GGUF` @ `2d52e26bd96b`, 2.54 GB), all clients on
the same Wi-Fi network, sampled with 40–45-second windows. Rates are
decimal MB/s.

## Matrix

| Client | Run samples | Mean |
| --- | --- | --- |
| macOS `curl`, single connection | 1.37 · 1.76 · 1.65 | ~1.6 |
| OnePlus 12R `/system/bin/curl`, single connection | 1.27 · 1.75 · 2.80 | ~1.9 |
| macOS `curl`, 3 parallel ranged connections | 2.50 + 3.57 + 10.76 | **~16.9 aggregate** |
| OnePlus 12R in-app (`background_downloader` DownloadWorker) | 0.33 · ~0.5 over three windows | **~0.4–0.6** |

iPhone 17 in-app sampling was not repeated this round; the #15-era
observations (~1.5 MB/s foreground, ~3.4 MB/s backgrounded) sit between
the Android in-app and raw-curl numbers and are consistent with the
attribution below.

## Attribution

1. **The phone radio is not the limiter.** OnePlus curl matched or beat
   Mac curl on the same network (2.8 MB/s peak sample).
2. **Single-connection CDN throughput is capped and noisy** (1.3–2.8 MB/s
   across all clients and runs) — the CAS-bridge variability suspected in
   the ticket, reproduced.
3. **Parallel ranged connections raise the aggregate ~10×** (16.9 MB/s
   over three ranges from the same Mac seconds after a 1.6 MB/s
   single-connection sample). The per-connection cap is per-stream, not
   per-client.
4. **The Android in-app stack costs another 3–5× under raw curl on the
   same device** (~0.5 vs ~1.9 MB/s): `background_downloader`'s
   DownloadWorker path paces well below what the link sustains.

## Recommendation

Adopt `ParallelDownloadTask` (multi-connection chunking behind the
existing `ArtifactFileDownloader` seam) as the follow-up implementation:
it attacks both the dominant term (per-connection cap, ~10× headroom
measured) and sidesteps most of the single-worker pacing gap. The
implementation must preserve the #15 invariants — pinned
`resolve/<revision>` URLs, per-file SHA-256, skip-if-valid, and
pause/resume/cancel — and respect the plugin's documented constraints
(chunks are a reserved task group; Android chunk sizes must stay under
the transfer-service limits; no URI destinations). File the change as its
own ticket; this note is the #36 deliverable (measure, attribute,
recommend).

Raw numbers were captured with
`curl -sL -o /dev/null --max-time 45 -w '%{size_download} %{speed_download}'`
and, for the ranged runs, three concurrent `-r` slices of the same
artifact; the in-app rate was read from the model card's progress
(0.05 → 0.07 → 0.14 → 0.16 GB at ~60 s / ~180 s / ~60 s intervals).
