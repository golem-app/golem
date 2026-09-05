# Qwen 3.5 GGUF multimodal projector selection

> **Legacy timing semantics (v1)** — the TTFT figures below came from a
> bespoke CLI over the ABI-3 llama shim, which timed from the end of prefill
> to the first token. On an image prompt that excludes projector evaluation
> and prefill, which is most of the wait; they are decode-start delays, not
> times to first token, and are not comparable with v2
> (`docs/decisions/0020-generation-timing-semantics.md`). The selection rests
> on peak footprint and answer quality, which this note does not touch.

Recorded for #18. This independently selects the projector shipped with the
Qwen 3.5 2B and 4B GGUF artifacts and proves that their similarly named
projectors are not interchangeable.

## Setup

| | |
| --- | --- |
| Host | Apple M1 Pro, 32 GB, macOS 26.6.1 (25G76) |
| Engine | llama.cpp `9bd4c09ea571a9020f30eeef169b552625b5b5a4` (release `b10241`), Metal, production Inferno ABI 3 and standalone `libmtmd` |
| 2B weights | `unsloth/Qwen3.5-2B-GGUF` @ `f6d5376be1edb4d416d56da11e5397a961aca8ae`, `Qwen3.5-2B-Q4_0.gguf`, 1 214 873 856 B, `cd70221bebaee0503e0f6717e174250cd7825aa88438b3aabec9ad55731d9bb1` |
| 4B weights | `YoozLabs/Qwen3.5-4B-qat-GGUF` @ `2d52e26bd96b49be5f8d37f1c85b27673adaa7da`, `Qwen3.5-4B-qat-Q4_0.gguf`, 2 543 899 040 B, `1367a2b4f8dc63a1782aa1f4006767d5451b8e5d491cc241cb656fbf4b4b5e62` |
| Sampling | non-reasoning Qwen profile: temperature 0.7, top-p 0.8, seed 7, maximum 64 tokens, context 4096, stop `[248046, 248044]` + `<\|im_end\|>` |
| Procedure | one discarded warm-up, then three cold processes per model/projector; each process loaded once, ran all fixtures, unloaded, and exited |

The fixtures and assertions match the Gemma projector bake-off: newspaper OCR,
red-shape colour, three-object count, left/right spatial relation, and a simple
bar chart. They cover a natural photograph as well as deterministic synthetic
ground truth.

## Immutable candidates

| Model | Variant | Repository revision | Bytes | SHA-256 |
| --- | --- | --- | ---: | --- |
| 2B | F16 | `prithivMLmods/Qwen3.5-2B-MTP-GGUF` @ `d4a4b305fe76ab01b541278d3078cd25c825530a` | 671 372 864 | `91ea86496a1c02d7cd32fbfa963e103d2a512fa29ca4a22dca1a9c92c3fd30d8` |
| 2B | Q8_0 | same | 364 664 384 | `526dbf85f350baf3a5107b1f14e629e94571c7cbab4277476fbdaaa8c4a31a64` |
| 4B | F16 | `prithivMLmods/Qwen3.5-4B-MTP-GGUF` @ `dd65086bdcdd7a8f242a2e54cfe11caf8cd51097` | 675 569 216 | `463f39bd1c291c1186c319a8c90ff8640aafa678b14cbee2232d695113dfbb66` |
| 4B | Q8_0 | same | 366 894 656 | `40a4f07d7bbdbb43011d6cf35ef751e4b1829ff47ee8aa4964c6296f571725ad` |

## Results

| Model | Projector | Graded cases | Median peak footprint | Median load | TTFT range |
| --- | --- | ---: | ---: | ---: | ---: |
| 2B | F16 | 15 / 15 | 1 084.4 MB | 0.648 s | 38–40 ms |
| 2B | Q8_0 | 15 / 15 | **789.0 MB** | 0.549 s | 37–40 ms |
| 4B | F16 | 15 / 15 | 1 135.2 MB | 0.761 s | 85–88 ms |
| 4B | Q8_0 | 15 / 15 | **837.5 MB** | 0.648 s | 85–89 ms |

Every cold run produced the same grounded facts for both quantizations: the OCR
answer contained `MEN WALK ON MOON`, followed by `red`, `3`, `left`, and
`right`. No hallucination, omission, or case-level regression appeared.

For 2B, OCR decode was 71–73 tok/s and one-word decode was 18–19 tok/s. For 4B,
OCR decode was 38–40 tok/s and one-word decode was about 8.5–9.0 tok/s. The
small variation between variants is noise relative to the memory result.

## Selection

**Q8_0 ships for both sizes.** On 2B it lowers median peak footprint by
295.4 MB (27.2%); on 4B it lowers it by 297.7 MB (26.2%). Both reductions clear
the selection gate of the greater of 5% or 64 MiB, while all required answers
remain identical. The F16 files remain pinned evaluation inputs only.

## Wrong-size rejection

The production Inferno load path was also run in both invalid directions with
the selected Q8_0 files:

- 2B language weights + 4B projector; and
- 4B language weights + 2B projector.

Both failed during `mtmd_init_from_file`, before generation, with the typed
`InfernoErrorCode.incompatibleModel` and user message “The image projector does
not match this model.” The 2B projector outputs a 2,048-wide language
projection and the 4B projector outputs 2,560; Inferno relies on `libmtmd`'s
model-aware initialization to enforce that boundary rather than matching a
filename or repository slug.

## Physical Android acceptance

Both selected Q8_0 projectors were also exercised through the shipping app path
on a OnePlus 12R (Android 16, arm64-v8a). Each run started a fresh chat, selected
the same fourth photo from the Android system gallery, and sent “What fruit is
shown? Answer with one word.” The pictured object was a green apple. Image
intake decoded, oriented, stripped metadata from, and canonicalized the gallery
photo to PNG under the one-megapixel ceiling before Inferno loaded it.

| Model | Result | Decode |
| --- | --- | ---: |
| Qwen 3.5 2B GGUF Q4_0 + Q8_0 projector | `apple` (1 token) | 14.1 tok/s |
| Qwen 3.5 4B GGUF Q4_0 + Q8_0 projector | `Apple` (1 token) | 7.9 tok/s |

The 4B artifact was copied over USB into the QA app's private model directory
to avoid making network throughput part of the test. The app itself then
hashed both files and wrote the normal verified-install receipt before the
release build was installed over the same QA package. No catalog or preference
state was edited. The temporary transfer directory was removed after
verification; the production `app.golem` package was not touched.
