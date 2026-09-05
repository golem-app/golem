# Inferno

Inferno is Golem's only model-runtime boundary. It is a pure Dart package: it
does not import Flutter, download weights, own chat history, or render model
templates. Callers provide a verified local model path and a fully rendered
prompt.

The v0 public lifecycle is deliberately narrow:

1. probe available engines;
2. load one local model;
3. stream one generation at a time;
4. cancel the active generation;
5. unload the model.

Android and Linux use llama.cpp. Apple targets use MLX Swift when the iPhone
bake-off supports keeping the two-engine architecture. macOS is a development
bench only and is not a v0 acceptance target.

## Safety and threading

All native work is asynchronous. The shared C ABI declares that token, metric,
completion, and error callbacks may arrive from any native worker thread. The
Dart binding receives them through `NativeCallable.listener`, copies callback
bytes before returning, and serializes lifecycle state in Dart. Cancelling a
stream subscription invokes the same native cancellation path as `cancel()`.

Inferno validates whether a path is a file (llama.cpp) or directory (MLX)
before entering native code. Each shim then validates model structure before a
runtime load so missing, corrupt, truncated, incompatible, and wrongly-shaped
inputs become catchable `InfernoException`s instead of process failures.

## Model policy

Immutable revisions, sizes, and SHA-256 values live in
`lib/src/model_manifest.dart`. The production Gemma artifacts are never
bundled, committed, or downloaded by Inferno. The tiny random GGUF is used only
by local/native CI tooling and is fetched into temporary storage.

Gemma-specific templating, reasoning-tag parsing, and end-of-turn policy live in
`app/lib/broker/`. Engines receive raw rendered text and return raw generated
text. BOS/EOS policy is documented and verified at token level in the broker
parity fixture; no engine applies its embedded chat template.

## License

Copyright © 2026 Jan Slominski. Inferno is licensed under the GNU Affero
General Public License, version 3 only (`AGPL-3.0-only`; the text is in
[`LICENSE`](LICENSE), identical to the repository's). The engines it drives
are not part of that grant: llama.cpp (MIT) and the MLX Swift graph (MIT and
Apache-2.0) are fetched at build time under their own licenses, and the app
discloses the ones each build links in Settings ▸ Open-source licenses.
