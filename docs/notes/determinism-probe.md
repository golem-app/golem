# Cross-device determinism probe

Question: with everything pinned — model artifact, engine, rendered prompt,
seed, temperature, top-p — does the same generation produce the same output
on macOS (Apple silicon, desktop GPU) and on an iPhone 17? Hardware
floating-point differences may legitimately diverge sampling even under
identical seeds; the point is knowing which engine holds.

## Method

One committed driver runs the identical code path on every platform:
`app/integration_test/real_backend_probe_test.dart` sends the fixed prompt
"Name the largest planet in the solar system." through the app's own chat UI
against a build carrying the real-backend dart-defines plus
`GOLEM_SAMPLING_SEED=7`. With a seed configured, the broker logs one
`INFERNO_PROBE` line per completed generation containing an FNV-1a 64-bit
hash of the raw pre-parser output text. Equal hashes ⇒ byte-identical
output text (chat template, sampling parameters `temperature: 1`,
`topP: 0.95`, and stop policy are identical by construction, so text
equality is the meaningful cross-device signal; token-level identity is not
measured directly).

Both runs used the `qa` flavor and the pinned Gemma 4 E2B artifacts from
`packages/inferno/lib/src/model_manifest.dart` (GGUF Q4_K_XL for llama.cpp,
4-bit MLX directory for MLX). The macOS llama build runs Metal
(`n_gpu_layers = -1`), the same configuration as iOS — not the old macOS
CPU path, whose outputs this Metal enablement changed even at fixed seed.

## Findings

| Engine | macOS (M-series) | iPhone 17 | Output-identical? |
| --- | --- | --- | --- |
| llama.cpp (Metal) | `fnv1a64=d710455907eadf55`, 54 chars | `fnv1a64=d710455907eadf55`, 54 chars | **Yes** |
| MLX | `fnv1a64=d710455907eadf55`, 54 chars | `fnv1a64=d710455907eadf55`, 54 chars | **Yes** |

Observations (2026-08-04, decode speeds for orientation only):

- **Both engines held across devices** on this prompt: macOS M-series and
  iPhone 17 produced byte-identical output at seed 7 — the expected
  hardware-float divergence did not materialize here.
- All four runs produced the identical 54-character answer ("The largest
  planet in the solar system is \*\*Jupiter\*\*."). The cross-engine
  agreement is luck of a peaked distribution as much as determinism; the
  cross-device agreement within each engine is the finding.
- Same-machine reruns of the same engine reproduce the hash exactly
  (llama.cpp verified twice on macOS).
- Throughput for context: llama-Metal 48 tok/s (Mac) vs 27 tok/s (iP17);
  MLX 66 tok/s (Mac) vs 42 tok/s (iP17). Correctness evidence only — never
  quote Mac numbers as mobile performance.

## Caveats

- A diverging hash localizes nothing by itself: sampler-order, kernel
  fusion, and accumulation-order differences across GPUs are all plausible
  causes. The probe answers "does it hold?", not "why not?".
- Longer or higher-entropy prompts are more likely to diverge; this short
  factual prompt is a smoke signal, not proof of general determinism.
- Comparisons are only valid within one engine and one model artifact;
  llama-vs-MLX agreement above is an observation, not a guarantee.
