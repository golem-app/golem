# What Play checks in the native libraries, and what the build was leaving to chance

Status: decided on `chore/25-play-native-library-compliance` (issue #25)

Google Play requires every app targeting API 35+ to support 16 KB memory pages
on 64-bit devices, and has required API 36 of new apps and updates since
2026-08-31. Golem satisfied both before this ticket. It satisfied them by
accident, and an accident is not a property you can ship on.

## Compliant, and none of it was ours

Measured against the production artifacts as they stood at `c57d995`:

| Property | State | Where it came from |
| --- | --- | --- |
| `PT_LOAD` alignment, 64-bit | `libinferno.so` 2\*\*14, `libdartjni.so` 2\*\*14, `libapp.so` and `libflutter.so` 2\*\*16 | NDK r28 links 16 KB-aligned by default |
| `.so` stored uncompressed, 16 KB zip offsets | `zipalign -c -P 16` verified | AGP 9 default (`extractNativeLibs="false"`) |
| `BundleConfig.pb` | `uncompress_native_libraries { enabled: true, alignment: PAGE_ALIGNMENT_16K }` | AGP ≥ 8.5.1 default |
| `targetSdk` | 36 | Flutter 3.44.9's default |
| Page-size assumptions in the engine | none — llama.cpp uses `sysconf(_SC_PAGESIZE)` | upstream |

Not one of those is stated anywhere in this repository. Every one of them is a
toolchain default that a version change can withdraw.

The alignment is the sharpest case. `hook/build.dart` passes no linker options
at all, and Flutter picks the Android NDK by taking the **newest one installed
on the machine** (`AndroidSdk.getNdkBinaryPath`), not the `ndkVersion` Gradle
declares. So the shipped library's Play compliance was decided by which NDK
happened to be present. Rebuilding the same source against NDK r27.2, which is
also installed here, proves it:

| Build | Toolchain | Link options | arm64 `libinferno.so` |
| --- | --- | --- | --- |
| Before | NDK r28.2 (clang 19.0.1) | none | 2\*\*14 |
| Control | NDK r27.2 (clang 18.0.3) | none | **2\*\*12 — Play rejects** |
| Treatment | NDK r27.2 (clang 18.0.3) | explicit | 2\*\*14 |
| Ships | NDK r29.0 (clang 21.0.0) | explicit | 2\*\*14 |

Same source, same compiler, one flag: 4096 becomes 16384.

## Explicit link options, because the NDK's own switch is not a control

`native/llama/CMakeLists.txt` now passes `-Wl,-z,max-page-size=16384` and
`-Wl,-z,common-page-size=16384` for every Android ABI. The NDK's
`ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES` was rejected as the mechanism. Reading
each toolchain's own `build/cmake/flags.cmake`: r26 and earlier do not have it;
r27 treats it as opt-**in** and adds `max-page-size=16384` for the two 64-bit
ABIs; r28 and r29 invert it, acting only when it is set to *false*, where it
*downgrades* to `max-page-size=4096`. Setting it true on r28+ does nothing. A
control whose meaning inverts across the very versions it is supposed to guard
against is not a control. The raw linker options mean one thing on every NDK.

They are applied to all Android ABIs rather than only the 64-bit ones. The rule
binds on 64-bit alone, but a uniform link line cannot be wrong, and on 32-bit it
costs a page of padding.

## The NDK is a pin

`androidNdkVersion` joins the upstream pins in `model_manifest.dart`, and the
build hook refuses any other revision by reading the selected NDK's
`source.properties`. It asserts rather than selects: silently switching the
compiler under the inference hot path is the failure this exists to prevent, so
it fails visibly and names the revision to install.

Two consequences worth stating. The per-target CMake build directory is now
keyed by NDK revision, because CMake keeps the compiler it first cached and will
not swap it inside an existing directory — without the key, a future bump would
relink the previous compiler's objects and the guard would still pass.
And `app/android/app/build.gradle.kts` repeats the literal so AGP strips with
the same toolchain it was compiled with; `pin_consistency_test.dart` and
`app/test/android_packaging_test.dart` hold both copies to the manifest.

The pin moves to r29.0.14206865, the newest stable NDK. That is a two-major
clang jump (19 → 21) across every ggml kernel, so it was measured rather than
assumed — OnePlus 12R, Android 16, `qwen35-2b-gguf`, the twelve-turn soak
regimen at `contextLength=1024`, identical dart-defines on both sides:

| Toolchain | Decode tok/s (mean of 12) | Prefill tok/s (mean of 12) |
| --- | --- | --- |
| NDK r28.2 (clang 19.0.1) | 19.09 (17.43–20.88) | 79.34 (73.88–88.40) |
| NDK r29.0 (clang 21.0.0) | 19.30 (13.90–21.27) | 83.16 (76.53–96.23) |

No regression. The differences sit inside run-to-run variance and are not
quotable as an improvement.

## The store artifact carries arm64 alone

`--target-platform android-arm64` narrows what *Flutter* compiles. It does not
narrow what AGP packages: plugin AARs ship prebuilt libraries for every ABI in
`abiFilters`, and Flutter's Gradle plugin sets that to all three ABIs it
supports. The arm64-only bundle therefore still contained
`base/lib/armeabi-v7a/libdartjni.so` and `base/lib/x86_64/libdartjni.so` — two
ABIs advertised to Play with no Flutter engine behind them. Play would have
offered the app to devices that install it and crash on launch. Flutter's own
plugin comment describes this hazard exactly; its mitigation stops at excluding
32-bit x86.

The override is `abiFilters.clear()` then `add("arm64-v8a")` in `defaultConfig`.
Flutter's plugin populates that set during `apply()`, before the `android {}`
block is evaluated, so clearing it there wins — and `defaultConfig` is the only
place Flutter promises to preserve, since AGP merges flavor and build-type ABI
sets by *union* and no flavor can therefore narrow below it. Flutter's
[breaking-change note](https://docs.flutter.dev/release/breaking-changes/default-abi-filters-android)
documents exactly this. `--target-platform` survives as a build-time saving —
one llama.cpp cross-compile instead of three — never as the correctness
mechanism.

The consequence is that **every** Android build is arm64, not just the store
bundle: `qa` and `dev` APKs no longer install on an x86_64 or 32-bit emulator.
That is accepted rather than worked around. The alternative — the flavor-scoped
filter plus `-Pdisable-abi-filtering` — was built and measured first, and it
buys emulator breadth at a poor price: Flutter says it cannot safely preserve
flavor filters, disabling the plugin's filtering also removes its exclusion of
the 32-bit x86 that plugin AARs still carry (the qa APK grew to 79.6 MB and
gained a `lib/x86/` no engine can serve), and the ABI set ends up restated in
three flavors. Every Android surface this project verifies on is arm64 — the
OnePlus 12R and Apple-silicon emulators — so the breadth was hypothetical and
the failure modes were not. Widening later is one line in `defaultConfig`.

Dropping these two ABIs also closes a hole in the device floor.
`cpu_meets_floor()` in `llama_shim.cpp` is guarded by
`#if defined(__linux__) && defined(__aarch64__)` and otherwise falls through to
`return true`, so the dot-product refusal that ADR 0007 and
`docs/device_floor.md` rely on never fired on either `armeabi-v7a` or the
Android `x86_64` slice. Such a device passed admission, spent 1.2 GB on
weights, and ran generic kernels — a tier ADR 0007 says does not exist.

## Target API 36, and what it turns on

`targetSdk` still follows the Flutter SDK, but the build now refuses to produce
an artifact below 36 rather than discovering it at upload. Targeting 36 also
binds Android 16's edge-to-edge enforcement and its large-screen orientation
changes; both are live on the OnePlus 12R the app is verified on, and neither is
a native-library concern. Anything a pre-launch report raises there belongs to
#28, not here.

## Weights are data, not code

Play's Device and Network Abuse policy restricts downloading executable code.
Golem downloads none: the interpreter is llama.cpp, statically linked inside
`libinferno.so` and shipped in the bundle. What arrives after install is GGUF
weight data, read by that interpreter. This is why the bundle stays at tens of
megabytes against Play's 200 MB compressed-download ceiling, and why keeping the
weights out of it is not in tension with the policy.

## What the artifact proves, and what only the Console can

`tool/check_android_packaging.dart` reads a built APK or bundle and asserts
every property in the first table, plus the ABI set, the native debug symbols
and R8 mapping Play warns about when they are missing, and the absence of
packaged weights. It parses the zip and the ELF headers directly: `zipalign`
cannot read a bundle, `bundletool` is not a checkout dependency, and the entry
offsets the zip-alignment check needs are exposed by neither.

It runs at release time, not in CI, following `verify_pins.dart` — no CI job
builds an Android artifact, and adding one would mean an SDK, an NDK and a
cross-compile for a check that only matters when something ships. The
CI-affordable half is the two text guards over the build files.

What none of it can prove is the last line of the ticket. Play rejects any
upload signed with the Android debug certificate, and release still signs with
the debug keystore, so **the release AAB cannot be uploaded at all until #24
provides an upload key** — no Console validation, no pre-launch report. That
half of #25 is blocked, not deferred, and the ticket's "done when" should say
so.

## Re-checking this at the next bump

A llama.cpp or NDK bump must re-run `tool/check_android_packaging.dart` against
a fresh production bundle. The two text guards fail loudly if the link options
or the pins are dropped, but only the artifact check can see what the toolchain
actually emitted — which is the entire lesson of the table at the top.
