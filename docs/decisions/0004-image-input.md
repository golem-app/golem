# Image input: ABI 3, mtmd, and capability as data

Status: decided on `feat/18-image-input` (issue #18, epic #10)

## The ABI carries images outside JSON

Generation requests cross the C ABI as one JSON payload. Images do not join it:
a multi-megabyte base64 string through a text boundary would double the bytes
and pin them twice. ABI 3 adds a separate borrowed array to
`inferno_engine_generate`:

```c
typedef struct inferno_image_input {
  const uint8_t *bytes;
  size_t length;
} inferno_image_input;
```

Borrowed **for the duration of the call only**. Generation runs on a native
worker that outlives the call, so each shim copies what it needs before
returning, and Dart frees its buffers as soon as the call returns. The load
payload gains an optional `projectorPath`.

Engines decode the image themselves. Dart never rasterizes a photo to hand
pixels across — `libmtmd` already links stb_image, and MLX has CoreImage.

## llama.cpp: libmtmd, built standalone

Upstream supports exactly the configuration this repo wants —
`LLAMA_BUILD_MTMD=ON` with the tools tree off — and `mtmd` links only `ggml`
and `llama`, never `llama-common`, so it adds no dependency. `MTMD_VIDEO` is
forced off rather than left to a default: it needs a subprocess helper the app
has no use for.

A projector is validated in two steps, both before any image is accepted:

1. `mtmd_get_cap_from_file` says whether the file even provides a vision
   encoder, without loading the language model.
2. `mtmd_init_from_file` pairs it with the model. A projector built for a
   different model is refused here as `incompatible_model` — its output
   dimension has to match the model's embedding width, and mtmd checks rather
   than producing noise.

Generation tokenizes through `mtmd_tokenize` and prefills with
`mtmd_helper_eval_chunks`, counting the context budget in mtmd's tokens. A
prompt whose media markers do not match the images supplied is refused. The
projector is released before the model it was initialized against.

The text-only path is untouched, so the recorded cross-engine token fixtures
still assert against exactly the same tokenization.

## Capability is data, split in two

Capability is never inferred from a model name, repository slug, file name, or
engine. Two independent facts have to agree:

- **The catalog entry** says what *this exact artifact on this exact engine* has
  been proven to accept. `gemma4-gguf` declares images; `gemma4-mlx` shares the
  same image-capable template and stays text-only until its own path is
  validated.
- **The profile** says whether its *template* can express an image, and how —
  the media marker, and the conservative per-image token cost windowing needs.

`ModelRuntimeConfig.supportsImages` is the conjunction. The composer gates on
it, the attach sheet disables with copy naming the model, and the repository
refuses an image aimed at a text-only artifact before touching the engine.

## The projector is pinned per file, from its own repository

A multimodal projector is commonly published apart from the quantized weights
it pairs with — ours is `ggml-org` while the weights are unsloth's QAT build.
Manifest files therefore carry an optional per-file repository and revision, and
a role (`weights`, `projector`, `snapshot`) so a GGUF artifact pinning two
`.gguf` files still resolves one language model.

Q8_0 was selected over the BF16 reference on measured evidence:
`docs/evals/2026-08-09-gemma4-mmproj-selection.md`. That record also documents a
grounding failure — chart reading — that occurs identically on both projectors
and is therefore a model limitation, not a selection input.

## Attachments are app-owned, and not excluded from backup

Bytes are copied into an app-owned store on attach, so a conversation never
depends on a photo-library entry the user can delete or revoke. A message
references an opaque store id, never a source path: a transcript, share sheet,
or export cannot leak where a picture came from.

Chat history is the only owner of references. `retainOnly` runs on every
persist against the live conversations, so deleting a message, a conversation,
or all chats collects the bytes, while a session with history off keeps its
pictures readable.

Unlike model weights, attachments are **not** excluded from platform backup.
A model is re-fetchable from Hugging Face; a user's photo is not.

## Intake uses the platform decoder

No image-processing package. `dart:ui`'s codec is the decoder Flutter already
ships, it applies EXIF orientation, and `targetWidth`/`targetHeight` downscale
*during* decode — so an oversized photo never materializes at full size. Bytes
within bounds pass through untouched: re-encoding costs quality for nothing,
since the vision encoder resamples to its own resolution anyway.

`image_picker` and `file_selector` are both flutter.dev packages. The photo
library needs no Android permission because the picker runs out of process
(the Android Photo Picker on 13+), so the app never gains gallery read access.
Camera use is declared on both platforms.

## Scope

Images only. Audio is out of scope even though the pinned Gemma projector also
reports an audio encoder, and nothing advertises it. Video is compiled out.
