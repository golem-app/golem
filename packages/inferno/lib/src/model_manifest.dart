/// What a pinned file is for. An artifact's loadable path depends on it: the
/// llama engine needs exactly one [weights] file and at most one [projector],
/// while an MLX snapshot is a directory of [snapshot] files.
enum InfernoFileRole { weights, projector, snapshot }

final class InfernoModelFile {
  const InfernoModelFile({
    required this.path,
    required this.bytes,
    required this.sha256,
    this.role = InfernoFileRole.snapshot,
    this.repository,
    this.revision,
  });

  final String path;
  final int bytes;
  final String sha256;
  final InfernoFileRole role;

  /// Where this individual file comes from, when that is not the artifact's
  /// own repository. A multimodal projector is commonly published separately
  /// from the quantized weights it pairs with, and pretending otherwise would
  /// mean pinning a repository that does not contain the file.
  final String? repository;
  final String? revision;
}

final class InfernoModelArtifact {
  const InfernoModelArtifact({
    required this.repository,
    required this.revision,
    required this.files,
  });

  final String repository;
  final String revision;
  final List<InfernoModelFile> files;
}

/// Text-only MLX snapshot. Vision/audio processor files are intentionally out.
const gemma4E2BMlx4Bit = InfernoModelArtifact(
  repository: 'mlx-community/gemma-4-e2b-it-4bit',
  revision: '238767527555cb75a05732a84dff5d6ba0dd6809',
  files: [
    InfernoModelFile(
      path: 'chat_template.jinja',
      bytes: 17336,
      sha256:
          '2f1b4d75d067bae3fe44e676721c7f077d243bc007156cb9c2f8b5836613d082',
    ),
    InfernoModelFile(
      path: 'config.json',
      bytes: 6395,
      sha256:
          '6397cb6eca41b911d1dcab74e17941351057bd759284052a2331918ff6f9246c',
    ),
    InfernoModelFile(
      path: 'generation_config.json',
      bytes: 208,
      sha256:
          'd4226bbe3117d2d253ba4609720ba82c6c4ce4627a9a6ae05387c78983ac03de',
    ),
    InfernoModelFile(
      path: 'model.safetensors',
      bytes: 3550670554,
      sha256:
          '038e39a37a7667373d2c3991375446b10c96ae1d717a68674870343db376b76e',
    ),
    InfernoModelFile(
      path: 'model.safetensors.index.json',
      bytes: 218323,
      sha256:
          'edb157dbf495e23f37377af4a628a9ad13c4ee7937f93ccb36ec9e9a19940f16',
    ),
    InfernoModelFile(
      path: 'tokenizer.json',
      bytes: 32169626,
      sha256:
          'cc8d3a0ce36466ccc1278bf987df5f71db1719b9ca6b4118264f45cb627bfe0f',
    ),
    InfernoModelFile(
      path: 'tokenizer_config.json',
      bytes: 2740,
      sha256:
          '080d9e1aff284e2f6043889cd05367966f7c7b80e025fbc0b06745e218158656',
    ),
  ],
);

const gemma4E2BGgufQ4 = InfernoModelArtifact(
  repository: 'unsloth/gemma-4-E2B-it-qat-GGUF',
  revision: '66a399f68ddd113b06dff02fca9523e55465d11d',
  files: [
    InfernoModelFile(
      path: 'gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
      bytes: 2620370976,
      sha256:
          'e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889',
      role: InfernoFileRole.weights,
    ),
    // Selected over the BF16 reference by the #18 bake-off: identical graded
    // answers, 423 MB (30%) lower median peak resident memory — decisive on
    // the 8 GB tier this app supports. Published separately from the QAT
    // weights, hence its own repository pin.
    InfernoModelFile(
      path: 'mmproj-gemma-4-E2B-it-Q8_0.gguf',
      bytes: 557368064,
      sha256:
          '9406f99c16d68cda4f1f0552192dcc99021ea1fc6d2fd50b1dc3ccf30d04b292',
      role: InfernoFileRole.projector,
      repository: 'ggml-org/gemma-4-E2B-it-GGUF',
      revision: '64ef033dc9f85a88f88e70cceb0a7457366bea64',
    ),
  ],
);

