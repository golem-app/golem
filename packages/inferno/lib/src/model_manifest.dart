/// What a pinned file is for: the llama engine needs exactly one [weights] file
/// and at most one [projector]; an MLX snapshot is a directory of [snapshot]s.
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

  /// Where this file comes from when that is not the artifact's own repository:
  /// a multimodal projector is commonly published apart from the weights it
  /// pairs with, and pretending otherwise would pin a repository lacking it.
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

/// Full Gemma 4 E2B MLX snapshot. The processor file is pinned because the
/// native VLM path derives dynamic image-token counts from it.
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
      path: 'processor_config.json',
      bytes: 1316,
      sha256:
          'de3e580aebdc98272d4c4547daffe6525fcbae18a83a0e0bcf0d7444d4ee6f37',
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
    // answers, 423 MB (30%) lower median peak resident memory — decisive on the
    // 8 GB tier. Published apart from the QAT weights, hence its own pin.
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

/// Gemma 4 E2B multimodal projector candidates (#18). Evaluation inputs only:
/// one becomes the [InfernoFileRole.projector] on [gemma4E2BGgufQ4]. They are
/// `ggml-org` builds while the shipping weights are unsloth's QAT, so the
/// pairing is a hypothesis the bake-off must prove, not something the matching
/// architecture guarantees.
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

/// Full multimodal MLX snapshot for the low-memory Qwen 3.5 tier.
const qwen35TwoBMlx4Bit = InfernoModelArtifact(
  repository: 'mlx-community/Qwen3.5-2B-4bit',
  revision: '674aaa7240b91e8012fcad5d791b7dfe5ba90207',
  files: [
    InfernoModelFile(
      path: 'chat_template.jinja',
      bytes: 7755,
      sha256:
          '273d8e0e683b885071fb17e08d71e5f2a5ddfb5309756181681de4f5a1822d80',
    ),
    InfernoModelFile(
      path: 'config.json',
      bytes: 3113,
      sha256:
          'beb7fc5a6e0405fe332821cf1a8ef7b69bb390a8c8933171647de5579debf949',
    ),
    InfernoModelFile(
      path: 'model.safetensors',
      bytes: 1722271785,
      sha256:
          '713fe7e5d3c3965f7106b0d0ee17615f7869c23c8d327996df8c1196fbcf07d5',
    ),
    InfernoModelFile(
      path: 'model.safetensors.index.json',
      bytes: 81722,
      sha256:
          '8294c05cca7d53a6c33e3db2b379539bd296d054e0b689711b16b6ac93c7e49d',
    ),
    InfernoModelFile(
      path: 'preprocessor_config.json',
      bytes: 390,
      sha256:
          '27225450ac9c6529872ee1924fcb0962ff5634834f817040f444118116f4e516',
    ),
    InfernoModelFile(
      path: 'processor_config.json',
      bytes: 1300,
      sha256:
          '14932921ca485d458a04dafd8069fbb0a4505622a48208d19ed247115801385b',
    ),
    InfernoModelFile(
      path: 'tokenizer.json',
      bytes: 19989343,
      sha256:
          '87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4',
    ),
    InfernoModelFile(
      path: 'tokenizer_config.json',
      bytes: 1139,
      sha256:
          'e98f1901ac6f0adff67b1d540bfa0c36ac1a0cf59eb72ed78146ef89aafa1182',
    ),
    InfernoModelFile(
      path: 'video_preprocessor_config.json',
      bytes: 385,
      sha256:
          '7768af27c1fafa9cc9011c1dc20067e03f8915e03b63504550e11d5066986d13',
    ),
    InfernoModelFile(
      path: 'vocab.json',
      bytes: 6722759,
      sha256:
          'ce99b4cb2983d118806ce0a8b777a35b093e2000a503ebde25853284c9dfa003',
    ),
  ],
);

/// Multimodal low-memory llama.cpp tier. The Q8_0 projector was selected by
/// the #18 Mac bake-off and is pinned independently from the weights.
const qwen35TwoBGgufQ4 = InfernoModelArtifact(
  repository: 'unsloth/Qwen3.5-2B-GGUF',
  revision: 'f6d5376be1edb4d416d56da11e5397a961aca8ae',
  files: [
    InfernoModelFile(
      path: 'Qwen3.5-2B-Q4_0.gguf',
      bytes: 1214873856,
      sha256:
          'cd70221bebaee0503e0f6717e174250cd7825aa88438b3aabec9ad55731d9bb1',
      role: InfernoFileRole.weights,
    ),
    InfernoModelFile(
      path: 'Qwen3.5-2B.mmproj-q8_0.gguf',
      bytes: 364664384,
      sha256:
          '526dbf85f350baf3a5107b1f14e629e94571c7cbab4277476fbdaaa8c4a31a64',
      role: InfernoFileRole.projector,
      repository: 'prithivMLmods/Qwen3.5-2B-MTP-GGUF',
      revision: 'd4a4b305fe76ab01b541278d3078cd25c825530a',
    ),
  ],
);

/// Qwen 3.5 2B multimodal projector candidates (#18): evaluation inputs until
/// one passes against the exact shipping language artifact through the pinned
/// production `libmtmd` path.
const qwen35TwoBMmprojCandidates = InfernoModelArtifact(
  repository: 'prithivMLmods/Qwen3.5-2B-MTP-GGUF',
  revision: 'd4a4b305fe76ab01b541278d3078cd25c825530a',
  files: [
    InfernoModelFile(
      path: 'Qwen3.5-2B.mmproj-f16.gguf',
      bytes: 671372864,
      sha256:
          '91ea86496a1c02d7cd32fbfa963e103d2a512fa29ca4a22dca1a9c92c3fd30d8',
      role: InfernoFileRole.projector,
    ),
    InfernoModelFile(
      path: 'Qwen3.5-2B.mmproj-q8_0.gguf',
      bytes: 364664384,
      sha256:
          '526dbf85f350baf3a5107b1f14e629e94571c7cbab4277476fbdaaa8c4a31a64',
      role: InfernoFileRole.projector,
    ),
  ],
);

