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

The app ships as three coexisting build flavors — `production` (**Golem**,
`app.golem`, blue icon), `qa` (**Golem QA**, `app.golem.qa`, red icon), and
`dev` (**Golem Dev**, `app.golem.dev`, green icon) — selected with
`--flavor` (plain commands default to `dev`). QA is the canonical flavor
for automated testing; see [`app/README.md`](app/README.md). The same
flavors exist on iOS, Android, and the macOS desktop target, which opens
as an iPad-shaped resizable window, runs both real engines GPU-accelerated
(llama.cpp-Metal and MLX), and deliberately disables the App Sandbox for
development; Mac results validate correctness, never mobile performance.

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

The GitHub Actions workflow (`.github/workflows/ci.yml`) is deliberately
**disabled while this repository is private**: the org is on the free plan,
macOS runner minutes bill at 10×, and the workflow would exhaust the included
quota mid-month (#31). While it is off, the verification suite above — plus
the golden comparisons that only run on macOS — is the merge gate, and PR
descriptions state that it was run. When the repository goes public, Actions
minutes stop being metered: re-enable with `gh workflow enable ci.yml` and
retire this note.

See [`app/README.md`](app/README.md) for the app architecture, the asset
and splash pipeline, screen/automation identifiers, and the iPhone 17
simulator verification workflow.
