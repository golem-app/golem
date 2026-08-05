# Flavor backend defaults, the device-model policy, and context caps

Status: decided on `feat/19-generation-settings-flavor-defaults` (issue #19)

## The composition rule, stated once

- The `qa` flavor and the flavorless test identity wire **all fakes** —
  inference, model management, and benchmark — so goldens, journeys, and CI
  stay deterministic and offline.
- `production` and `dev` wire the **real implementations**: the real
  Hugging Face downloader (since #37) and, with this decision, real local
  inference by default.
- Explicit dart-defines override the flavor default in **any** build.
  `GOLEM_INFERENCE_BACKEND` accepts `fake`, `llama`, `mlx`, and `auto`;
  unset falls to the flavor default (`auto` for production/dev, `fake` for
  qa/flavorless). `auto` on a qa build reproduces the exact production
  composition — the only real-path route on the physical iPhone, where the
  production and dev bundle ids belong to the native app.
- Coherence corollary (caught in device QA): overriding a qa build to real
  inference carries **model management** to the real implementation as
  well. A real engine fed by the download simulation would "install"
  files that do not exist and then fail on first load. Only inference
  left on the fake keeps the fake downloader.

Host `flutter test` runs as the `dev` flavor, but flavor policy resolves
only in `main()`; the widget-visible backend signal
(`inferenceBackendProvider`) defaults to the fake and is pinned by a
regression test.

## `auto`: engine and model

`auto` composes the **llama.cpp/GGUF** artifact of the device-policy model
on both platforms, per ADR 0002 (llama.cpp is the single v0 engine:
equal-or-better decode, no shader-compile cold start, mmap-evictable
weights on memory-pressure-prone phones). MLX remains one dart-define away.
The model path, broker profile, and active catalog artifact are resolved
together as one value, eliminating the mismatched profile/path hazard.

## Device-model policy: 7 GiB, and unknown means small

Devices reporting **≥ 7 GiB** physical memory default to **Gemma 4 E2B**
(`gemma4-gguf`, 2.62 GB); below that — or when memory cannot be read —
the lighter **Qwen 3.5 4B** (`qwen35-gguf`, 2.54 GB).

- The threshold is 7 GiB rather than a literal 8 GB because Android's
  `ActivityManager.MemoryInfo.totalMem` reports net of kernel/firmware
  reservations: a nominal 8 GB phone reads ~7.5 GB. The policy classifies
  nominal capacity, not reported bytes.
- Unknown memory selects the protective default: the policy exists to keep
  small devices out of trouble, so absence of evidence lands on the light
  side. The probe (a `physicalMemoryBytes` method on the existing storage
  platform channel) runs only on the `auto` path, capped at one second.
- `GOLEM_DEVICE_MEMORY_BYTES` is a test-only override to exercise both
  branches on hardware (both team devices report over 8 GB).

## First-need downloads require consent

A fresh production/dev install selects its default model but never starts
a multi-gigabyte download silently. The first generation attempt without
the installed artifact fails fast into a typed missing-model state, and
the chat banner offers an explicit sized "Download …" action
(`download-active-model`) that drives the existing verified download
machinery and lands on the Settings model card for progress and control.

## On-device context caps

User-facing context length is a broker-level token budget over prompt plus
generation, enforced identically by both engines (llama.cpp additionally
caps at the model's trained context; MLX has no cap of its own, so the
budget is its only bound). The default and UI maximum is **8192 tokens
for both models** — far under Gemma's trained context and Qwen's 256k
upstream context, but sized so worst-case KV memory stays in the low
hundreds of megabytes on an 8 GB phone. The settings UI keeps every
mode's effective budget at least a 512-token prompt reserve below the
context (`maxTokens ≤ contextLength − 512`, clamped across both reasoning
modes), so a budget can never be unsatisfiable by construction; very long
chats can still exhaust the reserve and surface the engines' budget
error.

Qwen's thinking-mode sampling (temperature 0.6 / top-p 0.95) is pinned
against user overrides: off-spec thinking sampling reproduced
endless-think repetition loops during the #33 bring-up (the committed
evals in `docs/evals/` record the fixed configuration passing). Token
budgets remain overridable in both modes. Top-k ships plumbed through
both engines but off by default, so recorded eval baselines and
determinism probes stay bit-identical.

## Benchmark copy stays simulated

The only benchmark implementation is the deterministic fake, so the
benchmark screen and its exported JSON keep their "simulated / not
hardware validated" labeling even in real-engine builds. Sweeping that
copy onto the backend signal would make it dishonest; it changes only
when a real benchmark implementation exists.
