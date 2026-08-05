import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:inferno/testing.dart';
import 'package:test/test.dart';

/// The broker's Qwen 3.5 render of a one-turn conversation with reasoning
/// enabled: ChatML turns, no BOS anywhere, and the primer's open think block.
const _renderedConversation =
    '<|im_start|>user\nHello from the parity fixture.<|im_end|>\n'
    '<|im_start|>assistant\n<think>\n';

/// See tokenization_parity_test.dart: CLI runs colocate the staged metallib
/// beside the hook-built dylib so MLX resolves its shader library.
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
  final ggufPath = Platform.environment['INFERNO_QWEN_GGUF'];
  final mlxPath = Platform.environment['INFERNO_QWEN_MLX'];
  final skipReason = ggufPath == null || mlxPath == null
      ? 'Set INFERNO_QWEN_GGUF and INFERNO_QWEN_MLX for Qwen parity.'
      : false;

  setUpAll(() {
    if (Platform.isMacOS) _stageMetallibForCliRun();
  });

  test(
    'llama.cpp and MLX produce identical Qwen prompt token IDs',
    () async {
      final llama = NativeInfernoTestHarness();
      await llama.load(
        engine: InfernoEngineKind.llamaCpp,
        modelPath: ggufPath!,
      );
      final llamaTokens = await llama.tokenize(_renderedConversation);
      await llama.unload();

      final mlx = NativeInfernoTestHarness();
      await mlx.load(engine: InfernoEngineKind.mlx, modelPath: mlxPath!);
      final mlxTokens = await mlx.tokenize(_renderedConversation);
      await mlx.unload();

      expect(
        llamaTokens.first,
        248045,
        reason:
            'the rendered <|im_start|> is token 248045 and Qwen has no BOS — '
            'nothing may be auto-inserted before it',
      );
      expect(
        llamaTokens,
        contains(248068),
        reason: 'the primer <think> must tokenize as its special token',
      );
      expect(
        llamaTokens,
        contains(248046),
        reason:
            'the rendered <|im_end|> is the stop token the broker supplies — '
            'a drift here means generation never stops',
      );
      expect(mlxTokens, llamaTokens);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
