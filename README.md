# Golem (Flutter)

High-fidelity Flutter implementation of Golem. The repository is a pub
workspace with two members:

- [`app/`](app/) — the Flutter application. By default every model
  transition and generated token is a deterministic simulation; the app
  ships no model weights and no network client.
- [`packages/inferno/`](packages/inferno/) — the on-device inference
  package: a pure Dart FFI boundary over llama.cpp and MLX Swift shims.
  See [`docs/architecture/inferno.md`](docs/architecture/inferno.md) and
  the decision notes in [`docs/decisions/`](docs/decisions/).

Only [`app/lib/broker/`](app/lib/broker/) may import `package:inferno`;
`tool/check_inferno_imports.dart` enforces that boundary in CI. The broker
owns Gemma chat templating, reasoning-tag parsing, and stop-token policy —
engines receive fully rendered prompts and emit raw text.

The simulated backend is the default in every build. A real local runtime
is opt-in via build configuration:

```sh
flutter run --release \
  --dart-define=GOLEM_INFERENCE_BACKEND=llama \  # or: mlx
  --dart-define=GOLEM_MODEL_PATH=documents:models/gemma.gguf
```

`GOLEM_MODEL_PATH` is an absolute path, or `documents:<relative>` resolved
against the app documents directory. Building with hooks requires
`flutter config --enable-native-assets` once per machine.

Verify (from the repo root):

```sh
cd app && flutter pub get && flutter analyze && flutter test && cd ..
dart run tool/check_inferno_imports.dart
cd packages/inferno && dart test
```

See [`app/README.md`](app/README.md) for the app architecture, the asset
and splash pipeline, screen/automation identifiers, and the iPhone 17
simulator verification workflow.
