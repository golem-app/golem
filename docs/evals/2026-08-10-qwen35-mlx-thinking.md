# Qwen 3.5 thinking loops, attributed — and the presence penalty ABI 4 carries (#80)

`reasoning-speed` on the pinned Qwen 3.5 4B MLX snapshot spent its whole
4096-token thinking budget without answering
(`docs/evals/2026-08-10-qwen35-4b-anchors.md`). This records the attribution:
what actually causes the loop, why the shipped recipe was wrong for it, and
the evidence behind the fix.

## Attribution method

`packages/inferno/tool/probe_qwen_thinking.dart` renders the failing anchor's
exact prompt in the Qwen ChatML template with the `<think>` primer and runs a
sampling grid — recipe variants × seeds {7, 42, 1980} — against a local
artifact, reporting whether `</think>` arrived before the 4096-token budget.
Seed 7 is the eval harness's own pinned seed, so its rows reproduce the
recorded failure exactly.

## What the grid shows

Closure counts (thinking channel closed before budget / runs):

| recipe | 4B `mlx-community` @ 32f3e8ec (pinned) | 2B `mlx-community` (pinned) | 4B YoozLabs qat-lean @ dc6b06e7 (2026-08-05 baseline) |
| --- | --- | --- | --- |
| shipped 0.6 / 0.95 | 1/3 | **0/3** | 3/3 |
| 0.6 / 0.95 / top-k 20 | 1/3 | 0/3 | 3/3 |
| 1.0 / 0.95 / top-k 20 | 3/3 | 1/3 | 2/3 |
| 1.0 / 0.95 | 3/3 | 2/3 | 2/3 |
| **1.0 / 0.95 / top-k 20 / presence 1.5** | **3/3** | **3/3** | — |

Three facts fall out:

- **No penalty-free recipe is reliable across the family.** Every artifact
  loops under some seed at some penalty-free recipe, and the recipes invert
  between snapshots: the old YoozLabs artifact earned its 2026-08-05 pass at
  0.6 and loops at 1.0, while the currently pinned artifact does the
  opposite. This is the quantization behavior the literature describes —
  low-bit reasoning models inflate their traces with near-duplicate steps
  (arXiv 2606.25519; 2606.00206) — surfacing per artifact, per seed.
- **The shipped recipe was wrong for both pinned artifacts.** The 2B never
  closes under it on this prompt: 0/6 across both 0.6 variants. The 4B that
  filed the ticket closes 2/6.
- **The card's full thinking recipe closes everything.** Qwen 3.5 publishes
  thinking-mode general-tasks sampling of temperature 1.0, top-p 0.95,
  top-k 20, min-p 0, presence penalty 1.5 — and names the presence penalty
  as the lever against endless repetition. With it, both pinned artifacts
  close 3/3 with the correct answer.

The pre-#80 profile carried the Qwen3-generation values (0.6/0.95, no top-k,
no penalty) because the pinned snapshot's `generation_config.json` publishes
only eos ids; the Qwen 3.5 model card is the recommendation source.

## The fix

- `qwen35` thinking sampling becomes the card's full recipe —
  1.0 / 0.95 / top-k 20 / presence penalty 1.5 — still pinned, budget still
  4096. Direct-mode sampling is untouched, so the nine direct anchors keep
  their baselines (five of them byte-identical across engines).
- The presence penalty did not exist in the engine ABI; **ABI 4** adds it to
  the generate request. llama.cpp applies `llama_sampler_init_penalties`
  with a window covering the whole generation (window = maxTokens) ahead of
  top-k/top-p/temperature — not `-1`: the core sampler clamps negatives to
  disabled, a silent no-op a review round caught, so the GGUF baselines
  below are recorded with the penalty verifiably active (a gated native
  test asserts it diverges output at a fixed seed). MLX sets
  `GenerateParameters.presencePenalty` with `presenceContextSize` widened
  from the library's 20-token default to the full budget — a 20-token window
  can never see, let alone break, a budget-length loop. Edge semantics stay
  engine-native: llama penalizes only sampled tokens, while MLX pre-seeds
  its ring with the prompt, so prompt vocabulary and the stop token carry
  the penalty there; reasoning hashes are therefore never comparable across
  engines.
- `budgetExhaustedBeforeAnswer` is untouched: it caught this and stays loud.

Penalty-free rows re-run after the ABI change reproduce the pre-change rows
seed for seed — the new field perturbs nothing when null.

## Anchor re-runs on the new recipe

One harness invocation, both engines × both pinned sizes, seed 7, macOS.
`reasoning-speed` — the anchor that filed #80 — passes on all four:

| combo | tokens | stop | fnv1a64 |
| --- | ---: | --- | --- |
| Qwen 3.5 4B GGUF Q4_0 | 1439 | endOfSequence | `aa525288c7f415bf` |
| Qwen 3.5 2B GGUF Q4_0 | 3035 | endOfSequence | `09f1dfda98d020ca` |
| Qwen 3.5 4B MLX 4-bit | 1666 | stopToken | `c86c939aabc2d409` |
| Qwen 3.5 2B MLX 4-bit | 1900 | stopToken | `7a80aa446baadcb6` |

The MLX token counts equal the probe's seed-7 `card-full` rows exactly —
the probe and the production broker path agree token for token — and
reproduce byte-for-byte across harness runs. An interim run with the
llama penalty still a no-op passed too (497 tokens, `9c249e10bb15a40b`
on the 4B): penalty-free 1.0/0.95/k20 happens to close the GGUF builds at
seed 7, which is exactly the accidental-pass class the probe grid warns
about and why the no-op mattered despite green anchors.

Every direct-mode anchor keeps its recorded baseline byte for byte where
one exists (4B GGUF `anchor-jupiter` `436a1c1c87b8c9fd`, `long-synthesis`
`c665ec00d00fc23c`, and the cross-engine-identical five, e.g.
`factual-capital` `8bfd779284f134df` on all four combos). The GGUF 4B
`reasoning-speed` baseline is intentionally re-recorded: the 2026-08-05
value (449 tokens, `dba9ee464930b4e1`) was measured at 0.6, which the grid
above shows was never a safe recipe for this family's quantized builds.

Two new facts the widened matrix surfaced, recorded rather than hidden:

- **2B MLX misses `arithmetic-17x23` in direct mode** (answers 411, 3
  tokens, hash `2bd5c11809be5185`). Direct-mode sampling is untouched by
  this change and the 2B text anchors had never been run before, so this
  is a pre-existing gap of the weakest pinned quant, consistent with its
  vision-matrix counting miss (`2026-08-09-mlx-vision-matrix.md`). With
  thinking on, the same artifact answers the harder reasoning prompt
  correctly.
- **2B GGUF thinks long**: 3035 of 4096 tokens on `reasoning-speed`.
  Within budget, but the least headroom of the four combos.

## Caveats

- Mac numbers serve answer quality and relative comparison only, never
  mobile performance (`docs/notes/determinism-probe.md`).
- The old YoozLabs snapshot's inversion (passes at 0.6, loops at 1.0) is
  recorded for attribution only; nothing pins that artifact anymore.
- The presence penalty applies to thinking mode only, as a profile-level
  correctness constraint with no user-override channel.
