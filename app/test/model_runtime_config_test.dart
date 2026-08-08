import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/broker/model_runtime_config.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';

void main() {
  group('resolveModelRuntimeConfig', () {
    test('resolves every pinned catalog key coherently', () {
      for (final entry in modelCatalog) {
        final config = resolveModelRuntimeConfig(entry.key);
        expect(config.catalogKey, entry.key);
        expect(config.engine, brokerEngineFor(entry.engine));
        expect(config.modelPath, primaryModelPathFor(entry.key));
        expect(entry.key, startsWith(config.profile.key));
      }
    });

    test('gemma4-gguf maps to llama.cpp with the single weights file', () {
      final config = resolveModelRuntimeConfig('gemma4-gguf');
      expect(config.engine, BrokerEngine.llamaCpp);
      expect(config.modelPath, startsWith('documents:'));
      expect(config.modelPath, endsWith('.gguf'));
      expect(config.profile.key, 'gemma4');
    });

    test('qwen35-mlx maps to MLX with the install directory', () {
      final config = resolveModelRuntimeConfig('qwen35-mlx');
      expect(config.engine, BrokerEngine.mlx);
      expect(config.modelPath, startsWith('documents:'));
      expect(config.modelPath, isNot(endsWith('.gguf')));
      expect(config.profile.key, 'qwen35');
    });

    test('refuses custom keys with an actionable message', () {
      expect(
        () => resolveModelRuntimeConfig('custom-my-repo-abc12345'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Custom repository models cannot be activated yet'),
          ),
        ),
      );
    });

    test('refuses unknown keys', () {
      expect(
        () => resolveModelRuntimeConfig('gemma4-turbofieldfare'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Unknown catalog key'),
          ),
        ),
      );
    });
  });

  group('brokerEngineFor', () {
    test('maps both catalog engine families', () {
      expect(brokerEngineFor(ModelEngine.gguf), BrokerEngine.llamaCpp);
      expect(brokerEngineFor(ModelEngine.mlx), BrokerEngine.mlx);
    });
  });
}
