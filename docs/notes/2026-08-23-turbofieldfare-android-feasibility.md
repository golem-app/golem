# TurboFieldfare on Android: what the flash delivers, what the model asks for — 2026-08-23

Question: can the TurboFieldfare approach — Gemma 4 26B-A4B with its routed
experts streamed from storage through a bounded per-layer cache, in about
2 GB of RAM — run on Android, and if so through which of the three
candidate directions: a kernel rewrite of the Swift + Metal runtime, the
existing llama.cpp shim with mmap'd weights, or an expert-streaming layer
inside ggml?

This is a spike (#9) under the TurboFieldfare epic (#7). It creates no
product ticket, changes no application behavior, adds one standalone
measurement tool (`tool/expert_read_probe.c`), and makes no release
decision by itself. Device identifiers, local paths, and account data are
excluded; the phone is named by model and OS.

## Sources and environment

- The vendored runtime in the native app's checkout (upstream
  `drumih/turbo-fieldfare`, 10.7k lines of Swift, 4.0k of Metal Shading
  Language, no C) and its installed `gemma4.gturbo` (14.3 GB), read in place.
  Upstream's own `README`, `SYSTEM_DESIGN`, `OPTIMIZATION_JOURNEY`, and
  `BENCHMARKS` for the Mac figures quoted below.
- Golem at `main` @ `4a6bcc7`: the Inferno llama shim and build hook
  (`packages/inferno/native/src/llama_shim.cpp`, `hook/build.dart`,
  `native/llama/CMakeLists.txt`), the pinned llama.cpp source
  (`9bd4c09`, b10241), and the app's load preflight
  (`app/lib/broker/inferno_inference_repository.dart`).
- **OnePlus 12R, Android 16** (Snapdragon 8 Gen 2: one Cortex-X3 at 3.2 GHz,
  four A715/A710 at 2.8 GHz, three A510 at 2.0 GHz; Adreno 740; 15.5 GiB
  reported memory, ≈ 7 GiB available at rest; **UFS 3.1**; f2fs with inline
  encryption; 4 KiB pages; 7.5 GiB zram swap). The adb shell runs in the root
  cpuset with a 64 MiB `RLIMIT_MEMLOCK`. Everything ran from
  `/data/local/tmp` as the shell user; no app was installed and no setting
  was changed.
- A MacBook Pro (M1 Pro, 32 GB) for the miss-rate traces. Its tok/s and its
  I/O times are not quoted as device figures — mobile numbers come from
  mobile; only the *counts* transfer.
- Test artifact on the phone: `ggml-org/gemma-4-26B-A4B-it-GGUF` Q4_0
  (14,618,145,824 bytes, SHA-256 verified against the Hub), chosen over
  Unsloth's UD-Q4_K_XL because Q4_0 is the only quantization the pinned
  OpenCL backend runs `MUL_MAT_ID` for on an Adreno 7xx. It was removed after
  the runs.

## The decision rule, written before the runs

With **B** = bytes read from storage per decode token under TurboFieldfare's
16-slot-per-layer LFU (measured on the Mac, a property of the model and the
cache policy, not of the machine) and **R** = the phone's sustained random-read
throughput at expert granularity, predicted decode is

```
tok/s ≤ 1 / (B / R + t_compute)
```

with `t_compute` measured on the same CPU with every expert resident (Method
S3b, Finding 3). *Feasible for a premium tier* was defined as predicted decode
≥ 3 tok/s **and** a 512-token prefill ≤ 60 s on the OnePlus 12R; anything
else is *not feasible on current Android hardware*.

## What the runtime is, for the port question

- Routed experts live in `packed_experts/layer_XX.bin` as a dense array of
  **3,358,720-byte** blobs (820 × 4 KiB; also 16 KiB-clean): 4-bit affine
  weights, group 64, BF16 scale and bias, for `gate`, `up`, `down`. 30 layers
  × 128 experts; the router picks 8 per token, plus one always-resident
  shared expert. Worst case is 8 × 30 × 3.36 MB = **806 MB per token**.