/// Full multimodal MLX snapshot for the larger Qwen 3.5 tier.
const qwen35Mlx4Bit = InfernoModelArtifact(
  repository: 'mlx-community/Qwen3.5-4B-MLX-4bit',
  revision: '32f3e8ecf65426fc3306969496342d504bfa13f3',
  files: [
    InfernoModelFile(
      path: 'chat_template.jinja',
      bytes: 7756,
      sha256:
          'a4aee8afcf2e0711942cf848899be66016f8d14a889ff9ede07bca099c28f715',
    ),
    InfernoModelFile(
      path: 'config.json',
      bytes: 3366,
      sha256:
          'f3efc81b2ea8d96a45301037d3ccccbcccdef44a961845c87f286aaddbc6eaaa',
    ),
    InfernoModelFile(
      path: 'model.safetensors',
      bytes: 3034300695,
      sha256:
          '5fb9acd0246866381cf8c5c354c6db1019f6498eec4ccb4f5edcc71ffeacb2db',
    ),
    InfernoModelFile(
      path: 'model.safetensors.index.json',
      bytes: 101944,
      sha256:
          '52e534c41f7b97708329c85f762e5882bf48bd5955a422c6ae74eba321e6048a',
    ),
    InfernoModelFile(
      path: 'preprocessor_config.json',
      bytes: 390,
      sha256:
          '27225450ac9c6529872ee1924fcb0962ff5634834f817040f444118116f4e516',
    ),
    InfernoModelFile(
      path: 'processor_config.json',
      bytes: 1300,
      sha256:
          '14932921ca485d458a04dafd8069fbb0a4505622a48208d19ed247115801385b',
    ),
    InfernoModelFile(
      path: 'tokenizer.json',
      bytes: 19989343,
      sha256:
          '87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4',
    ),
    InfernoModelFile(
      path: 'tokenizer_config.json',
      bytes: 1139,
      sha256:
          'e98f1901ac6f0adff67b1d540bfa0c36ac1a0cf59eb72ed78146ef89aafa1182',
    ),
    InfernoModelFile(
      path: 'video_preprocessor_config.json',
      bytes: 385,
      sha256:
          '7768af27c1fafa9cc9011c1dc20067e03f8915e03b63504550e11d5066986d13',
    ),
    InfernoModelFile(
      path: 'vocab.json',
      bytes: 6722759,
      sha256:
          'ce99b4cb2983d118806ce0a8b777a35b093e2000a503ebde25853284c9dfa003',
    ),
  ],
);

/// The only language quantization published in the QAT GGUF repository at pin
/// time, paired with the independently validated Q8_0 vision projector.
const qwen35GgufQ4 = InfernoModelArtifact(
  repository: 'YoozLabs/Qwen3.5-4B-qat-GGUF',
  revision: '2d52e26bd96b49be5f8d37f1c85b27673adaa7da',
  files: [
    InfernoModelFile(
      path: 'Qwen3.5-4B-qat-Q4_0.gguf',
      bytes: 2543899040,
      sha256:
          '1367a2b4f8dc63a1782aa1f4006767d5451b8e5d491cc241cb656fbf4b4b5e62',
      role: InfernoFileRole.weights,
    ),
    InfernoModelFile(
      path: 'Qwen3.5-4B.mmproj-q8_0.gguf',
      bytes: 366894656,
      sha256:
          '40a4f07d7bbdbb43011d6cf35ef751e4b1829ff47ee8aa4964c6296f571725ad',
      role: InfernoFileRole.projector,
      repository: 'prithivMLmods/Qwen3.5-4B-MTP-GGUF',
      revision: 'dd65086bdcdd7a8f242a2e54cfe11caf8cd51097',
    ),
  ],
);

/// Qwen 3.5 4B multimodal projector candidates (#18). Evaluated independently
/// from the 2B files: the vision encoders are related, but their language
/// projection dimensions are not compatible.
const qwen35MmprojCandidates = InfernoModelArtifact(
  repository: 'prithivMLmods/Qwen3.5-4B-MTP-GGUF',
  revision: 'dd65086bdcdd7a8f242a2e54cfe11caf8cd51097',
  files: [
    InfernoModelFile(
      path: 'Qwen3.5-4B.mmproj-f16.gguf',
      bytes: 675569216,
      sha256:
          '463f39bd1c291c1186c319a8c90ff8640aafa678b14cbee2232d695113dfbb66',
      role: InfernoFileRole.projector,
    ),
    InfernoModelFile(
      path: 'Qwen3.5-4B.mmproj-q8_0.gguf',
      bytes: 366894656,
      sha256:
          '40a4f07d7bbdbb43011d6cf35ef751e4b1829ff47ee8aa4964c6296f571725ad',
      role: InfernoFileRole.projector,
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
const mlxSwiftLmRevision = '60bd0d7880c82980f9481f8be78862e9b63c58a3';
const mlxSwiftLmVersion = '3.31.4+31.g60bd0d78';
const mlxSwiftRevision = '0bb916c67f4b9e5c682cbe02a42c701c93ab5021';
const mlxSwiftVersion = '0.31.6';
