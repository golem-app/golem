# ADR 0009: Model and software attribution

- Status: accepted
- Date: 2026-08-11
- Issue: #23

## Context

Golem ships Flutter and native open-source software, but Flutter's generated
license registry only discovers Dart package license files. Inferno also links
native Swift packages and a pinned llama.cpp build. The app downloads model
artifacts after explicit consent, and does not bundle model weights, but users
still need a durable account of each model's author, license, and exact source.

Community model repositories do not always carry reliable license metadata.
In particular, the pinned `mlx-community/gemma-4-e2b-it-4bit` snapshot reports
the legacy `gemma` identifier, while Google's Gemma 4 model card and current
license publish Gemma 4 under Apache 2.0. The official upstream model license
controls; repository metadata is supporting evidence, not the authority.

## Decision

Golem exposes two direct Settings destinations:

- **Model attribution** identifies the official author and Apache 2.0 license
  for Gemma 4 E2B and Qwen 3.5, and lists every immutable Hugging Face source
  and revision in the pinned catalog, including conversion and projector
  repositories.
- **Open-source licenses** renders Flutter's `LicenseRegistry` through native
  Cupertino UI. Golem lazily registers exact license and NOTICE snapshots for
  native dependencies and model families that Flutter cannot collect.

The native manifest mirrors every identity and revision in
`native/apple/Package.resolved`, plus llama.cpp at
`9bd4c09ea571a9020f30eeef169b552625b5b5a4`. The llama.cpp inventory includes
the vendored components that reach the shipping targets: nlohmann/json in the
Inferno shim, and stb_image and miniaudio in libmtmd. Video/subprocess, curl,
server, tools, examples, and tests are disabled by the package CMake options
and are not declared as shipped dependencies.

Gemma 4 E2B is attributed to Google DeepMind under Apache 2.0. The audit covers
the official model card plus the pinned MLX, GGUF, and projector snapshots in
the catalog. Qwen 3.5 2B and 4B are attributed to Alibaba Cloud/Qwen under
Apache 2.0; the audit likewise covers the pinned MLX, GGUF, and projector
snapshots. The complete license text remains available offline.

The audited download sources are:

| Family | Repository | Revision |
| --- | --- | --- |
| Gemma 4 E2B | `mlx-community/gemma-4-e2b-it-4bit` | `238767527555cb75a05732a84dff5d6ba0dd6809` |
| Gemma 4 E2B | `unsloth/gemma-4-E2B-it-qat-GGUF` | `66a399f68ddd113b06dff02fca9523e55465d11d` |
| Gemma 4 E2B projector | `ggml-org/gemma-4-E2B-it-GGUF` | `64ef033dc9f85a88f88e70cceb0a7457366bea64` |
| Qwen 3.5 2B | `mlx-community/Qwen3.5-2B-4bit` | `674aaa7240b91e8012fcad5d791b7dfe5ba90207` |
| Qwen 3.5 2B | `unsloth/Qwen3.5-2B-GGUF` | `f6d5376be1edb4d416d56da11e5397a961aca8ae` |
| Qwen 3.5 2B projector | `prithivMLmods/Qwen3.5-2B-MTP-GGUF` | `d4a4b305fe76ab01b541278d3078cd25c825530a` |
| Qwen 3.5 4B | `mlx-community/Qwen3.5-4B-MLX-4bit` | `32f3e8ecf65426fc3306969496342d504bfa13f3` |
| Qwen 3.5 4B | `YoozLabs/Qwen3.5-4B-qat-GGUF` | `2d52e26bd96b49be5f8d37f1c85b27673adaa7da` |
| Qwen 3.5 4B projector | `prithivMLmods/Qwen3.5-4B-MTP-GGUF` | `dd65086bdcdd7a8f242a2e54cfe11caf8cd51097` |

Repositories supplied manually by a user are outside the pinned catalog.
Their upstream terms continue to govern them, and Golem neither redistributes
nor certifies those repositories.

## Consequences

- A pin update must update the bundled declaration, its exact license/NOTICE
  assets, and this audit when its obligations or compiled graph change.
- A catalog update must classify the official model license, author, and all
  download sources before it can ship.
- Automated drift tests compare Swift and llama pins with the declarations and
  require every referenced asset to exist and contain text.
- This record documents engineering evidence and distribution handling; it is
  not legal advice.

## Sources reviewed

- Gemma 4 license: <https://ai.google.dev/gemma/apache_2>
- Gemma 4 official model card: <https://huggingface.co/google/gemma-4-E2B-it>
- Qwen 3.5 2B license at audited revision:
  <https://huggingface.co/Qwen/Qwen3.5-2B/blob/965dcc54bc9c0591873df0e9869c056a54d323d1/LICENSE>
- Qwen 3.5 4B official model card:
  <https://huggingface.co/Qwen/Qwen3.5-4B>
