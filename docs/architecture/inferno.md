# Inferno v0 architecture

The Flutter application depends on `packages/inferno` through the root pub
workspace. Only `app/lib/broker/` may import it. A repository-wide automated
check enforces that boundary.

```text
ChatController -> InferenceRepository -> app/lib/broker
                                        | template + reasoning parser
                                        v
                                  Inferno Dart API
                                        |
                               shared asynchronous C ABI
                                  /             \
                          llama.cpp shim      MLX Swift shim
                         Android + Linux          iOS
```

Inferno receives a local path and has no networking. Model acquisition,
verification UI, and catalog UI are separate concerns. The package owns one
loaded model and one active generation. Stream cancellation and the explicit
`cancel()` operation converge on the same native cancellation flag.

## Gemma 4 text contract

The broker renders the pinned `chat_template.jinja` subset used by v0 text
chat, including exactly one literal `<bos>`. Both native engines tokenize the
rendered prompt with automatic BOS insertion disabled. EOS token `1` and
end-of-turn token `106` are supplied with every request; engines never infer
stop policy from an embedded template. `<|channel>thought\n` and `<channel|>`
are parsed above the engine, including when either marker spans callbacks.

Token parity is asserted over a checked-in conversation fixture. The recorded
IDs are produced independently by llama.cpp and MLX Swift from the same
rendered bytes. Any future deliberate divergence must update the fixture and
this policy together; a prompt whose two leading tokens are both the
tokenizer's BOS is a hard failure.

## Sampling contract

Generation requests cross the C ABI as one JSON payload: `prompt`,
`maxTokens`, `temperature`, `topP`, `topK`, `contextLength`, `seed`,
`stopSequences`, and `stopTokenIds`. `topK` and `contextLength` are
absent-or-null when unset; both shims treat that — and, defensively, an
explicit zero — as "top-k filtering off" and "no caller budget", so older
payloads keep today's behavior bit for bit. The Dart API itself never
encodes zero (it requires null-or-positive); the shim tolerance exists so
the two engines cannot diverge on a malformed payload. Negative values
are invalid on both engines. When `topK` is set, each engine applies its
own upstream filter order
(llama.cpp chains top-k → top-p; MLX applies top-p → min-p → top-k), a
deliberate divergence — token-level sampling parity across engines is not
asserted. `contextLength` is a caller budget over prompt plus `maxTokens`,
checked before decoding on both engines: llama.cpp caps it at the model's
trained context, MLX (whose KV cache is otherwise unbounded) enforces it as
the only bound. Exceeding the budget fails with the same
"context budget" generation error on both engines.

## Native callbacks

The C header is the source of truth for threading. Load, generation, and unload
work run away from the Dart mutator thread. A callback can originate from any
native worker thread, so Dart uses `NativeCallable.listener` and copies the
callback bytes before returning. Operation IDs reject stale events, and
late events free their payloads through the engine library that allocated
them. The listener deliberately outlives unload/load cycles; `dispose()`
closes it once the runtime is finished so the isolate can exit.

macOS is a convenient place to develop and compare both shims, but it carries
no v0 smoke-test obligation.
