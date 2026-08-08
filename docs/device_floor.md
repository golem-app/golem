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

- **arm64 with dotprod** (`FEAT_DotProd`, ARMv8.2 optional / 8.4
  mandatory): the Inferno build hook passes
  `-DGGML_CPU_ARM_ARCH=armv8-a+dotprod` for arm64, because with
  `GGML_NATIVE OFF` (cross-compilation) ggml otherwise emits only
  baseline armv8-a kernels. ggml chooses its ARM kernels at compile
  time and Inferno ships as one statically linked asset, so whatever
  the flag names is a hard requirement of the binary — not a fast path
  it can fall back from. Hence exactly one extension over the baseline.
- **Enforced at load, not assumed**: the llama shim checks `AT_HWCAP`
  for `ASIMDDP` before the first model load and fails with
  `unsupported_device` ("this device's processor is missing an
  instruction set the local engine needs"). Without it, a device below
  the floor would install cleanly and then take `SIGILL` inside the
  first matmul — `minSdk` is 24, the APK carries no `abiFilters` and no
  CPU `<uses-feature>` (none exists for ISA extensions), so the store
  offers it to every arm64 device. Store-side gating is #27.
- **Deliberately excluded from the floor**: `i8mm` (`FEAT_MatMul_INT8`,
  ARMv8.6) would let ggml emit `SMMLA` in the repacked GEMM and
  `nrows = 2` vec-dot kernels — a large prefill win, but the resulting
  binary requires an ARMv9-era core, cutting out Snapdragon
  855/865/888, Tensor G1/G2, Dimensity 1000/1200 and other 8 GB parts
  inside the supported tier. Raising the baseline to `armv8.2-a` is
  excluded for the same reason: it makes LSE atomics mandatory (clang
  emits `ldaddal` in `ggml_barrier`), which traps on ARMv8.0 devices.
  Recovering i8mm needs runtime dispatch — `GGML_CPU_ALL_VARIANTS` with
  `GGML_BACKEND_DL`, i.e. several shared libraries instead of one code
  asset — which is a separate piece of work, not a compile flag.
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
