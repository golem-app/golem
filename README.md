# Golem (Flutter)

High-fidelity Flutter UI port of native Golem, built for workflow and visual
evaluation without a model runtime. Every model transition and generated
token is a deterministic simulation — the app contains no network client,
model weights, or inference engine.

All Flutter code lives under [`app/`](app/):

```sh
cd app
flutter pub get
flutter analyze
flutter test
flutter build ios --simulator
```

See [`app/README.md`](app/README.md) for the architecture, the asset and
splash pipeline, screen/automation identifiers, and the iPhone 17 simulator
verification workflow.