/// Gemma 4 E2B multimodal projector candidates (#18).
///
/// Evaluation inputs, not a shipping artifact: the 16-bit reference and the
/// Q8_0 candidate are compared on the production path, and only the selected
/// one becomes a [InfernoFileRole.projector] file on [gemma4E2BGgufQ4].
///
/// They are published by `ggml-org` while the shipping weights are unsloth's
/// QAT build, so the pairing is a hypothesis this bake-off has to prove, not
/// something the matching architecture guarantees.
const gemma4E2BMmprojCandidates = InfernoModelArtifact(
  repository: 'ggml-org/gemma-4-E2B-it-GGUF',
  revision: '64ef033dc9f85a88f88e70cceb0a7457366bea64',
  files: [
    InfernoModelFile(
      path: 'mmproj-gemma-4-E2B-it-BF16.gguf',
      bytes: 986833664,
      sha256:
          '711e1e8f43fa0664adbac493129be1e6c25b81af4b4cdea97c7d798b25c0a3a4',
      role: InfernoFileRole.projector,
    ),
    InfernoModelFile(
      path: 'mmproj-gemma-4-E2B-it-Q8_0.gguf',
      bytes: 557368064,
      sha256:
          '9406f99c16d68cda4f1f0552192dcc99021ea1fc6d2fd50b1dc3ccf30d04b292',
      role: InfernoFileRole.projector,
    ),
  ],
);

/// Text-only MLX snapshot of the QAT lean-4bit build; the only 4B QAT MLX
/// variant published at pin time.
const qwen35Mlx4Bit = InfernoModelArtifact(
  repository: 'YoozLabs/Qwen3.5-4B-qat-lean-4bit-mlx',
  revision: 'dc6b06e7ac5279a1d3ac716342644efe848dfcb7',
  files: [
    InfernoModelFile(
      path: 'chat_template.jinja',
      bytes: 7756,
      sha256:
          'a4aee8afcf2e0711942cf848899be66016f8d14a889ff9ede07bca099c28f715',
    ),
    InfernoModelFile(
      path: 'config.json',
      bytes: 2426,
      sha256:
          '4b8c4af0434e57f2b2c49b885d5deac288a0fd53d596cb3f6b87bb70aadb0d3e',
    ),
    InfernoModelFile(
      path: 'generation_config.json',
      bytes: 108,
      sha256:
          '757083276a24890fd6a94876bdaa460b3d1232cba3fa8b998c4188a0cea5764d',
    ),
    InfernoModelFile(
      path: 'model.safetensors',
      bytes: 2367237149,
      sha256:
          '36f7f2d16e6eac68e6638976de2c48372af22d77a46026e270af1fdf2566c909',
    ),
    InfernoModelFile(
      path: 'model.safetensors.index.json',
      bytes: 81008,
      sha256:
          '5a3779ecc1a94f395f26612fdc9a491c1884250eda9353d214322717564a69c7',
    ),
    InfernoModelFile(
      path: 'tokenizer.json',
      bytes: 19989325,
      sha256:
          '06b9509352d2af50381ab2247e083b80d32d5c0aba91c272ca9ff729b6a0e523',
    ),
    InfernoModelFile(
      path: 'tokenizer_config.json',
      bytes: 1161,
      sha256:
          '95c557768e6b88a7128befc7bfd3c7de50e5d51af9b8b33a9f4dee0e04f99679',
    ),
  ],
);

/// The only quantization published in the QAT GGUF repository at pin time.
const qwen35GgufQ4 = InfernoModelArtifact(
  repository: 'YoozLabs/Qwen3.5-4B-qat-GGUF',
  revision: '2d52e26bd96b49be5f8d37f1c85b27673adaa7da',
  files: [
    InfernoModelFile(
      path: 'Qwen3.5-4B-qat-Q4_0.gguf',
      bytes: 2543899040,
      sha256:
          '1367a2b4f8dc63a1782aa1f4006767d5451b8e5d491cc241cb656fbf4b4b5e62',
    ),
  ],
);

/// Small random-weight model fetched only by native CI and local test tooling.
const infernoToyGguf = InfernoModelArtifact(
  repository: 'aladar/tiny-random-LlamaForCausalLM-GGUF',
  revision: '6a57244a5aa2fcff3bd09899c8266a6a2df714a9',
  files: [
    InfernoModelFile(
      path: 'tiny-random-LlamaForCausalLM.gguf',
      bytes: 2789632,
      sha256:
          'f411bb6b67997e9d9e769c2d8438acd9759a4a3b2dc258500eeeb3c715d23e96',
    ),
  ],
);

// Each release/version constant names the upstream tag whose commit is the
// paired revision. Nothing in CI ties the pairs together — after bumping
// any of them, run `dart run tool/verify_pins.dart` (network) to confirm.
const llamaCppRevision = '9bd4c09ea571a9020f30eeef169b552625b5b5a4';
const llamaCppRelease = 'b10241';
const mlxSwiftLmRevision = 'bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57';
const mlxSwiftLmVersion = '3.31.4';
const mlxSwiftRevision = '0bb916c67f4b9e5c682cbe02a42c701c93ab5021';
const mlxSwiftVersion = '0.31.6';
