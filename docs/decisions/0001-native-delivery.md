# Native delivery: `hook/build.dart` native assets — selected

Status: decided on `feat/3-inferno`

The sub-issue-zero spike is complete: Dart build hooks assemble and deliver
every native runtime this ticket needs, on every target, without the
binaries-only carrier fallback. The fallback clause is retired.

## Evidence

- **macOS (dev bench):** `dart test` in `packages/inferno` runs the hook,
  which downloads the pinned llama.cpp source archive
  (`9bd4c09ea571a9020f30eeef169b552625b5b5a4`, SHA-256 verified), builds the
  CPU shim via CMake, and builds the MLX carrier via SwiftPM/xcodebuild.
  Full suite: 17/17 with the Gemma fixtures present, including cross-engine
  tokenization parity.
- **Android:** `flutter build apk --release` cross-compiles the llama shim
  through the NDK toolchain file for `arm64-v8a` and `armeabi-v7a`;
  `libinferno.so` ships in the APK. Validated on a OnePlus 12R
  (Android 16): the pinned GGUF loads, streams coherent text, honours stop
  conditions, and cancels mid-generation.
- **iOS:** `flutter build ios --release` builds the llama shim with
  `GGML_METAL` and an embedded metallib plus the MLX Swift carrier;
  validated end to end on an iPhone 17 (iOS 26.6) for both engines — see
  the [iOS engine decision](0002-ios-engine.md).

## Constraints recorded

- Building with hooks required `flutter config --enable-native-assets` once
  per machine on the SDK of the day; `dart test` needed no flag. Since the
  3.47.1 pin native assets are on by default on stable (#12); the switch
  still exists, and a machine that once persisted `--no-enable-native-assets`
  skips the hook and fails the Apple resource-staging phase.
- MLX Swift is Apple-silicon-only. The hook skips the carrier for non-arm64
  Apple slices (Flutter still invokes the hook for x86_64 simulator slices
  regardless of Xcode settings), and the Runner project excludes x86_64
  simulator slices from linking.
- MLX resolves its Metal shader library and tokenizer resources from
  SwiftPM bundles. In the app these are staged by the
  "Stage Inferno Apple Resources" build phase; bare CLI processes instead
  colocate `mlx.metallib` beside the hook-built dylib (the env-gated tests
  stage it automatically).
- The shared build cache lives under `.dart_tool/hooks_runner/shared/`;
  nothing from the native builds enters git.
- On Android 11+ scoped storage, files pushed via `adb` into the app's
  storage are invisible to the app. On-device validation provisions models
  through a debug build and `run-as` into internal storage; production
  model acquisition remains the app's future download flow (out of scope
  here).
