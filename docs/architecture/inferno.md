# Inferno architecture

The Flutter application depends on `packages/inferno` through the root pub
workspace. Only `app/lib/broker/` may import it. A repository-wide automated
check enforces that boundary.

```text
ChatController -> InferenceRepository -> app/lib/broker
                                        | templates + reasoning parsers
                                        v
                                  Inferno Dart API
                                        |
                               shared asynchronous C ABI (version 5)
                                  /             \
                          llama.cpp shim      MLX Swift shim
                    Android · macOS · iOS*     iOS · macOS*
```

`auto` is platform-owned (ADR 0012): iOS composes MLX, Android composes
llama.cpp/GGUF, macOS keeps llama.cpp. The starred cells are reachable by
`GOLEM_INFERENCE_BACKEND=llama|mlx` and carry no default; iOS ships the MLX
carrier alone, whose iOS 17 is the lowest the install floor could be — it is
set to the current major instead (ADR 0016).

Inferno receives a local path and has no networking. Model acquisition,
verification UI, and catalog UI are separate concerns. The package owns one
loaded model and one active generation. Stream cancellation and the explicit
`cancel()` operation converge on the same native cancellation flag.

## Three calls before any engine exists

- `Inferno.probeDevice()` reads a native free function per engine and
  creates nothing: the operating system, whether each engine is available,
  and — on the llama shim — whether the CPU meets the `FEAT_DotProd` floor the
  shipped kernels require. ADR 0007's admission reads this once at launch;
  the same predicate refuses the first load if anything reaches it anyway.
- The ABI version (`inferno_abi_version`, `INFERNO_ABI_VERSION` in
  `native/include/inferno.h`) is checked per library before the first call,
  because the MLX carrier is a separate binary with its own copy.
- A load crosses as one JSON payload — `modelPath`, `checkTensors`,
  `kvCacheType` (`f16`|`q8_0`), `threadCount`, `gpuLayers`, `swaFull`, and an
  optional `projectorPath` for a multimodal projector. Engines ignore fields
  that do not apply to them.

## Chat templates are the broker's

The broker renders each model's chat template and owns its stop policy; the
shims receive fully rendered prompts and emit raw text. Two profiles ship:

- **Gemma 4** — the pinned `chat_template.jinja` subset with exactly one
  literal `<bos>`. EOS token `1` and end-of-turn token `106` travel with every
  request. `<|channel>thought\n` and `<channel|>` are parsed above the engine,
  including when either marker spans callbacks, and an opening the model
  later labels as reasoning is retracted (`AnswerResetEvent`).
