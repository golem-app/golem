# Golem Model Lab acceptance — 2026-09-05

- Instrument: `app/integration_test/lab_acceptance_test.dart` on the `lab` flavor (`GOLEM_LAB_ACCEPTANCE=true`), issue #58
- Host: macOS Version 26.6.2 (Build 25G83), Apple M1 Pro, 32 GB
- Engine pins: llama.cpp b10241, MLX Swift 0.31.6
- Artifacts: the four pinned lab configurations, hard-linked into `~/Library/Application Support/app.golem.lab/Documents/models/` and verified offline through the lab's own store before the first run
- Timing semantics v2 (ADR 0020): `ttft s` is native request acceptance → first output token, prefill included; decode tok/s is tokens over first token → end; elapsed is acceptance → generation end
- Mac numbers serve correctness and relative comparison only — never quote them as mobile performance

## Turns

Two turns per configuration ("Name the largest planet in the solar system." then "And the smallest?"), engines switched in both directions inside one process (gguf → mlx → gguf → mlx). Every run held the v2 relations (`ttft ≤ elapsed`, `ttft ≥ prompt / prompt rate`, decode rate recomputable from the published numbers) and its observations counted the engine's output: one instant per token on llama.cpp, one per chunk on MLX. A cold run reports its load and ends the load fraction at 1; a warm run has no load phase.

| run | key | engine | load s | prompt tok | prompt tok/s | ttft s | tokens | decode tok/s | elapsed s | observations | median gap ms | stalls | peak GiB | batch |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| run-1 | gemma4-gguf | gguf | 1.34 | 18 | 192.2 | 0.121 | 11 | 62.2 | 0.30 | 11 token | 14.5 | 0 | 1.16 | 18 |
| run-2 | gemma4-gguf | gguf | warm | 43 | 526.0 | 0.098 | 11 | 71.5 | 0.25 | 11 token | 13.8 | 0 | 0.99 | 43 |
| run-3 | gemma4-mlx | mlx | 2.43 | 18 | 45.3 | 0.398 | 11 | 73.5 | 0.55 | 11 chunk | 13.6 | 0 | 3.34 | — |
| run-4 | gemma4-mlx | mlx | warm | 43 | 61.6 | 0.699 | 11 | 50.2 | 0.92 | 11 chunk | 13.4 | 1 | 3.36 | — |
| run-5 | qwen35-gguf | gguf | 1.78 | 21 | 60.4 | 0.374 | 67 | 38.0 | 2.14 | 67 token | 24.4 | 2 | 1.18 | 21 |
| run-6 | qwen35-gguf | gguf | warm | 102 | 348.1 | 0.323 | 122 | 41.0 | 3.30 | 122 token | 24.4 | 0 | 1.16 | 102 |
| run-7 | qwen35-mlx | mlx | 1.23 | 21 | 18.5 | 1.137 | 97 | 51.7 | 3.01 | 97 chunk | 19.3 | 0 | 3.58 | — |
| run-8 | qwen35-mlx | mlx | warm | 132 | 179.7 | 0.736 | 88 | 51.3 | 2.45 | 88 chunk | 19.4 | 0 | 3.71 | — |

The second turn of every configuration prefilled the conversation (its prompt count grew), and after each pair the resident key was the armed one. Batch is llama.cpp's `promptBatchSize` (`min(prompt, 512)`); MLX reports none. MLX's prompt rate on a cold first turn is the library's own figure over its first-token window (18.5–45.3 tok/s here) — the compile-and-warm cost of a fresh MLX graph sits inside `ttft`, which is why its cold `ttft` is three to nine times llama.cpp's on the same prompt.

## Stop and Retry

A 400-word prompt on `gemma4-gguf` was stopped after 21 tokens (88 characters of partial output kept, metrics still delivered, run terminated once). Retry sent the same prompt as a new run beside it:

| run | key | load s | prompt tok | prompt tok/s | ttft s | tokens | decode tok/s | elapsed s | observations | median gap ms | stalls |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| run-9 | gemma4-gguf | warm | — | — | — | 21 | — | — | cancelled | — | — |
| run-10 | gemma4-gguf | warm | 40 | 458.5 | 0.103 | 473 | 73.4 | 6.54 | 473 token | 13.6 | 0 |

## Forced failure

Reasoning on under a one-token budget: the broker refused run-11 as `budgetExhaustedBeforeAnswer` (the whole budget went to the thinking opener). The run kept its own snapshot (`maxTokens = 1`), the failed notice rendered, and Retry under the same contract failed the same way as a second run beside the first; neither turn fed the conversation's context.

## Instrumentation overhead

The same 150-word prompt, seed 7, observed (`GenerationObservation.everything`) against silent, straight through the repository so both cells run the identical request. One silent warm-up, then three alternating pairs per engine. A repeatable decode slowdown of 5 % or more blocks acceptance.

| engine | silent decode tok/s | observed decode tok/s | slowdown |
| --- | --- | --- | --- |
| gemma4-gguf (llama.cpp) | 73.2 / 73.4 / 73.4 / 73.8 | 73.5 / 70.4 / 73.4 | 1.4 % |
| gemma4-mlx (MLX) | 73.6 / 74.6 / 74.5 / 74.4 | 74.4 / 74.4 / 74.6 | −0.2 % |

Per-token stamping on llama.cpp and per-chunk stamping on MLX cost nothing a three-repeat measurement can separate from noise on this host.

## Result

PASS — 12 runs over 7 conversations, 26 `INFERNO_METRICS` lines, 69 s wall time, exit 0.
