# Device floor

What Golem's real-inference builds require of a device, and why. Decided
with epic #61 (tickets #62/#63); the store-side gating that advertises
this floor is #27.

## iOS

- **Install floor: iOS 15.0** (`IPHONEOS_DEPLOYMENT_TARGET`, all Runner
  configurations). 15.0 is the minimum for
  `com.apple.developer.kernel.increased-memory-limit`, which the app
  ships (added with #62) so multi-gigabyte weights plus an 8192-token KV
  cache fit under the jetsam ceiling on supported devices.
- **MLX engine floor: iOS 17** (the `InfernoMLXCarrier` SwiftPM platform
  declaration). Shipping builds compose llama.cpp-Metal (ADR 0002), so
  this floor only binds when MLX is enabled by dart-define.
- Practical memory floor: the device-model policy (ADR 0003) selects the
  lighter Qwen GGUF below 7 GiB reported physical memory; the app's
  supported tier is nominal 8 GB phones.

## Android

- **arm64 with dotprod and i8mm** (armv8.2-a): the Inferno build hook
  passes `-DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+i8mm` for arm64, because
  with `GGML_NATIVE OFF` (cross-compilation) ggml otherwise emits only
  baseline armv8-a kernels and leaves the int8 matmul paths off. Every
  SoC in the app's supported 8 GB tier (Snapdragon 7/8 series,
  Dimensity 8000/9000 era and later) has both extensions; pre-armv8.2
  devices lose the real backend and are outside the floor.
- The `armeabi-v7a` and `x86_64` targets build at their toolchain
  baselines and exist for emulators and compatibility, not for the
  supported real-inference tier.

## Both platforms

- The 7 GiB physical-memory threshold and its rationale live in ADR 0003;
  `GOLEM_DEVICE_MEMORY_BYTES` exercises the light-model branch on
  hardware.
- The load preflight (`availableMemoryBytes`, #62) refuses loads that
  cannot fit free memory plus 512 MiB headroom, with a typed retryable
  failure — the floor governs what we ship to, the preflight governs the
  moment of load.
