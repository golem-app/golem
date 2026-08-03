final class InfernoModelFile {
  const InfernoModelFile({
    required this.path,
    required this.bytes,
    required this.sha256,
  });

  final String path;
  final int bytes;
  final String sha256;
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

const llamaCppRevision = '9bd4c09ea571a9020f30eeef169b552625b5b5a4';
const llamaCppRelease = 'b10241';
const mlxSwiftLmRevision = 'bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57';
const mlxSwiftLmVersion = '3.31.4';
const mlxSwiftRevision = '0bb916c67f4b9e5c682cbe02a42c701c93ab5021';
const mlxSwiftVersion = '0.31.6';
