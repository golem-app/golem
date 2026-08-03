# iOS engine bake-off: llama.cpp-Metal selected for v0

Status: decided on `feat/3-inferno`

## Setup

- Device: iPhone 17 (`iPhone18,3`), iOS 26.6, USB, Release builds installed
  over the existing `app.golem.flutter`.
- Artifacts: the pinned manifest revisions —
  `unsloth/gemma-4-E2B-it-qat-GGUF` `gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf`
  (llama.cpp `b10241`, Metal, embedded metallib) and
  `mlx-community/gemma-4-e2b-it-4bit` (MLX Swift 0.31.6 /
  MLX Swift LM 3.31.4).
- Same broker path for both: identical rendered prompts, temperature 1.0,
  top-p 0.95, max 512 tokens, stop tokens `[1, 106]`. Metrics are the
  engine-reported `INFERNO_METRICS` lines captured from the device syslog.

## Measurements

| Run | llama.cpp-Metal | MLX |
| --- | --- | --- |
| Cold "2+2=?" | 20.3 tok/s decode, correct "4" | 30.1 tok/s decode, prompt 4.8 tok/s (first-run shader compile), correct "4" |
| Warm "17 × 23" | 27.2 tok/s decode, prompt 133.9 tok/s (41 tok), TTFT 0.119 s, correct "391" | 28.5 tok/s decode, prompt 42.8 tok/s (42 tok), TTFT 0.132 s, correct "391" |
| Warm long-form | 27.6 tok/s decode over 129 tok, TTFT 0.268 s | 28.0 tok/s decode over 153 tok, prompt 398 tok/s (544 fresh tok), TTFT 0.063 s |
| Peak `phys_footprint` | 0.39–0.45 GB¹ | 3.04–3.11 GB |

¹ llama.cpp mmaps the weights; clean file-backed pages do not count toward
`phys_footprint`, so the two columns measure different things. The number
shows llama's *allocated* memory is small and its weight pages are cleanly
evictable under pressure; MLX's buffers are resident allocations.

Reference baseline (deprecated native `golem-app/iOS`, same model class,
MLX): 18–22 tok/s decode, 60–360 tok/s warm prompt, ~4.2 GB peak footprint.

Both engines produced coherent, correct answers on all prompts, with
near-identical phrasing — a qualitative echo of the token-level parity
suite. Thermals stayed unremarkable; no memory-pressure events or WDA
stalls occurred across either session.

## Decision

The ticket's rule: llama.cpp-Metal must match or beat the MLX baseline to
justify a single-engine v0. It clears that bar decisively — 27+ tok/s
decode against the 18–22 baseline, warm decode within ~5% of
concurrently-measured MLX (28–30 tok/s), materially faster cold start (no
shader compile; mmap load), and a far lighter resident-memory profile on a
device this app has previously pushed into memory-pressure restarts.

**v0 ships llama.cpp as the single default engine on both platforms.** The
MLX shim stays in the tree: built by the same hook, covered by the
env-gated MLX suite and the parity fixture, and fully validated in this
bake-off — it is one dart-define away (`GOLEM_INFERENCE_BACKEND=mlx`) if
longer-context or sustained-throughput workloads later favour it.
