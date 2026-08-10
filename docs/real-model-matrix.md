# Real-model chat matrix

What has actually been run, on what hardware, against which pinned artifact —
and what is therefore *not* claimed. Recorded for #20, the closing acceptance of
epic #10.

Two rules this document exists to keep honest:

- **Capability follows a proven path, never a name.** An artifact advertises
  image input only where that exact artifact on that exact engine has read a
  picture (#18, ADR 0004).
- **Mobile numbers come from mobile.** macOS runs are for correctness and
  relative comparison only; they are never quoted as device performance.

## What ships

The engine is a build-time composition, not a runtime choice: `auto` — the
default on the `production` and `dev` flavors — composes llama.cpp/GGUF on both
platforms (ADR 0002), selecting Gemma 4 E2B at ≥ 7 GiB reported physical memory
and the lighter Qwen 3.5 2B below it (ADR 0003). The MLX engine is validated and
one dart-define away, but no shipping build selects it.

So a shipping build's chat model picker lists the three GGUF entries, and a user
switches among *those*. The MLX rows exist for builds that ask for MLX.

| Catalog key | Family | Engine | Quant | Installed size | Image input |
| --- | --- | --- | --- | ---: | --- |
| `gemma4-gguf` | Gemma 4 E2B QAT | llama.cpp | Q4_K_XL | 3.18 GB | yes — pinned `mmproj` |
| `qwen35-2b-gguf` | Qwen 3.5 2B | llama.cpp | Q4_0 | 1.58 GB | yes — pinned `mmproj` |
| `qwen35-gguf` | Qwen 3.5 4B | llama.cpp | Q4_0 | 2.91 GB | yes — pinned `mmproj` |
| `gemma4-mlx` | Gemma 4 E2B | MLX | 4-bit | 3.58 GB | yes |
| `qwen35-2b-mlx` | Qwen 3.5 2B | MLX | 4-bit | 1.75 GB | yes, with a caveat below |
| `qwen35-mlx` | Qwen 3.5 4B | MLX | 4-bit | 3.06 GB | yes |

Every file of every entry is pinned by byte count and SHA-256 in
`packages/inferno/lib/src/model_manifest.dart`, and installs are verified
against those pins before an entry counts as installed.

## Instruments

Gated integration tests carry this evidence. None runs in CI, and each
self-skips without its dart-defines.

| Instrument | Answers |
| --- | --- |
| `integration_test/device_acceptance_test.dart` | one device/engine cell end to end: install, text turn, per-chat switch, image turn, persistence |
| `integration_test/model_switch_acceptance_test.dart` | one process loading two artifacts under two chat templates |
| `integration_test/real_soak_test.dart` | twelve turns across the context-window boundary without degrading |
| `integration_test/custom_repository_acceptance_test.dart` | a hand-added, non-pinned repository resolving, downloading and running |
| `integration_test/real_download_smoke_test.dart` | the download stack against real Hugging Face: pinned URLs, streaming SHA-256, skip-if-valid, delete |
| `integration_test/download_lifecycle_test.dart` | reconciliation against the platform, and adoption instead of a second writer |

The last one covers only what a test process can reach. Backgrounding, screen
lock and process recreation are hand-driven on both platforms, for reasons and
with commands in `notes/download-lifecycle.md`.

Evidence lands on the host console as `GOLEM_CELL` lines beside the broker's own
`INFERNO_METRICS` lines. That channel matters: a release build's `debugPrint` is
os_log-privacy-redacted in an `ios syslog` capture, so device metrics are read
from the test harness, not the system log.

## Cells run

Each row is one `device_acceptance_test.dart` invocation: install the artifact,
send a text turn, switch the chat to a second artifact and send again, attach a
generated solid-colour PNG and ask what colour it is, then read the chat back
off disk. Every assertion is on content, not on the absence of a crash.

| Device | Engine | Primary | Switched to | Text | Image | Persisted |
| --- | --- | --- | --- | --- | --- | --- |
| iPhone 17, iOS 26.6 | llama.cpp | `gemma4-gguf` | `qwen35-2b-gguf` | `Paris` | `Red` | 6 messages |
| iPhone 17, iOS 26.6 | MLX | `gemma4-mlx` | `qwen35-2b-mlx` | `Paris` | `Red` | 6 messages |
| OnePlus 12R, Android 16 | llama.cpp | `gemma4-gguf` | `qwen35-2b-gguf` | `Paris` | `Red` | 6 messages |
| MacBook Pro M1 Pro, macOS 26.6 | llama.cpp | `gemma4-gguf` | `qwen35-2b-gguf` | `Paris` | `Red` | 6 messages |

Install came two ways on purpose. Where an artifact's files were already in the
container, the shipping Download path verified them against the pinned hashes
and installed with no network at all — the documented offline sideload. Where it
was absent, the same path fetched it from Hugging Face for real: `qwen35-2b-gguf`
on both phones, and `gemma4-gguf` on the iPhone, whose receipt did not cover a
projector pushed after the fact and so re-earned its install.

Sampling per turn, read off the `INFERNO_METRICS` line, is the evidence that a
profile travels with its model rather than with the build:

| Turn | Model | Profile | temperature / top-p | Prompt tokens |
| --- | --- | --- | --- | ---: |
| text | Gemma 4 E2B | `gemma4` | 1.0 / 0.95 | 20 |
| after switch | Qwen 3.5 2B | `qwen35` | 0.7 / 0.8 (pinned) | 45 |
| image | Gemma 4 E2B | `gemma4` | 1.0 / 0.95 | 119 (llama.cpp) / 326 (MLX) |

The numbers flip to Qwen's pinned pair on the switched turn and back afterwards,
on every device and both engines. Before #20 they could not: sampling was read
from the build's boot profile, so a switched chat kept the first model's numbers.
The macOS container happens to carry a hand-set Precise style for `gemma4`, and
it shows the same shape more sharply — 0.3/0.9 on the Gemma turns, Qwen's
0.7/0.8 in between, 0.3/0.9 again after. A user's per-model settings follow the
model, not the build.

The image turn's prompt is several times the text turn's for the same question —
the picture reached the engine rather than being dropped on the way.

Observed decode rates, for orientation only — one- and two-token answers make
these noisy by construction:

| Device | Engine | Gemma 4 E2B | Qwen 3.5 2B |
| --- | --- | ---: | ---: |
| iPhone 17 | llama.cpp | 9.0 tok/s | 8.3 tok/s |
| iPhone 17 | MLX | 40.5 tok/s | 49.3 tok/s |
| OnePlus 12R | llama.cpp | 7.7 tok/s | 24.1 tok/s |
| M1 Pro (never mobile evidence) | llama.cpp | 6.3 tok/s | 19.7 tok/s |

Android reports no `peakPhysicalFootprintBytes`; the field is Apple-only and
logs `null` there. On the iPhone the two engines report footprints an order of
magnitude apart for the same family — 1.05–1.25 GB under llama.cpp against
2.4–4.2 GB under MLX — because llama.cpp mmaps its weights and clean
file-backed pages are excluded from that metric. It is not a memory comparison.

The MLX decode rates are four to six times the llama.cpp ones on the same phone.
That is a real gap and a live argument for revisiting ADR 0002's engine choice,
but it is one prompt shape at one context length with single-digit token counts:
a reason to measure properly, not a decision.

### One process, two artifacts, two templates

`model_switch_acceptance_test.dart` on macOS, llama.cpp, three loads in one
process — Gemma → Qwen 2B → Gemma:

```
GOLEM_SWITCH gemma="Paris" qwen="Tokyo" gemma="Rome"
temperature=1.0 topP=0.95   ← gemma4
temperature=0.7 topP=0.8    ← qwen35
temperature=1.0 topP=0.95   ← gemma4
```

### Twelve turns across the windowing boundary

`real_soak_test.dart` on macOS, llama.cpp, `auto`, with a deliberately tiny
1024-token context and a 256-token budget so history is evicted every few turns:
12/12 turns completed, no recovery banner, and the process footprint plateaued
between 1.07 GB and 1.15 GB — 1.08× the warm baseline against a 1.5× bound.

### Paths this pass did not re-derive

Memory-pressure unload, background release, the low-memory load preflight,
typed load and mid-generation failures, and cancellation were delivered and
evidenced under #62/#63 and are unchanged by this work. Per-artifact vision
grading lives in `evals/2026-08-09-mlx-vision-matrix.md` and the two
`mmproj-selection` records. Real custom-repository download, verification and
deletion on both phones is #52's evidence.

No device screenshots were taken: label honesty is covered by the widget and
golden suites plus the residency assertions in each cell, not by eye.

### Text anchors, both engines, Qwen 3.5 4B

Re-run because #18 swapped the Qwen 3.5 4B MLX artifact without re-running them
(`evals/2026-08-10-qwen35-4b-anchors.md`). The shipping llama.cpp path passes all
ten and reproduces the 2026-08-05 baseline byte for byte. The MLX path failed
one — `reasoning-speed` spent its whole thinking budget without answering —
which #80 attributed to an off-card thinking recipe rather than the artifact:
no penalty-free sampling closes the quantized think channel reliably. The
`qwen35` profile now carries the Qwen 3.5 card's full thinking recipe
(1.0/0.95, top-k 20, presence penalty 1.5 over ABI 4), and the anchor passes
on both engines and both pinned sizes
(`evals/2026-08-10-qwen35-mlx-thinking.md`). The GGUF `reasoning-speed`
baseline is intentionally re-recorded there.

## Caveats and gaps

- **Qwen 3.5 2B on MLX mis-answers a counting question and a three-token
  multiplication.** The #18 vision matrix recorded it over-analysing the
  object-count fixture (`docs/evals/2026-08-09-mlx-vision-matrix.md`), and the
  #80 re-run surfaced `arithmetic-17x23` answered 411 in direct mode — the
  first text-anchor run this artifact ever had, not a regression. It still
  declares image input, which is accurate — it reads pictures — but it is the
  weakest of the six.
- **Cross-engine switching is not offered.** `BrokerRuntime.load` takes an
  engine per call, but the only code that cycles engines in one process disposes
  the adapter between them, so switching llama.cpp ↔ MLX inside a live app is
  unproven and the picker does not offer it.
- **A sideloaded `GOLEM_MODEL_PATH` has no catalog entry**, so it stays
  text-only, is labeled by its own file name, and cannot be switched away from
  and back.
