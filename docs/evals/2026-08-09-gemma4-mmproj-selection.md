# Gemma 4 E2B multimodal projector selection

Recorded for #18. Decides which `mmproj` ships with `gemma4-gguf`, and
establishes that Gemma 4 E2B image input works at all through the pinned
llama.cpp path.

## Why this needed proving

The projector candidates are published by `ggml-org`, while the shipping
weights are unsloth's QAT build. A matching architecture is not proof that a
projector pairs with a differently-quantized language model, so the pairing was
treated as a hypothesis rather than an assumption.

**It holds.** `clip_model_loader` reports a vision encoder, `mtmd_tokenize`
substitutes the media marker, and `mtmd_helper_eval_chunks` prefills correctly.

## Setup

| | |
| --- | --- |
| Host | Apple M1 Pro, 32 GB, macOS 26.6.1 (25G76) |
| Engine | llama.cpp `9bd4c09ea571a9020f30eeef169b552625b5b5a4` (release `b10241`), Metal, `libmtmd` built standalone |
| Path | production Inferno ABI 3 — the same shim, load payload, and generate call the app uses |
| Weights | `unsloth/gemma-4-E2B-it-qat-GGUF` @ `66a399f68ddd113b06dff02fca9523e55465d11d`, `gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf`, 2 620 370 976 B, `e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889` |
| Sampling | temperature 1.0, top-p 0.95, top-k off, seed 7, max 64 tokens, context 4096, stop `[1, 106]` + `<turn|>` |
| Procedure | one warm-up per projector (discarded), then 3 cold runs each, model and projector fully unloaded between runs |

Candidates, both from `ggml-org/gemma-4-E2B-it-GGUF` @
`64ef033dc9f85a88f88e70cceb0a7457366bea64`:

| Variant | Bytes | SHA-256 |
| --- | --- | --- |
| BF16 (16-bit reference) | 986 833 664 | `711e1e8f43fa0664adbac493129be1e6c25b81af4b4cdea97c7d798b25c0a3a4` |
| Q8_0 (candidate) | 557 368 064 | `9406f99c16d68cda4f1f0552192dcc99021ea1fc6d2fd50b1dc3ccf30d04b292` |

## Graded cases

Five fixtures, one question each, asserted on required and forbidden
substrings. Four are hand-generated PNGs so ground truth is exact rather than a
judgement call; the OCR case is llama.cpp's own `tools/mtmd/test-1.jpeg`
photograph of a newspaper front page.

| Case | Fixture | Asks | Requires |
| --- | --- | --- | --- |
| `ocr` | newspaper photo | what text appears | `moon` |
| `colour` | red circle | what colour | `red`, not `blue`/`green` |
| `count` | three blue squares | how many | `3`/`three` |
| `spatial` | red square left, green circle right | which side is the square | `left`, not `right` |
| `chart` | three bars, tallest on the right | which side is the tallest bar | `right`, not `left` |

## Results

| | BF16 | Q8_0 |
| --- | --- | --- |
| Assertions passed | 12 / 15 | 12 / 15 |
| Median peak resident memory | **1 413.7 MB** | **990.6 MB** |
| Per-run peaks | 1 409 / 1 414 / 1 416 MB | 981 / 991 / 991 MB |
| Median projector load | 0.99 s | 0.85 s |
| Median decode | 14.7 tok/s | 14.6 tok/s |
| Median TTFT | 55 ms | 54 ms |
| Image prompt size | 109 tokens (84–152 observed) | 109 tokens (84–152 observed) |

Sample answers (Q8_0): OCR — *"a newspaper clipping … **MEN WALK ON MOON** …"*;
colour — *"Red"*; count — *"3"*; spatial — *"left"*.

## Selection

**Q8_0 ships.** Median peak resident memory is 423.1 MB lower — 29.9% — which
clears the gate of at least max(5% = 70.7 MB, 64 MiB = 67.1 MB) by a wide
margin, with no case-level quality or grounding difference between the two and
throughput within noise. On the 8 GB tier this app supports, 423 MB is the
difference between comfortable and memory-pressured.

The BF16 file remains an evaluation input in the manifest. Only Q8_0 is pinned
as a `projector`-role file on `gemma4E2BGgufQ4` and enters normal download.

## Physical Android acceptance

The selected Q8_0 projector was accepted through the shipping app path on a
OnePlus 12R running Android 16, using the separate `app.golem.qa` package. The
app downloaded and verified both catalog files (3.18 GB total) before the
request was retried; no sideload or receipt edit bypassed model management.

Using Android's system photo picker, the fourth gallery image—an apple on a
wooden table—was attached through the composer, persisted into the chat, and
sent to the catalog-backed Gemma GGUF runtime. For the prompt “What fruit is
shown in this image? Answer with one word.” the settled response was `Apple`,
one generated token at 10.5 tok/s. This exercises the Android picker, intake
normalization, attachment store, broker prompt, ABI 3 image array, `libmtmd`,
and the selected cross-repository projector as one end-to-end path.

## Recorded grounding failure

**Chart reading fails, identically on both projectors.** All three cold runs of
each projector answered `Left` when the tallest bar is unambiguously on the
right. This is a model/vision limitation on a synthetic unlabelled bar chart,
not a projector discriminator, and it is not a Q8_0 regression — but it means
the claim "every required assertion passes" would be false, and it is recorded
rather than dropped.

Consequence: Gemma 4 E2B image input is reliable for object and colour
identification, counting, spatial relationships, and text/OCR. Chart and diagram
interpretation is **not** something this build should be presented as good at.

## Note for future harnesses

A CLI harness that cycles engines must terminate explicitly. The native
callback listener deliberately outlives unload
(`docs/architecture/inferno.md`), so a script that finishes its work and falls
off the end of `main` hangs at exit with the work already done — and any
buffered pipeline swallows its output. The first attempt at this bake-off
looked like a hang for exactly that reason.
