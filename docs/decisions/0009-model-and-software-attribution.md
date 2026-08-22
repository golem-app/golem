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
- **Open-source licenses** discloses the third-party software Golem itself
  declares, through native Cupertino UI. Golem lazily registers exact license
  and NOTICE snapshots for the native dependencies Flutter cannot collect.

That screen renders three explicit manifests and nothing else (#144), in
reading order: llama.cpp with its vendored components, the Swift graph the MLX
engine links, then the `dependencies:` block of `app/pubspec.yaml`. The
ordering is `declaredLicensePackagesFor`, assembled from the same const
declarations this record audits, so a pin change moves the screen with it.
`legal_surfaces_test.dart` holds the pub half to `pubspec.yaml`, so a new
dependency is disclosed deliberately rather than by accident.

The Swift half is disclosed only where it exists. `hook/build.dart` builds the
MLX carrier for `OS.iOS` and `OS.macOS` alone; an APK links `libinferno.so`
and nothing from that graph, so naming those sixteen packages on Android would
describe software that is not in the binary. The gate reads `dart:io`'s
`Platform`, never `defaultTargetPlatform` — the golden harness overrides that
through `TargetPlatformVariant`, so an Android golden runs on a macOS host and
would answer the wrong question — and it is injected, so tests drive both arms.
A drift test reads the build hook itself and fails if the carrier stops being
Apple-gated, which keeps the guarantee checked against the build system rather
than restated next to it. The license *text assets* still ship on every
platform: Flutter's pubspec has per-flavor asset keys but no per-platform one.
That is a deliberate wart, roughly 160 KB of unreferenced text in the APK, not
a disclosure problem.

Each row states its license kind. For the bundled declarations that kind is
authored on the declaration, because these are known at pin time and reading
them back out of the text gets them wrong: `miniaudio` is `Unlicense OR MIT-0`,
`stb_image` is `MIT OR Unlicense`, and six Swift packages carry
`Apache-2.0 WITH Swift-exception`. Only the pub half is classified from text,
and a package whose documents disagree — `flutter` files ten, mixing BSD-3 with
an MIT shader notice and a font license — renders no label rather than a
confident wrong one.

Flutter's `LicenseRegistry` carries far more: 243 entries, sweeping the
engine's own `third_party` tree and every dev-time package in the graph, much
of which never reaches a shipping binary. Its collector walks the package
graph rather than the link map and offers no knob to prune what it generates,
so those notices still ship inside the app — they are simply not rendered.
Golem discloses software it chose, not software Flutter compiled.

Model licenses are not on that screen. Golem downloads weights from Hugging
Face after explicit consent and does not redistribute them, so no bundled
notice obligation attaches; **Model attribution** is their home, naming the
license and linking the canonical text upstream. The bundled Apache 2.0
snapshot that once backed an offline copy is gone with them.

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
snapshots. The license is named offline; its full text lives upstream, where
the model card publishes it.

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
- A new direct dependency in `app/pubspec.yaml` fails `legal_surfaces_test`
  until it is added to `directRuntimeLicensePackages`. That is the point: the
  screen is a decision, not a sweep.
- This record documents engineering evidence and distribution handling; it is
  not legal advice.

## Sources reviewed

- Gemma 4 license: <https://ai.google.dev/gemma/apache_2>
- Gemma 4 official model card: <https://huggingface.co/google/gemma-4-E2B-it>
- Qwen 3.5 2B license at audited revision:
  <https://huggingface.co/Qwen/Qwen3.5-2B/blob/965dcc54bc9c0591873df0e9869c056a54d323d1/LICENSE>
- Qwen 3.5 4B official model card:
  <https://huggingface.co/Qwen/Qwen3.5-4B>
