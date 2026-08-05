@Tags(['real-model'])
library;

import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:inferno/testing.dart';
import 'package:test/test.dart';

const _renderedConversation =
    '<bos><|turn>system\n<|think|>\n<turn|>\n'
    '<|turn>user\nHello from the parity fixture.<turn|>\n'
    '<|turn>model\n';

/// MLX resolves its shader library beside the loaded binary
/// (`current_binary_dir()/mlx.metallib`) before falling back to app-bundle
/// lookups. Inside the app the staged `mlx-swift_Cmlx.bundle` provides it,
/// but `dart test` loads the hook-built dylib from `.dart_tool/lib/`, so CLI
/// runs colocate the staged metallib there first.
void _stageMetallibForCliRun() {
  final dylib = File('.dart_tool/lib/libinferno_mlx.dylib');
  final metallib = File(
    'build/apple-resources/macosx/mlx-swift_Cmlx.bundle/'
    'Contents/Resources/default.metallib',
  );
  if (dylib.existsSync() && metallib.existsSync()) {
    metallib.copySync('${dylib.parent.path}/mlx.metallib');
  }
}

void main() {
  final ggufPath = Platform.environment['INFERNO_GEMMA_GGUF'];
  final mlxPath = Platform.environment['INFERNO_GEMMA_MLX'];
  final skipReason = ggufPath == null || mlxPath == null
      ? 'Set INFERNO_GEMMA_GGUF and INFERNO_GEMMA_MLX for the bake-off.'
      : false;

  setUpAll(() {
    if (Platform.isMacOS) _stageMetallibForCliRun();
  });

  test('llama.cpp and MLX produce identical raw prompt token IDs', () async {
    final llama = NativeInfernoTestHarness();
    await llama.load(engine: InfernoEngineKind.llamaCpp, modelPath: ggufPath!);
    final llamaTokens = await llama.tokenize(_renderedConversation);
    await llama.unload();

    final mlx = NativeInfernoTestHarness();
    await mlx.load(engine: InfernoEngineKind.mlx, modelPath: mlxPath!);
    final mlxTokens = await mlx.tokenize(_renderedConversation);
    await mlx.unload();

    expect(llamaTokens.first, 2, reason: 'the rendered <bos> is token 2');
    expect(
      llamaTokens.take(2),
      isNot(everyElement(2)),
      reason: 'automatic BOS insertion must stay disabled',
    );
    expect(mlxTokens, llamaTokens);
  }, skip: skipReason);
}
