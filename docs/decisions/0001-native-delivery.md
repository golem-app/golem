# Native delivery feasibility

Status: in progress on `feat/3-inferno`

Target: `hook/build.dart` compiles and bundles the llama.cpp shim for Linux and
Android, and supplies Apple-compatible assets with a consistent library name.
The spike is deliberately first because Dart build hooks and SwiftPM/XCFramework
composition are the highest-risk integration point.

If the hook cannot reproducibly assemble MLX Swift's Swift/Metal dependency
graph, v0 may use a binaries-only carrier that exports the same `inferno.h` ABI.
That fallback must pin its inputs and preserve the pure-Dart package and broker
boundaries; it is not permission to create a Flutter method-channel plugin.

The final decision, commands, failure evidence, and artifact provenance will
replace this section before review.
