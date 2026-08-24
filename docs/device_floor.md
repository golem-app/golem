# Device floor

What Golem's real-inference builds require of a device, and why. The install
and engine floors were decided with epic #61 (tickets #62/#63); the admission
policy that classifies every install against them, and the store gating that
advertises them, are #27 (ADR `decisions/0007-supported-device-policy.md`).

## The supported tiers

| Reported physical memory | Tier | Model (iOS / Android + macOS) |
| --- | --- | --- |
| ≥ 7 GiB | preferred | Gemma 4 E2B — `gemma4-mlx` / `gemma4-gguf` |
| ≥ floor, < 7 GiB | light | Qwen 3.5 2B — `qwen35-2b-mlx` / `qwen35-2b-gguf` |
| < floor (Apple 4 GiB / Android 3 GiB) | unsupported | none |
| unknown | light | Qwen 3.5 2B |

The engine is the platform's build-time composition (ADR 0012: MLX on iOS,
llama.cpp/GGUF on Android and macOS); the tier chooses the family only.

An arm64 Android CPU without `FEAT_DotProd` is unsupported at any memory
size, and so is a simulator or emulator — the platform answers that one about
itself, and it is classified before either hardware reading, both of which
describe the host on a simulator (#148). The floor is one nominal rule — 4 GB,
the iPhone 12 — spelled per platform because Apple reports installed DRAM while
Android reports net of reservations; ADR 0007 carries the derivation. Unknown
never refuses.

## iOS

- **Install floor: iOS 26.0** (`IPHONEOS_DEPLOYMENT_TARGET`, all twelve Runner
  configurations) — the current major only, with iOS 27 weeks away. The
  technical minimum is lower but not by much: the MLX carrier needs 17 and
  is `dlopen`ed by the first native call (the launch probe), so anything
  below it would start and die before its first frame rather than be refused
  by the store. Every phone at or above the memory floor runs 26.
  `com.apple.developer.kernel.increased-memory-limit` (added with #62, so
  multi-gigabyte weights plus an 8192-token KV cache fit under the jetsam
  ceiling) needs only 15.0 and holds. Decided in
  [ADR 0016](decisions/0016-release-bundle-declarations.md).
- **Store gate: A12.** `UIRequiredDeviceCapabilities` names `arm64` and
  `iphone-ipad-minimum-performance-a12`, so the App Store offers the app only
  to iPhone XS/XR and later. It is the closest mechanism iOS has to the
  memory floor — every A12-or-later iPhone has at least 3 GB — but it is not
  the floor: the 3 GB parts it admits are classified unsupported in the app.
  The key needs a deployment target of iOS 14 or later, and Apple permits
  only expanding device requirements in an update. With the install floor
  at iOS 26 the A12 entry is redundant — no A12 phone runs 26 — but a
  capability removed is a requirement contracted, so it stays.
- **MLX engine floor: iOS 17** (the `InfernoMLXCarrier` SwiftPM platform
  declaration, `packages/inferno/native/apple/Package.swift`). Shipping iOS
  builds compose MLX (ADR 0012), so this is the lowest the install floor
  could honestly be; the install floor sits above it by choice. The
  llama.cpp-Metal shim, reachable by dart-define, carries a lower floor of
  its own that never decides anything.

## Android

- **arm64 with dotprod** (`FEAT_DotProd`, ARMv8.2 optional / 8.4
  mandatory): the Inferno build hook passes
  `-DGGML_CPU_ARM_ARCH=armv8-a+dotprod` for arm64, because with
  `GGML_NATIVE OFF` (cross-compilation) ggml otherwise emits only
  baseline armv8-a kernels. ggml chooses its ARM kernels at compile
  time and Inferno ships as one statically linked asset, so whatever
  the flag names is a hard requirement of the binary — not a fast path
  it can fall back from. Hence exactly one extension over the baseline.
- **Answered twice, from one predicate**: `inferno_probe_json()` reports the
  llama engine unavailable where `cpu_meets_floor()` is false, so the app
  classifies the device before offering a download; the same predicate
  refuses the first load with `unsupported_device` if anything reaches it
  anyway. Without either, a device below the floor would install cleanly and
  then take `SIGILL` inside the first matmul — `minSdk` is 24 and there is no
  CPU `<uses-feature>` (none exists for ISA extensions), so the store offers
  the app to every arm64 device the bundle covers.
- **Store gate: a console rule, not the manifest.** Play Console's device
  catalog can exclude by RAM (Monitor and improve ▸ Reach and devices ▸
  Device catalog ▸ Manage exclusion rules); that rule is the Android memory
  floor's enforcement and is part of the launch checklist, since nothing in
  the manifest expresses it. Play notes that RAM varies between variants of a
  model, so exclusion can be partial. `android.hardware.ram.normal` is
  deliberately not declared: it signals Android Go rather than a RAM figure,
  and requiring an API-26 feature constant would silently drop API 24–25
  devices too. No store mechanism can express the dot-product requirement.
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
- **Android is `arm64-v8a` alone** (`defaultConfig.ndk.abiFilters` in
  `app/android/app/build.gradle.kts`, ADR 0010) — every flavor, not just the
  store bundle, so an x86_64 or 32-bit emulator no longer installs any of
  them. Shipping the other ABIs advertised a tier that does not exist:
  `cpu_meets_floor()` is guarded by
  `#if defined(__linux__) && defined(__aarch64__)` and falls through to
  `return true` otherwise, so the dot-product refusal above never fired on
  `armeabi-v7a` or the Android `x86_64` slice. The Inferno hook still knows
  how to cross-compile both; nothing packages them.

## Both platforms

- The 7 GiB threshold and the per-platform floors live in
  `app/lib/core/domain/device_eligibility.dart`; their rationale is in ADR
  0003 (threshold) and ADR 0007 (floors).
- `GOLEM_DEVICE_MEMORY_BYTES` exercises the light-model branch and the floor
  on hardware; `GOLEM_DEVICE_ENGINE_UNSUPPORTED` exercises the
  instruction-set refusal. Both are test-only.
- The load preflight (`availableMemoryBytes`, #62) refuses loads that
  cannot fit free memory plus 512 MiB headroom, with a typed retryable
  failure — the floor governs what we ship to, the preflight governs the
  moment of load, and admission (#27) governs what is offered at all. It
  measures the file, not a working set, and on Android that is load-bearing:
  a 14 GB mixture-of-experts GGUF that reaches `mmap` reboots the OnePlus
  12R (`notes/2026-08-23-turbofieldfare-android-feasibility.md`), and no
  tier above `preferred` exists to offer one.