- **Qwen 3.5** — its own template, `<think>` parsing, and a thinking-mode
  sampling recipe pinned against user overrides (#85); the presence penalty
  below exists to break its budget-length think loop.

Both engines tokenize the rendered prompt with automatic BOS insertion
disabled. Token parity is asserted over a checked-in conversation fixture
whose IDs are produced independently by llama.cpp and MLX Swift from the same
rendered bytes. Any future deliberate divergence must update the fixture and
this policy together; a prompt whose two leading tokens are both the
tokenizer's BOS is a hard failure.

## Sampling contract

Generation requests cross the C ABI as one JSON payload: `prompt`,
`maxTokens`, `temperature`, `topP`, `topK`, `contextLength`, `presencePenalty`,
`seed`, `stopSequences`, and `stopTokenIds`. `topK` and `contextLength` are
absent-or-null when unset; both shims treat that — and, defensively, an
explicit zero — as "top-k filtering off" and "no caller budget", so older
payloads keep today's behavior bit for bit. `presencePenalty` (ABI 4) is
null-or-positive: null keeps every penalty out of the sampler chain, a value
applies an additive presence penalty whose window covers the whole
generation. The Dart API never encodes zero for any of the three (it requires
null-or-positive); the shim tolerance exists so the two engines cannot diverge
on a malformed payload. Negative values are invalid on both engines. When
`topK` is set, each engine applies its own upstream filter order (llama.cpp
chains top-k → top-p; MLX applies top-p → min-p → top-k), a deliberate
divergence — token-level sampling parity across engines is not asserted.
`contextLength` is a caller budget over prompt plus `maxTokens`, checked
before decoding on both engines: llama.cpp caps it at the model's trained
context, MLX (whose KV cache is otherwise unbounded) enforces it as the only
bound. Exceeding the budget fails with the same "context budget" generation
error on both engines.

Images do not join the JSON (ADR 0004): `inferno_engine_generate` takes a
separate borrowed array of encoded image bytes, decoded by the engine, valid
for the call only — the shim copies what it needs before returning. The
broker maps each image onto the profile's media marker in the rendered prompt.

## Timing contract

Every generation that does not fail ends with one METRICS event whose numbers are measured
against five boundaries, and whose `timingSemanticsVersion` names the contract
they were measured under. Version 2 (ABI 5, ADR 0020) is the one below.
Version 1 — an absent key, found only in records written before #57 —
started its `timeToFirstTokenSeconds` at the prefill's submission; ADR 0020
records what each engine's columns actually held.

| Boundary | llama.cpp shim | MLX shim |
| --- | --- | --- |
| Request accepted (t0) | first statement of `inferno_engine_generate`, before the image-byte copy and the wait for a retiring worker | first statement of `inferno_mlx_engine_generate`, before the buffer copy and the wait for a retiring operation |
| Prompt evaluation | `prefill_start → prompt_end`: the prefill batch loop (`mtmd_helper_eval_chunks` with images) followed by `llama_synchronize`, because a decode returns once the graph is submitted and the backend settles on the first logits read; tokenization and context/KV allocation precede it | the library's `promptTime`: the prefill run synchronously inside `MLXLMCommon.generate` plus the step that produces the first token; when the library never summarises (a stop sequence broke the loop, or a cancel), the interval from the `generate` call to the first chunk |
| First output token (t1) | stamped after the first `llama_sampler_sample` that is neither end-of-generation nor a stop id, before stop-sequence hold-back | the earlier of two measurements of one instant: the summary's arrival less the library's `generateTime` (the summary is yielded right after that figure is taken, so this lands on the instant the first token was returned, with iterator setup and task dispatch inside), and the wall clock to the first streamed chunk; the first is immune to the streaming detokenizer withholding a token that ends mid-UTF-8 and to the tool-call scanner buffering a reply from its first `{`, the second is what remains when the summary never arrives |
| Decode interval | `elapsedSeconds − timeToFirstTokenSeconds`: what follows the first token, holding one decode step per generated token — the step that yields the next token, or the one that ends the reply | same |
| Total native request latency | t0 → the instant the generation loop stops | t0 → the summary's arrival on a normal completion, which excludes the library's stream teardown; t0 → where the loop was left after a cancel or a stop sequence |

Derived: `timeToFirstTokenSeconds` is t1 − t0 and null exactly when no token
was produced (zero would be a measurement); `elapsedSeconds` is the total
latency; `promptTokensPerSecond` divides `promptTokenCount` by prompt
evaluation, an intra-engine figure because the two windows differ by one
decode step; `decodeTokensPerSecond` is `generatedTokenCount` over the decode
interval — the per-step rate, identical on both engines and recomputable from
the published numbers, down to a one-token reply whose window is the single
step that ended it. A reply cut by a stop sequence skips that last step and
reads slightly high; nothing else does. The bounded wait for a
retiring worker sits inside t0 → t1 on purpose: a caller who cancels and
re-sends waits through it. For every record with a token:
`0 < ttft ≤ elapsed` and `ttft ≥ promptTokenCount / promptTokensPerSecond`.

Cancellation still reports metrics. A cancel before the first token yields
`generatedTokenCount` 0, a null first-token time, a 0 decode rate, and the
elapsed time the request really cost. On MLX a cancel that lands during input
preparation — image decoding runs before tokenization there — also reports a
null prompt token count, because none exists yet. Only a decode failure
replaces the metrics event with an error.

## Native callbacks, cancellation, and teardown

The C header is the source of truth for threading. Load, generation, and
unload work run away from the Dart mutator thread. A callback can originate
from any native worker thread, so Dart uses `NativeCallable.listener` and
copies the callback bytes before returning. Operation IDs reject stale events,
and late events free their payloads through the engine library that allocated
them. The listener deliberately outlives unload/load cycles.

Cancellation is cooperative and its latency is the engine's. llama.cpp honors
it mid-graph through ggml's abort callback and mid-load through the progress
callback, so a cancel lands within one operation. The MLX shim polls at every
boundary it owns — before and after the container load, per image during
preparation, and before prefill — but the library's prefill itself polls
nothing until its first token, so on MLX the bound is one prefill.

Two teardowns exist and they are not interchangeable (#124):

- `releaseEngine()` is **synchronous** and is what `AppLifecycleState.detached`
  runs. Android delivers `detached` without awaiting the handler, and
  predictive back can finish the activity without running Dart at all, so an
  asynchronous unload races the isolate's destruction; a worker that outlives
  the isolate aborts the process from the callback trampoline. Destroying the
  engine blocks until its worker has joined — unbounded on purpose, because a
  timed wait would free the trampoline under a straggling task. The listener
  stays open so `detached → resumed` remains possible.
- `dispose()` unloads, joins, then closes the listener so the isolate can
  exit. The app never calls it; the evaluation harness, which builds one
  adapter per model in a single process, must.

macOS runs both shims GPU-accelerated and is the evaluation and comparison
target: `docs/real-model-matrix.md` records its acceptance cell beside the
phones', and the model-eval harness runs there. Its numbers serve correctness
and relative comparison, never mobile performance.
