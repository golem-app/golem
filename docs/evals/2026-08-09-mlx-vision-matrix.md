# MLX vision acceptance matrix

This evaluation decides which pinned Apple MLX artifacts may expose image
input in GOLEM. It also records why Gemma 4 E2B initially appeared unusable
and the upstream implementation required to load it correctly.

## Environment

- MacBook Pro, Apple M1 Pro, 32 GB
- macOS 26.6.1
- Inferno ABI 3, broker-rendered prompts, one image per graded request
- `mlx-swift-lm` pinned to
  `60bd0d7880c82980f9481f8be78862e9b63c58a3`
- seed 7, 4096-token context, maximum 64 generated tokens

The peak is the process physical-footprint high-water mark, not model weights
alone. Each artifact was loaded in a fresh process and evaluated on the same
five fixtures: OCR, colour, object count, left/right spatial relation, and a
three-bar chart.

## Exact artifacts

| Catalog artifact | Repository | Revision |
| --- | --- | --- |
| Gemma 4 E2B MLX 4-bit | `mlx-community/gemma-4-e2b-it-4bit` | `238767527555cb75a05732a84dff5d6ba0dd6809` |
| Qwen 3.5 2B MLX 4-bit | `mlx-community/Qwen3.5-2B-4bit` | `674aaa7240b91e8012fcad5d791b7dfe5ba90207` |
| Qwen 3.5 4B MLX 4-bit | `mlx-community/Qwen3.5-4B-MLX-4bit` | `32f3e8ecf65426fc3306969496342d504bfa13f3` |

Every downloaded file, including each processor configuration, is pinned by
byte count and SHA-256 in Inferno's manifest.

## Results

| Artifact | OCR | Colour | Count | Spatial | Chart | Peak footprint |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Gemma 4 E2B MLX 4-bit | pass | pass | pass | pass | pass | 4.14 GB |
| Qwen 3.5 2B MLX 4-bit | pass | pass | **fail** | pass | pass | 2.53 GB |
| Qwen 3.5 4B MLX 4-bit | pass | pass | pass | pass | pass | 4.05 GB |

Gemma answered the five graded facts as `MEN WALK ON MOON`, `Red`, `3`,
`left`, and `Right`. Qwen 2B recognized the three squares but over-analysed
instead of returning the requested count; the other four cases were correct.
Qwen 4B passed all five. Observed decode rates were about 61–72 tok/s for
Gemma, 99–122 tok/s for Qwen 2B, and 50–52 tok/s for Qwen 4B.

The final Qwen runs use `UserInput.Processing(maxPixels: 262144)`, an
aspect-preserving 512²-equivalent ceiling. The original one-megapixel setting
produced the same Mac answers but made Qwen 4B the largest process on the
iPhone at 345,364 16 KiB pages (about 5.27 GiB); iOS killed it for
`vm-pageshortage` during vision prefill. At 262,144 pixels, 2B retained the
same four passes and the same count miss, while 4B retained all five passes.
The lower peaks in the table are the final bounded-pixel runs.

## Gemma loader finding

The former `mlx-swift-lm` pin failed while loading the E2B weights at layer 15
because its VLM loader created K/V projection parameters for layers whose
weights are shared. Upstream PR
[#384](https://github.com/ml-explore/mlx-swift-lm/pull/384) taught the Gemma 4
VLM loader to honor `num_kv_shared_layers` and added E2B/E4B integration-load
coverage. PR
[#405](https://github.com/ml-explore/mlx-swift-lm/pull/405) then matched the
reference aspect-preserving resize, used dynamic per-image token counts, and
fixed multi-image requests. The latter merged as the revision pinned above.

GOLEM copies that processing boundary without giving template ownership to
MLXVLM: the broker remains authoritative, emits `<__media__>` in the ordered
message parts, and the native shim replaces and expands those placeholders
after image preprocessing. It never applies a second chat template.

## Decision

Gemma 4 E2B MLX and both Qwen 3.5 MLX artifacts expose image input. Qwen MLX
processing is capped at 262,144 pixels per image; the app's cross-engine intake
still caps decoded attachments at one megapixel, and context windowing reserves
1,280 visual tokens per image. Profile capability alone does not imply artifact
capability; the separate
[Qwen GGUF projector bake-off](2026-08-09-qwen35-mmproj-selection.md) later
validated and enabled both llama.cpp artifacts.

The Qwen 2B count miss is a recorded quality limitation, not a transport or
processor failure. The 4B artifact is the stronger vision choice where memory
allows; 2B remains useful on lower-memory Apple devices.

## Physical iPhone acceptance

All three catalog-backed MLX paths were accepted through the actual app on an
iPhone 17 running iOS 26.6, using the separate `app.golem.qa` bundle. The
snapshots were cable-copied into QA Documents, then the app's normal download
action hashed every pinned file and wrote its verification receipt; no model
was trusted from size alone. Each Qwen result came from a separately created,
empty chat whose header named the exact boot-selected catalog artifact.

Through the real iOS photo picker, composer tray, attachment store, persisted
chat history, broker, ABI, and MLXVLM shim, the model identified the main object
in a non-personal test photo as a gray car parked in front of a garage. The
settled app response reported 25.8 decode tok/s and 19 generated tokens. The
answer was produced after an app update and relaunch from the attachment in
chat history, proving durable attachment reads rather than only an in-memory
picker handoff.

On the final bounded-pixel build, Qwen 2B described the same photo as “A gray
hatchback car is parked on a paved lot next to a building with a white roller
door.” It settled at 35.4 decode tok/s for 21 tokens. Qwen 4B identified the
car more specifically as a Volkswagen Golf Mk2 and remained grounded while
over-answering the requested brevity; it settled at 16.7 tok/s for 261 tokens.

The first 4B one-megapixel attempt generated the jetsam record described above.
After reducing only the upstream processor's pixel budget—and rerunning both
Mac matrices—it completed on the same phone without eviction. The final build
also kept the sent-image frame mounted across generation-state rebuilds; the
visible double blink reported during the first runs no longer reproduced.
