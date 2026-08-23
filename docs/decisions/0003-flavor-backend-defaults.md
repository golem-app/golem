# Flavor backend defaults, the device-model policy, and context caps

Status: decided on `feat/19-generation-settings-flavor-defaults` (issue #19)

The mobile `auto` mapping and first-need download behavior are superseded by
[ADR 0012](0012-platform-engine-and-required-model-startup.md): iOS uses MLX,
Android uses llama.cpp/GGUF, and a verified compatible model is required before
any app route content is exposed.

The install-time device floor that complements this composition policy is
documented in `../device_floor.md` (added with epic #61).

Amended by #116: the flavorless identity this record treats as a fourth
composition no longer exists. A build that names no flavor resolves to `qa`.
Every sentence below that groups "flavorless" with production is therefore
obsolete rather than re-readable — the grouping inverted. A flavorless build
now *gains* what those sentences say it suppresses: the benchmark route and
assets, the scripted launch and startup failures, and the device-capability
overrides. Read "production and the flavorless identity" as "production"
alone.

## The composition rule, stated once

- The `qa` flavor and the flavorless test identity wire fake inference and
  model management so goldens, journeys, and CI stay deterministic and
  offline. Benchmark is a separate internal-tool capability: `qa` and `dev`
  wire its deterministic fake, while production and flavorless builds omit
  its route, settings affordance, repository override, and prompt assets.
- `production` and `dev` wire the **real implementations**: the real
  Hugging Face downloader (since #37) and, with this decision, real local
  inference by default.
- Explicit dart-defines override the flavor default in **any** build.
  `GOLEM_INFERENCE_BACKEND` accepts `fake`, `llama`, `mlx`, and `auto`;
  unset falls to the flavor default (`auto` for production/dev, `fake` for
  qa/flavorless). `auto` on a qa build reproduces the exact production
  composition — the only real-path route on the physical iPhone, where the
  production and dev bundle ids belong to the native app.
- An explicit engine with no `GOLEM_MODEL_PATH` resolves that engine/profile's
  exact pinned catalog artifact and retains its capability proof. Supplying a
  path is the separate operator-sideload contract and does not inherit catalog
  projectors or image capability.
- `GOLEM_MODEL_ARTIFACT` selects an exact catalog key independently from its
  prompt-family profile. This is how builds select Qwen 2B versus 4B without
  inventing a second Qwen template. The artifact must match the selected
  engine and profile, and cannot be combined with the sideload path override.
- Coherence corollary (caught in device QA): overriding a qa build to real
  inference carries **model management** to the real implementation as
  well. A real engine fed by the download simulation would "install"
  files that do not exist and then fail on first load. Only inference
  left on the fake keeps the fake downloader.
- Amended by #148: the flavor default has one device-shaped exception. On a
  **simulator or emulator**, an internal identity with no engine define
  resolves `fake` rather than `auto`, and model management follows it, so a
  plain `flutter run` composes the simulation instead of fetching multi-gigabyte
  weights into a container where no engine can load them. Production is
  deliberately excluded: its composition stays a pure build-time fact, so a
  detection that ever answered wrong on a phone could refuse a shipping build
  but never quietly turn one into a simulation. An explicit
  `GOLEM_INFERENCE_BACKEND` still wins everywhere, and the device
  classification then refuses the transfer
  (`0007-supported-device-policy.md`) — including on `qa`, which is therefore
  untouched on a virtual device only while it names no engine. So does an
  artifact or a path define: the fake branch throws on the first and ignores
  the second, so a build that named any model configuration keeps the real
  path rather than being swapped under. A container that already holds real
  weights when the swap begins stops being managed — the fake repository has
  never heard of them, so the storage meter omits them and no row offers a
  delete. That costs a stale simulator container, which is why the exception
  stops at the two internal identities.

Host `flutter test` runs as the `dev` flavor, but flavor policy resolves
only in `main()`; the widget-visible backend signal
(`inferenceBackendProvider`) defaults to the fake and is pinned by a
regression test.

Internal tooling is keyed from `AppIdentity`, never `kDebugMode`: `qa` and
`dev` retain the benchmark, scripted launch/startup failures, device-capability
overrides, and `INFERNO_METRICS` / `INFERNO_FAILURE` / `INFERNO_PROBE` sinks
even in release builds. Production and the legacy flavorless identity suppress
all of them even in debug builds. Operator model/backend and performance
tuning defines remain available in every identity, and native engine error
transport is not part of this Dart logging policy.

## `auto`: engine and model

`auto` composes **MLX on iOS** and **llama.cpp/GGUF on Android**. macOS retains
llama.cpp. The exact platform engine is resolved before the capability probe,
then the model path, broker profile, and active catalog artifact are resolved
together as one value, eliminating the mismatched profile/path hazard.

## Device-model policy: 7 GiB, and unknown means small

Devices reporting **≥ 7 GiB** physical memory default to **Gemma 4 E2B**;
below that — or when memory cannot be read — the lighter **Qwen 3.5 2B**. The
artifact is the family on the engine the platform composes (ADR 0012):
`gemma4-mlx` (3.58 GB) / `qwen35-2b-mlx` (1.75 GB) on iOS, `gemma4-gguf`
(3.18 GB) / `qwen35-2b-gguf` (1.58 GB) on Android and macOS. Sizes follow the
pins in `docs/real-model-matrix.md`.

- The threshold is 7 GiB rather than a literal 8 GB because Android's
  `ActivityManager.MemoryInfo.totalMem` reports net of kernel/firmware
  reservations: a nominal 8 GB phone reads ~7.5 GB. The policy classifies
  nominal capacity, not reported bytes.
- Unknown memory selects the protective default: the policy exists to keep
  small devices out of trouble, so absence of evidence lands on the light
  side. The probe (a `physicalMemoryBytes` method on the existing storage
  platform channel) runs only on the `auto` path, capped at one second.
- `GOLEM_DEVICE_MEMORY_BYTES` is an internal-identity-only test override to
  exercise both branches on hardware (both team devices report over 8 GB).
- Since #27 the reading itself belongs to the device classification: one probe
  at launch produces a tier, the tier picks the model here, and the same
  verdict decides whether this device is admitted to running one at all
  (`0007-supported-device-policy.md`). The thresholds live together in
  `app/lib/core/domain/device_eligibility.dart`.

## First-need downloads require consent

A fresh production/dev install selects its default model but never starts a
multi-gigabyte download silently. Explicit consent begins the verified
download, and the app-root gate remains until installation succeeds. Decline,
pause, failure, interruption, or deletion never expose the shell.

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

Qwen's thinking-mode sampling is pinned against user overrides: off-spec
thinking sampling reproduced endless-think repetition loops during the
#33 bring-up, and again on the quantized MLX builds during #80, which
moved the pinned recipe to the Qwen 3.5 card's general-tasks values —
temperature 1.0 / top-p 0.95 / top-k 20 / presence penalty 1.5 (the
committed evals in `docs/evals/` record each configuration's evidence).
Token budgets remain overridable in both modes. Top-k and the presence
penalty stay off everywhere else, so every non-thinking baseline and the
determinism probes stay bit-identical; the qwen35 reasoning baselines are
recorded under the full recipe.

## Benchmark copy stays simulated and internal

The only benchmark implementation is the deterministic fake, available in
`qa` and `dev` only, so the
benchmark screen and its exported JSON keep their "simulated / not
hardware validated" labeling even in real-engine builds. Sweeping that
copy onto the backend signal would make it dishonest; it changes only
when a real benchmark implementation exists. Production omits the route,
settings row, repository wiring, and prompt assets instead of hiding a still
reachable surface.