- Each layer owns a 16-slot cache (LFU with recency tie-break, never decayed)
  filled by parallel `pread` into 2 MiB-aligned `posix_memalign` buffers that
  Metal wraps zero-copy (`makeBuffer(bytesNoCopy:)`); the 1.26 GiB of common
  weights are a read-only `mmap` wrapped the same way. Thirty open layers hold
  1.50 GiB of dirty slot memory; the FP16 KV ring at 4K is ≈ 305 MiB. The
  2 GiB target / 2.2 GiB hard stop is the native app's guard, not the
  package's.
- Upstream measured the alternatives it rejected: demand-paged `mmap` gave
  **0.50 tok/s** against **3.97** for parallel `pread`; the 16-slot cache cut
  expert I/O from 166 to 88 ms/token; LFU over LRU, 72.6 → 64.8. On an 8 GB
  M2 Air decode is 5.1–6.3 tok/s with expert reads costing 83 ms/token; the
  native iPhone 17 integration reports ≈ 3.75 tok/s.
- **Platform-neutral as written**: the `.gturbo` manifest, index, layout,
  receipt and SHA-256 policy; the cache planner; the KV ring arithmetic;
  prefill tiling and expert grouping. All of it is POSIX over `open`,
  `pread`, `fstat`, `mmap`, `posix_madvise`, `posix_memalign`. Swift itself
  is no longer the obstacle: Swift 6.3 ships an official Android SDK.
