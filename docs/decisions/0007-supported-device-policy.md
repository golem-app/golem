# The supported-device policy: what Golem admits, and who enforces it

Status: decided on `feat/27-device-floor-admission` (issue #27)

The classification and refusal thresholds remain current. ADR 0012 supersedes
the refusal's former access to chats and Settings: the explanation now blocks
the app shell because no supported model can satisfy startup. It also made the
engine platform-owned, so the tier table below names the artifact per platform.
The iOS install floor that follows from that engine is recorded in
[ADR 0016](0016-release-bundle-declarations.md).

Everything before this decision governed the *moment of load*: the
device-model policy picks a lighter model below 7 GiB (#19), the preflight
refuses a load that cannot fit free memory (#62), and the llama shim refuses
a load on a CPU without the ARM dot-product extension (#63). None of them
governed *admission*. A device outside every supported tier could install,
tap the chat banner's consent CTA, spend 1.58 GB fetching weights, and only
then be told — by a load failure — that it can never run them.

This decision adds one classification, taken once at launch, that every
model affordance consults before it offers anything.

## Tiers

| Reported physical memory | Tier | Model |
| --- | --- | --- |
| ≥ 7 GiB | preferred | Gemma 4 E2B — `gemma4-mlx` on iOS (3.58 GB), `gemma4-gguf` elsewhere (3.18 GB) |
| ≥ floor, < 7 GiB | light | Qwen 3.5 2B — `qwen35-2b-mlx` on iOS (1.75 GB), `qwen35-2b-gguf` elsewhere (1.58 GB) |
| < floor | **unsupported** | none |
| unknown | light | Qwen 3.5 2B, as above |

The engine half of each key is the platform's composition under ADR 0012 (MLX
on iOS, llama.cpp/GGUF on Android and macOS); the tier only picks the family.

Plus one non-memory refusal: an **arm64 Android CPU without `FEAT_DotProd`**
is unsupported at any memory size, because the shipped kernels are compiled
for it (`../device_floor.md`) and no amount of free memory changes that.

Since #148 there is a third, which is not a hardware shortfall at all: a
**simulator or emulator** is unsupported however healthy it reads. It is
classified first, ahead of the instruction set, because the other two readings
answer about the host rather than the target — a simulator borrows the Mac's
memory and the MLX shim reports itself available there, so neither of the later
branches would ever fire and the refusal would be worded as a lie. The fact is
answered by the platform itself rather than inferred: `targetEnvironment(simulator)`
is a compile-time constant on Apple, and Android reads the public `Build`
identity (`HARDWARE` `ranchu`/`goldfish` and their Cuttlefish, GCE and VirtualBox
siblings, `sdk`-prefixed products, generic fingerprints). Reaching the refusal
at all takes a real backend on a virtual device: internal identities compose the
fake there instead (ADR 0003), so this is what `production` and an explicit
`GOLEM_INFERENCE_BACKEND` get.

## The floor is nominal, so it is spelled per platform

The floor is **nominal 4 GB — the iPhone 12**, the oldest device this project
is willing to claim. It reaches the code as two constants because the two
platforms report memory differently, for the same reason
`deviceMemoryThresholdBytes` is 7 GiB rather than 8:

- **Apple: 4 GiB.** `ProcessInfo.physicalMemory` reports installed DRAM, so a
  4 GB iPhone reads exactly 4294967296 and the threshold can be the nominal
  figure itself. Below it sit the 3 GB parts — iPhone XR, XS Max's siblings,
  SE 2 and SE 3 — which the App Store gate below cannot exclude.
- **Android: 3 GiB.** `ActivityManager.MemoryInfo.totalMem` is net of
  kernel and firmware reservations. Nominal 4 GB phones report roughly 3.4 to
  3.7 GiB and nominal 3 GB phones about 2.7 GiB, so 3 GiB is the value that
  separates them; 3.5 GiB would misclassify real 4 GB hardware as unsupported.

## Unknown is not a refusal

A probe that fails, times out, or returns nothing leaves the fact unknown,
and unknown classifies as the light tier — never as unsupported. The cost of
being wrong is asymmetric: a wasted download against a permanently unusable
install. The load preflight and the native ISA guard both remain behind this
decision, so an optimistic admission still fails safely and loudly.

## One read, one classification

`resolveConfiguredBackend()` reads the device once — device kind over the
storage channel, then memory over the same channel and engine support over
Inferno's device probe — classifies it, and hands the tier to
`resolveBackendPolicy` while publishing the verdict on
`deviceEligibilityProvider`. The model a build selects and the eligibility its
surfaces report therefore come from the same reading and cannot disagree.

Device kind is read first and on its own, because it decides which engine there
is left to probe: an internal build on a virtual device composes the fake, and
the fake path reads nothing about the device at all.

The engine half is answered by `Inferno.probeDevice()`, which reads a native
free function and creates no engine. The shim reports `available` from the
same `cpu_meets_floor()` predicate its load guard uses, so the early answer
and the late refusal cannot drift apart — and neither can drift from the
`-march=armv8-a+dotprod` flag in `hook/build.dart` that creates the
requirement, since all three live in one package. A `/proc/cpuinfo` parse in
the app layer was rejected for exactly that reason: it would have stated the
rule a third time, in a place with no link to the flag.

## What the refusal does, and does not, take away

An unsupported device may not download and may not load. The all-routes gate
presents the refusal inside the mounted router, with no download or continue action.
Persisted chats, preferences, and files remain untouched for a future launch
on supported hardware or a later compatible release.

## Store alignment, and what no store can do

- **App Store: enforced.** `UIRequiredDeviceCapabilities` gains
  `iphone-ipad-minimum-performance-a12`, which restricts installation to A12
  and later — iPhone XS/XR and up. Apple permits only *expanding* device
  requirements in an update, never restricting them, so a pre-launch app is
  the only place this can be adopted at all. It is a proxy, not the floor:
  A12 admits the 3 GB iPhones, which the in-app policy then classifies as
  unsupported. That gap is inherent — iOS offers no RAM-based store
  filter — and it is why the in-app state exists.
- **Play: console-side, recorded not committed.** Play Console's device
  catalog carries rule-based exclusions on RAM and on system-on-chip
  (Monitor and improve ▸ Reach and devices ▸ Device catalog ▸ Manage
  exclusion rules). The RAM rule is the Android floor's real enforcement and
  belongs on the launch checklist, because no manifest can express it. It
  also cannot be exact: Play warns that RAM varies between variants of a
  device model, so a model can end up partially excluded.
- **`android.hardware.ram.normal` was rejected.** It would filter at the
  manifest level, but it signals Android Go rather than a RAM figure, and
  requiring a feature constant introduced in API 26 would silently drop every
  API 24–25 device as well. A control that excludes the wrong set is worse
  than a documented console step.
- **No store can express the instruction-set requirement.** There is no
  `uses-feature` for an ISA extension, and an SoC exclusion rule would have to
  enumerate every pre-dot-product chip and be maintained forever. The in-app
  probe is the early answer and the shim's load guard remains the backstop.

## Testing what no device here can be

The virtual-device refusal is the one that needs no help: the iPhone 17
simulator and the Android emulator produce it directly, with a `production`
build or an explicit `GOLEM_INFERENCE_BACKEND`. It also closes the other two
there, since it classifies first and the fake path reads nothing at all — the
two overrides below reach the floor and the instruction set on hardware, which
is the only place they were ever needed. The other two are harder —
both team devices report over 8 GB and both carry the dot-product extension,
so neither is reachable on hardware without help.
`GOLEM_DEVICE_MEMORY_BYTES` already existed for the model-tier branch and now
also reaches the floor; `GOLEM_DEVICE_ENGINE_UNSUPPORTED` is its
instruction-set counterpart. Both are test-only, both are dart-defines, and
neither has a UI. The genuinely unsupported hardware case stays unverified by
construction and is recorded as such rather than simulated into a claim.