- **The port is the compute layer**: 38 Metal kernels and ≈ 4k lines of
  Swift that encode them. MSL 4 compiled from source at launch; `bfloat` as a
  device type in every signature; one-SIMD-per-row GEMV with a 32-lane
  assumption baked into lane-indexed offsets (Adreno subgroups are 64 or
  128, Mali's 16); Metal Performance Primitives tensor ops on the fast
  prefill path (optional, with fallbacks); legacy argument buffers for the
  eight routed blobs; and, above all, the unified-memory contract that
  `pread` writes into the very pages the GPU reads. Nothing computes on the
  CPU. On Android that contract needs `VK_EXT_external_memory_host` (or an
  OpenCL equivalent) on every supported GPU, or a 3.36 MB copy per expert
  miss — and ggml's OpenCL backend offers neither (`buffer_from_host_ptr =
  false`; every device tensor is a `set_tensor` copy).

## Method

1. **E3 — miss rates from the real runtime.** A scratchpad copy of the
   upstream checkout (never the vendored one) gained ~20 lines: a global
   counter in `PreadExpertStreamer.executeExpertCachePlan` and an `IOTRACE`
   line per prefill chunk and per decode token from the CLI. Seven chat
   prompts — English, Polish, German; 35 to 1,252 prompt tokens; code, math,
   summarization — at `--temperature 0`, 256 new tokens, production settings
   (16 slots, LFU, 128-token prefill tiles, `rdadvise` off). The first two
   decode tokens are excluded as warm-up.
2. **S2 — the storage probe.** `tool/expert_read_probe.c`, a static NDK
   binary pinned to the five big cores, reading the 14.6 GB GGUF at random
   4 KiB-aligned offsets in 3,358,720-byte units at queue depths 1–16, in
   three regimes: *cold* (`fsync` + `POSIX_FADV_DONTNEED`, **verified by
   `mincore()` over the whole file** — 1,036,379 resident pages → 0, `Cached`
   8.4 → 4.2 GB), *direct* (`O_DIRECT`, which accepts the blob size as-is),
   and *warm* (the same blocks pulled once first). Controls: 4 KiB random
   reads, a demand-paged `mmap` page touch with and without `MADV_RANDOM`, a
   sequential pass, and the little cores. One fixed offset sequence per seed,
   so every condition reads the same blocks in the same order. The matrix
   was run twice, against the 2.6 GB Gemma 4 E2B GGUF already on the phone
   and against the 14.6 GB file; the two agree within noise and the large
   file's numbers are the ones below.
3. **S3 — the llama.cpp control.** `llama-bench` and `llama-completion`
   built from the pinned revision with the hook's own cross-compile
   arguments (NDK r29, `arm64-v8a`, `c++_static`, `armv8-a+dotprod`) as
   static binaries, run with five big cores (`-C 0xF8 --cpu-strict 1`),
   `-r 1 --no-warmup`, with a 2-second sampler of `/proc/meminfo` and the
   process's `/proc/<pid>/io` and major-fault count. Two variants: upstream's
   loader as pinned, and a scratchpad build that honors an environment
   variable to skip `MAP_POPULATE` / `MADV_WILLNEED` (demand paging only).
4. **S3b — the compute term, measured.** A copy of the Q4_0 GGUF with only
   the first 16 of 128 experts per layer (the `ffn_*_exps` tensors, the
   router weight, and `expert_count` sliced with `gguf-py`; 3.34 GB) keeps
   the attention, the shared expert, and 8-of-N routing of the true shape,
   so its per-token compute is the real model's while its output is
   meaningless. It fits the page cache with 8 GB to spare, which is the only
   reason it was allowed near the phone. `llama-bench -p 512 -n 64 -t 5
   -C 0xF8 --cpu-strict 1 -r 2`.
5. **S4 — OpenCL** was conditional on the rule clearing and was not run.

## Findings

### 1. The phone's flash: ≈ 1 GB/s at expert granularity, saturated at queue depth 1–2

OnePlus 12R, 14.6 GB file, big cores, 240 reads of 3,358,720 bytes per row
(= one worst-case decode token):

| Regime | QD | p50 ms / read | p99 ms | Throughput |
| --- | ---: | ---: | ---: | ---: |
| cold (buffered) | 1 | 3.58 | 4.64 | **901 MB/s** |
| cold (buffered) | 2 | 6.53 | 8.12 | 1,002 MB/s |
| cold (buffered) | 4 | 16.8 | 19.4 | 779 MB/s |
| cold (buffered) | 8 | 34.1 | 37.4 | 772 MB/s |
| cold (buffered) | 16 | 67.4 | 72.9 | 772 MB/s |
| `O_DIRECT` | 1 | 2.83 | 3.48 | **1,130 MB/s** |
| `O_DIRECT` | 2 | 5.73 | 7.10 | 1,119 MB/s |
| `O_DIRECT` | 4 | 11.6 | 13.2 | 1,100 MB/s |
| `O_DIRECT` | 8 | 21.9 | 40.8 | 1,110 MB/s |
| `O_DIRECT` | 16 | 46.2 | 69.6 | 1,053 MB/s |
| warm (page cache) | 1 | 0.51 | 2.07 | 5,083 MB/s |
| sequential, cold | 1 | 2.03 | 3.28 | 1,529 MB/s |
| sequential, `O_DIRECT` | 1 | 1.93 | 3.19 | 1,602 MB/s |
| cold (buffered), **little cores** | 1 | 9.21 | 11.7 | 355 MB/s |
| `O_DIRECT`, little cores | 4 | 11.6 | 14.8 | 1,094 MB/s |

Concurrency buys nothing: the device saturates at one or two outstanding
3 MB reads and deeper queues only multiply latency. That is the opposite of
the Mac, where upstream's bounded parallel `pread` is the whole trick. The
buffered path also costs CPU — on the little cores it drops to 355 MB/s while
`O_DIRECT` holds 1.09 GB/s — so a streamer on this class of device should
read `O_DIRECT` into its own aligned slots, which the `.gturbo` stride
already permits.

Demand paging is the trap upstream found, reproduced here. Touching the same
blobs through `mmap` runs at 903 MB/s (3.55 ms per blob) *only because* the
kernel's readahead turns 820 sequential faults into a few large reads; with
`MADV_RANDOM` the same touch takes **110 ms per blob, 30 MB/s**. Random
4 KiB reads sit at 0.17 ms each (22 MB/s at QD1, 126–130 MB/s at QD8). Any
design that faults experts in page by page is dead on arrival.

### 2. What the model asks for: ≈ 266 MB per decode token, and a prefill that reads the whole model every 128 tokens

TurboFieldfare, production settings, Mac traces (counts only):

| Prompt | Prompt tok | New tok | Misses / token (mean · median · max) | MB / token (mean · max) | Prefill misses | Prefill GB |
| --- | ---: | ---: | --- | --- | ---: | ---: |
| short, English | 35 | 58 | 76 · 73 · 146 | 256 · 490 | 1,836 | 6.2 |
| short, Polish | 41 | 219 | 53 · 48 · 153 | 179 · 514 | 1,740 | 5.8 |
| code | 39 | 256 | 84 · 83 · 154 | 283 · 517 | 1,816 | 6.1 |
| medium, English | 624 | 256 | 86 · 81 · 181 | 288 · 608 | 12,425 | 41.7 |
| long, English | 1,230 | 256 | 93 · 90 · 167 | 311 · 561 | 24,320 | 81.7 |
| long, German | 1,252 | 256 | 76 · 75 · 134 | 255 · 450 | 24,334 | 81.7 |
| math | 57 | 256 | 81 · 80 · 151 | 271 · 507 | 2,061 | 6.9 |

Across all 1,536 steady-state decode tokens: **79 misses per token on
average (33 % of the 240 expert reads), p50 78, p90 109, p99 147, max
181** — that is **266 MB per token mean, 366 at p90, 494 at p99, 608 at the
worst token**. The 16-slot LFU is doing real work (a 67 % hit rate), and it
is also the ceiling: the model's routing simply changes more than 16 slots
can hold.

Prefill is the larger number. Every 128-token tile misses **2,350–2,750
experts** — 7.9–9.2 GB — because 128 tokens × 8 experts touches nearly all
128 experts of every layer, and the 16-slot cache cannot carry anything
across tiles. The cost is linear in prompt length at **≈ 67 MB per prompt
token**: 33.4 GB for 512 tokens, 81.7 GB for 1,230.

### 3. The llama.cpp path is not a slow alternative; it is a destructive one

Golem's Android engine is CPU-only ggml with `use_mmap` left on and no MoE
placement control reachable from the shim; what it would do with this model
is exactly what `llama-bench` does. Two attempts, both with five big cores
and the 14.6 GB Q4_0 GGUF against ≈ 7 GiB available (`pp512`/`tg64`, then
the shorter `pp128`/`tg32`):

- **As pinned** (`MAP_POPULATE` + `MADV_WILLNEED` over the whole file, plus
  `POSIX_FADV_SEQUENTIAL`, which is the wrong hint for expert access): the
  phone left the USB bus during load and came back with uptime 0. Boot
  reason `reboot`. No output.
- **Demand paging only** (prefetch disabled in a scratch build): the sampler
  recorded the collapse. In the first 30 s the process read **12.7 GB**
  through 3.2 M major faults while `MemAvailable` fell from 10.5 GB to
  **206 MB** and `Cached` to 427 MB; it then thrashed for four more minutes —
  `read_bytes` climbing to 33.6 GB at ≈ 80 MB/s, load average 55, `adb`
  barely answering — and the OS rebooted the device. The run produced no
  token.

```
t+0 s   MemAvailable 10,519,728 kB   Cached 8,028,552 kB   read  0.02 GB
t+9 s   MemAvailable  5,226,704 kB   Cached 5,423,804 kB   read  5.67 GB
t+16 s  MemAvailable  1,606,400 kB   Cached 1,842,240 kB   read  9.94 GB
t+30 s  MemAvailable    206,368 kB   Cached   427,136 kB   read 12.72 GB
t+45 s  MemAvailable    125,596 kB   Cached   297,744 kB   read 16.01 GB
t+4:33  MemAvailable    166,724 kB   Cached    91,952 kB   read 33.63 GB   → reboot
```

Before this spike the app's load preflight — which compares the *file size*
with `availMem` + 512 MiB — read as a bug for MoE models, since a streamed
model's working set is a fraction of its file. It is in fact the only thing
standing between an Android install and the behavior above, and it must stay
until a loader exists whose resident set is bounded by construction.

Two smaller things the control did establish: `--load-mode dio`
(`O_DIRECT`) works on this f2fs volume (Gemma 4 E2B: pp64 82.4, tg16 26.8
tok/s, against 81.9 / 27.3 with mmap), and the pinned ggml with five pinned
big cores decodes Gemma 4 E2B at **27 tok/s**, where the app's shim with
default threading has measured 8–13.

With every expert resident (S3b), the 26B-A4B's own per-token compute on the
same five cores is **14.76 ± 0.22 tok/s decode (67.7 ms per token) and
35.85 ± 0.22 tok/s prefill** — 3.10 GiB mapped, the phone untroubled. That is
the ceiling any streaming design on this CPU sits under, and it is the
`t_compute` the rule uses.

### 4. The rule applied

`t_compute` is the measured **68 ms** from S3b. It is still generous to the
streaming case: it assumes the routed experts are already in RAM when the
GEMVs run, and that reading and computing do not contend for the same five
cores — which on this SoC they do, since the buffered read path costs CPU
(Finding 1).

| | B | I/O at 1.13 GB/s (`O_DIRECT`) | I/O at 0.90 GB/s (buffered) | Predicted tok/s, serial | Ceiling if compute hides under I/O |
| --- | ---: | ---: | ---: | --- | --- |
| mean token | 266 MB | 235 ms | 296 ms | **3.3 · 2.7** | 4.2 · 3.4 |
| p90 token | 366 MB | 324 ms | 407 ms | 2.6 · 2.1 | 3.1 · 2.5 |
| p99 token | 494 MB | 437 ms | 549 ms | 2.0 · 1.6 | 2.3 · 1.8 |
| worst token | 608 MB | 538 ms | 676 ms | 1.7 · 1.3 | 1.9 · 1.5 |

Prefill, with the compute side at S3b's measured 35.9 tok/s:

| Prompt | Bytes | I/O at 1.13 GB/s | + compute | Wall, serial |
| --- | ---: | ---: | ---: | ---: |
| 512 tokens | 33.4 GB | 30 s | 14 s | **≈ 44 s** |
| 1,230 tokens (one realistic turn of history) | 81.7 GB | 72 s | 34 s | **≈ 106 s** |

Against the pre-registered rule: decode clears 3 tok/s only on the mean
token and only with `O_DIRECT` — it fails at p90 in every column, and the
compute term is measured, so there is no estimate left to be generous with.
A 512-token prefill passes at ≈ 44 s;
a conversation that has grown to 1.2k tokens, which Golem re-prefills on
every turn, waits ≈ 100 s for its first token. **Not feasible as a product
tier on this hardware.** The iPhone 17's measured 3.75 tok/s is the same
design on NVMe-class flash; on the OnePlus 12R's UFS 3.1, storage is the
term that dominates, and it is the term a port cannot engineer away.

Two levers exist and neither is enough on its own. A 512-token prefill tile
(four times the current 15.6 MiB arena) would bound prefill I/O at one full
pass of the experts, 12.9 GB, per 512 tokens — ≈ 25 s for 512 tokens, ≈ 60 s
for 1.2k — still the slowest first token Golem would ever show. A larger
decode cache would raise the hit rate, but the slot memory is the budget:
16 slots already cost 1.50 GiB, 32 would cost 3 GiB, and the device tier
that can spare it is the device tier that does not need streaming.

## Prior art says the same thing

The storage term has been measured before, on phones, by people who built
the predictive machinery TurboFieldfare does not have:

- **PowerInfer-2** (Xue et al., 2024; OnePlus 12, Snapdragon 8 Gen 3, 24 GB,
  UFS 4.0) characterizes the same flash: "UFS storage in mobile devices has
  only one command queue", "using multiple cores for 4KB random reads even
  deteriorates the I/O performance by up to 40%", and random reads issued
  from a big core reach 1 GB/s where a little core manages 760 MB/s — the
  queue-depth and core findings in Finding 1, two years earlier on faster
  storage. With a neuron-level predictor, a five-stage I/O/compute pipeline,
  and a next-layer prefetch, it serves TurboSparse-Mixtral-47B at 11.68
  tok/s when the model mostly fits and at **2.13 tok/s with 7 GB of memory
  available** — the memory this note's phone has, on better flash, with
  every trick applied. Its per-token cache miss rate is 3.5 % on average but
  **18.9 % at p99**; the tail is the product.
- **Ripple** (Wang et al., 2024; OnePlus 12 / Ace 3 / Ace 2, the last on UFS
  3.1): 71.9–97.7 % of decode latency is I/O once half the weights live on
  flash; reads under 24 KB are IOPS-bound, the command queue is 32 entries
  deep, and the remedy is laying correlated neurons out contiguously so reads
  get longer. TurboFieldfare's 3.36 MB blobs are already that remedy taken to
  its limit — there is no read-size lever left.
- **LLM in a flash** (Alizadeh et al., 2023): windowing and row-column
  bundling, "up to twice the size of the available DRAM" — the 2× the
  OnePlus 12R is at, with a dense model whose per-token sparsity a MoE does
  not offer.
- **HOBBIT** (Tang et al., 2024) and **FlashMoE** (2026): next-layer expert
  prediction from the current layer's gating input is 96 % accurate at top-1
  and ≈ 90 % two and three layers ahead; learned recency-plus-frequency
  policies beat LRU/LFU hit rates by up to 51 % on desktop SSDs. These are
  the two levers a future attempt would reach for first. Prediction buys
  overlap, and overlap is bounded by the smaller term: on this phone that
  is the 68 ms of compute under 235 ms of I/O, the "ceiling" column above.
  A better policy raises the hit rate from 67 %; the slot memory that makes
  a higher hit rate affordable is the RAM the device does not have.

## The three directions, priced

**(A) Port TurboFieldfare: Swift via the Android SDK, kernels rewritten for
Vulkan or OpenCL.** The format, planner, receipt, and KV logic carry over;
the tokenizer swaps to `tokenizers`; memory accounting moves from Mach to
`/proc`. The rewrite is 38 kernels plus their encoders, a SPIR-V
ahead-of-time pipeline with ~50 specialization constants, subgroup-width
re-derivation for two GPU families, a `bfloat` fallback in every kernel,
and — the gating risk — zero-copy host-pointer import on every supported
GPU, without which each miss costs a 3.36 MB copy on top of the read. A
capability matrix where Apple has a single floor. Months of work to reach
the 2–3 tok/s and 40–100 s first-token waits above. **Not recommended.**

**(B) llama.cpp as shipped, mmap'd GGUF.** Measured: reboots the reference
device. Even if the page-cache collapse were tamed, demand paging is the
0.5 tok/s path upstream abandoned, and ggml's Adreno OpenCL backend would
not change that — it copies weights into device buffers and disables its
MoE kernels on Adreno 7xx entirely. **Excluded.**

**(C) An expert-streaming buffer type inside ggml** (a `pread`/`O_DIRECT`
slot cache behind `mul_mat_id`, the shape of upstream issue #20757) over the
existing Android shim. The only direction that reuses Golem's engine, keeps
the model-blind shim, and could ship the same GGUF on both platforms. It is
bounded by the same physics — Findings 1 and 2 are properties of the flash
and the model, not of the runtime — so on UFS 3.1 it lands in the same
2–3 tok/s band. **Worth revisiting only when the device floor moves**: a
phone whose flash sustains ≥ 2.5 GB/s at 3 MB random reads (UFS 4.x class)
would put the mean token at ≈ 6 tok/s and a 512-token prefill near 25 s.

## Levers checked, March–August 2026

A second pass asked what recent work would change the terms above. One
more measurement was taken for it: the router's actual choices over 1,552
decode tokens of the seven prompts, logged from the decode loop.

- **Expert pruning (REAP, Cerebras 2510.13999; community 30 % Gemma 4
  checkpoints).** The routing is flat by construction: every layer uses
  110–126 of its 128 experts; the top-32 cover 63 % of activations and 96
  are needed for 98 %; each prompt's top-32 overlaps the global top-32 by
  55 %. A pool that fits RAM discards a third of what the router asks for,
  and the published checkpoints show it (World Religions 90 → 48 at 30 %).
  Not a lever for a general assistant.
- **Lower-bit experts.** The model quantizes unusually badly (3.3× the
  dense 31B's KL divergence at Q8; localbench, 2026-04-14) and its smallest
  2-bit GGUF is 9.9 GB. Does not fit; hurts.
- **Prefetch and expert prediction** (HOBBIT 96 % next-layer; SpecPrefetch
  2607.24787, +8 % on a Snapdragon 8 Elite). Overlap only: bounded by the
  68 ms of compute under 235 ms of I/O — the ceiling column above.
- **Cache policy** (FlashMoE 2601.17063): +7 % end to end on the
  128-expert model in its own table; a Belady oracle is worth ≈ 13 points
  of hit rate (2608.18261).
- **Speculative decoding with streamed experts** (AcceptMoE 2608.02989,
  DraftExpert 2607.24434): verifying a 4-token draft touches ≈ 2.7× the
  experts; Google notes the 26B's "unique routing challenges at batch size
  1". Raises bytes per token.
- **Larger prefill tiles** — the one real lever, and it is the iOS port's:
  TurboFieldfare PR #53 (open 2026-08-02) takes the chunk to 4096 tokens,
  prefill reads 182 → 14 GB on its long prompt, outputs byte-identical. On
  this phone that is ≈ 26 s for 512 tokens and ≈ 45 s for a 1.2k-token
  turn, against ≈ 6 s for the dense model shipped today.
- **Independent phone measurement of this model** (BigMoeOnEdge, stock
  llama.cpp, 12 GB phone, UFS 4.x, 4 GB expert cache): **2.8 tok/s** at
  top-8; 5.0 only at top-6, which changes the output. No prefill numbers.
- **Platform**: UFS 4.1 shares 4.0's PHY and UFS 5.0 devices are 2027;
  Android 17's memory limiter charges page cache to the app (8 GiB visible
  on a 12 GB device) and lmkd kills on page-cache refault thrashing; `O_DIRECT`
  silently falls back to buffered I/O without inline encryption. llama.cpp's
  disk-streaming PR #25294 has had no maintainer review since 2026-07-04;
  MLX has nothing merged; Apple's AFM 3 routes experts per prompt because
  "NAND-to-DRAM bandwidth is too slow to swap weights token by token".

None of it moves decode out of the 2–4 tok/s band on this class of device.

## Recommendation

Do not port TurboFieldfare to Android now, in any of the three shapes.
Record this spike's numbers as the bar a future attempt has to clear, and
keep the following invariants, which the spike found to be load-bearing:

1. The load preflight keeps refusing by file size on Android until a loader
   with a bounded resident set exists. A 14 GB MoE must never reach `mmap`.
2. Admission stays capped at the `preferred` tier; there is no Android
   "premium" tier to design until the storage term changes.
3. If (C) is ever attempted, the streamer reads `O_DIRECT` at queue depth
   1–2 into aligned slots, with a ≥ 512-token prefill tile, and is measured
   with `tool/expert_read_probe.c` on the candidate device *before* any
   engine work.

Two things the pass did surface that are worth doing, neither of them
streaming: the Gemma 4 QAT repositories ship MTP drafters (60–100 MB) that
llama.cpp auto-discovers — a free decode speedup on the resident models
Golem already ships, with unchanged output; and the prefill-tile change above
belongs in the iOS port's plan.

Proposed follow-ups (drafted, not filed): an Android memory channel in
`INFERNO_METRICS` (RSS and major faults — `peakPhysicalFootprintBytes` is
Apple-only and the soak asserts nothing on Android today); and a note on #7
that the iOS port's prefill design should already plan the 512-token tile,
since the 81.7 GB-per-1.2k-token prefill cost is the same on the iPhone.

## Caveats

- The Mac traces used the CLI's `.fullSha256` integrity policy and
  upstream's 128-token tiles; the counts are deterministic at temperature 0
  for these seven prompts and are not a claim about every prompt. The tail
  (p99, max) is from 1,536 tokens.
- `t_compute` is measured with every expert resident (S3b); no engine runs
  this model's routed experts from `pread` slots on this CPU, so the
  contention between reading and computing is not in the number. It is
  generous to the streaming case by construction.
- The OnePlus 12R is a 16 GB device; the measurements that matter (Findings
  1 and 2) do not depend on RAM size, and the one that did (Finding 3) was
  already 2× oversubscribed. An 8 GB phone is 3.5×.
- The cold regime is `POSIX_FADV_DONTNEED`, verified by `mincore()`; it is
  not `drop_caches`, which needs root. `O_DIRECT` is the regime that cannot
  be contaminated, and the two agree.
- The reboots are attributed to the memory collapse by the sampler timeline,
  not by a kernel log (unreadable without root). Nothing else was running.

## How to reproduce

Storage probe (any NDK; the repo pins r29; the probe only reads):

```sh
$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android24-clang \
  -O2 -static -o expert_read_probe tool/expert_read_probe.c
adb push expert_read_probe /data/local/tmp/
adb shell 'cd /data/local/tmp && ./expert_read_probe <big-file> evict && \
  for r in cold direct; do for q in 1 2 4 8 16; do \
    ./expert_read_probe <big-file> pread --qd $q --count 240 --regime $r --cpus 3-7; \
  done; done; \
  ./expert_read_probe <big-file> mmap --count 120 --regime cold --madv random --cpus 3-7'
```

Miss-rate traces: in a copy of upstream `turbo-fieldfare` (`3c48253`), add a
counter to `PreadExpertStreamer.executeExpertCachePlan` (`plan.misses.count`,
`plan.hits`, misses × `layout.expertStride`) and print it with
`runner.totalIoNanos` from the CLI's progress callback on every `.prefill`
and `.token` event; `swift build -c release --product TurboFieldfareCLI`; run
`--messages-file <prompt>.json --max-new 256 --temperature 0` and diff
consecutive token lines.

Compute ceiling (S3b): prune the GGUF with `gguf-py` from the pinned
llama.cpp source — copy every field and tensor, slice `blk.*.ffn_*_exps.*`
and `blk.*.ffn_gate_inp.weight` to their first 16 experts along the outermost
axis, and set `gemma4.expert_count` to 16 — then confirm the file is smaller
than `MemAvailable` before pushing it, and run
`llama-bench -m <pruned.gguf> -p 512 -n 64 -t 5 -C 0xF8 --cpu-strict 1 -r 2`.

The llama.cpp control is **not** to be repeated on a phone: both variants
rebooted the device. Build it only for the `dio` smoke on a small model:
from the pinned source with the hook's Android arguments plus
`-DLLAMA_BUILD_TOOLS=ON -DLLAMA_BUILD_COMMON=ON -DBUILD_SHARED_LIBS=OFF
-DLLAMA_CURL=OFF -DLLAMA_BUILD_MTMD=OFF`, then
`llama-bench -m <small.gguf> -p 64 -n 16 -t 5 -C 0xF8 --cpu-strict 1 -r 1
--no-warmup -lm mmap,dio`.
