import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/backend_policy.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';

const _gib = 1024 * 1024 * 1024;

Future<InferenceBackendConfig> _resolve({
  String backend = '',
  String profile = '',
  String artifact = '',
  String modelPath = '',
  AppIdentity identity = AppIdentity.production,
  int memoryOverride = 0,
  Future<int?> Function()? probe,
}) => resolveBackendPolicy(
  backendDefine: backend,
  profileDefine: profile,
  artifactDefine: artifact,
  modelPathDefine: modelPath,
  identity: identity,
  memoryOverrideBytes: memoryOverride,
  physicalMemoryBytes: probe ?? () async => 8 * _gib,
);

void main() {
  test('qa and the flavorless identity default to the fake backend', () async {
    for (final identity in [AppIdentity.qa, AppIdentity.flutter]) {
      final config = await _resolve(
        identity: identity,
        probe: () async => fail('the fake path must never probe memory'),
      );
      expect(config.kind, InferenceBackendKind.fake);
      expect(config.simulatedInference, isTrue);
      expect(config.artifactKey, isNull);
      expect(config.modelPath, isNull);
      expect(config.profileKey, 'gemma4');
    }
  });

  test(
    'production and dev default to auto: llama plus device policy',
    () async {
      for (final identity in [AppIdentity.production, AppIdentity.dev]) {
        final config = await _resolve(identity: identity);
        expect(config.kind, InferenceBackendKind.llama);
        expect(config.simulatedInference, isFalse);
        expect(config.profileKey, 'gemma4');
        expect(config.artifactKey, 'gemma4-gguf');
        expect(
          config.modelPath,
          'documents:models/gemma4-gguf/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
        );
        expect(config.modelPathFromCatalog, isTrue);
      }
    },
  );

  test('below the memory threshold the lighter Qwen is the default', () async {
    final config = await _resolve(probe: () async => 4 * _gib);
    expect(config.profileKey, 'qwen35');
    expect(config.artifactKey, 'qwen35-2b-gguf');
    expect(
      config.modelPath,
      'documents:models/qwen35-2b-gguf/Qwen3.5-2B-Q4_0.gguf',
    );
  });

  test('a nominal 8 GB Android that under-reports still gets Gemma', () async {
    // Android totalMem reports net of kernel reservations: ~7.5 GB on a
    // nominal 8 GB phone. That must land on the Gemma side.
    final config = await _resolve(probe: () async => (7.5 * _gib).round());
    expect(config.profileKey, 'gemma4');
  });

  test('unknown memory selects the protective default', () async {
    for (final probe in <Future<int?> Function()>[
      () async => null,
      () async => throw StateError('probe failed'),
      // Never completes: exercises the timeout without arming a real
      // delayed timer that would outlive the test.
      () => Completer<int?>().future,
    ]) {
      final config = await _resolve(probe: probe);
      expect(config.profileKey, 'qwen35', reason: 'probe: $probe');
      expect(config.artifactKey, 'qwen35-2b-gguf', reason: 'probe: $probe');
    }
  });

  test('the memory override define bypasses the probe entirely', () async {
    final config = await _resolve(
      memoryOverride: 4 * _gib,
      probe: () async => fail('the override must bypass the probe'),
    );
    expect(config.profileKey, 'qwen35');
    expect(config.artifactKey, 'qwen35-2b-gguf');
  });

  test('explicit defines override the flavor default in any build', () async {
    // production + explicit fake stays fake.
    final fake = await _resolve(backend: 'fake');
    expect(fake.kind, InferenceBackendKind.fake);

    // qa + explicit auto exercises the exact production composition — the
    // only real-path route on the physical iPhone.
    final auto = await _resolve(backend: 'auto', identity: AppIdentity.qa);
    expect(auto.kind, InferenceBackendKind.llama);
    expect(auto.artifactKey, 'gemma4-gguf');

    // A supplied path is an operator sideload, profile defaulting to gemma4.
    final llama = await _resolve(
      backend: 'llama',
      modelPath: 'documents:models/x.gguf',
      identity: AppIdentity.qa,
    );
    expect(llama.kind, InferenceBackendKind.llama);
    expect(llama.profileKey, 'gemma4');
    expect(llama.artifactKey, 'gemma4-gguf');
    expect(llama.modelPath, 'documents:models/x.gguf');
    expect(llama.modelPathFromCatalog, isFalse);

    final mlx = await _resolve(
      backend: 'mlx',
      profile: 'qwen35',
      modelPath: '/abs/mlx-dir',
    );
    expect(mlx.kind, InferenceBackendKind.mlx);
    expect(mlx.artifactKey, 'qwen35-mlx');
    expect(mlx.modelPath, '/abs/mlx-dir');
    expect(mlx.modelPathFromCatalog, isFalse);

    // Without an operator path, an explicit engine resolves the exact pinned
    // catalog artifact and retains its capability proof.
    final catalogMlx = await _resolve(
      backend: 'mlx',
      profile: 'gemma4',
      identity: AppIdentity.qa,
    );
    expect(catalogMlx.artifactKey, 'gemma4-mlx');
    expect(catalogMlx.modelPath, 'documents:models/gemma4-mlx');
    expect(catalogMlx.modelPathFromCatalog, isTrue);
  });

  test('explicit profile and path override the auto policy choices', () async {
    final config = await _resolve(
      profile: 'qwen35',
      modelPath: 'documents:models/sideloaded.gguf',
      memoryOverride: 16 * _gib,
    );
    expect(config.kind, InferenceBackendKind.llama);
    expect(config.profileKey, 'qwen35');
    expect(config.artifactKey, 'qwen35-gguf');
    expect(config.modelPath, 'documents:models/sideloaded.gguf');
    // Operator-supplied paths are never install-gated.
    expect(config.modelPathFromCatalog, isFalse);
  });

  test(
    'an exact catalog artifact selects size separately from profile',
    () async {
      final config = await _resolve(
        backend: 'mlx',
        artifact: 'qwen35-2b-mlx',
        identity: AppIdentity.qa,
        probe: () async => fail('an exact artifact must not probe memory'),
      );
      expect(config.kind, InferenceBackendKind.mlx);
      expect(config.profileKey, 'qwen35');
      expect(config.artifactKey, 'qwen35-2b-mlx');
      expect(config.modelPath, 'documents:models/qwen35-2b-mlx');
      expect(config.modelPathFromCatalog, isTrue);
    },
  );

  test('an exact auto artifact bypasses the device policy', () async {
    final config = await _resolve(
      backend: 'auto',
      artifact: 'qwen35-2b-gguf',
      probe: () async => fail('an exact artifact must not probe memory'),
    );
    expect(config.kind, InferenceBackendKind.llama);
    expect(config.profileKey, 'qwen35');
    expect(config.artifactKey, 'qwen35-2b-gguf');
  });

  test('catalog artifact overrides reject incoherent composition', () async {
    await expectLater(
      _resolve(backend: 'mlx', artifact: 'qwen35-2b-gguf'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      _resolve(backend: 'mlx', profile: 'gemma4', artifact: 'qwen35-2b-mlx'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      _resolve(backend: 'mlx', artifact: 'missing'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      _resolve(
        backend: 'mlx',
        artifact: 'qwen35-2b-mlx',
        modelPath: '/tmp/sideload',
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      _resolve(backend: 'fake', artifact: 'qwen35-2b-mlx'),
      throwsA(isA<StateError>()),
    );
  });

  test('an unknown backend value fails loudly', () async {
    await expectLater(_resolve(backend: 'metal'), throwsA(isA<StateError>()));
  });

  test('primaryModelPathFor derives paths from the pinned catalog', () {
    expect(
      primaryModelPathFor('qwen35-2b-gguf'),
      'documents:models/qwen35-2b-gguf/Qwen3.5-2B-Q4_0.gguf',
    );
    expect(
      primaryModelPathFor('qwen35-2b-mlx'),
      'documents:models/qwen35-2b-mlx',
    );
    expect(primaryModelPathFor('qwen35-mlx'), 'documents:models/qwen35-mlx');
    expect(
      primaryModelPathFor('gemma4-gguf'),
      'documents:models/gemma4-gguf/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
    );
    expect(() => primaryModelPathFor('nope'), throwsArgumentError);
  });

  test('the backend signal provider defaults to fake under test', () {
    // Host `flutter test` runs as the dev flavor, whose *composition*
    // default is auto/real — but that resolution happens only in main().
    // Any widget-visible read of the signal without an override must see
    // the fake, or every existing widget test and golden would silently
    // change meaning.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(inferenceBackendProvider).simulatedInference, isTrue);
    expect(AppIdentity.current, AppIdentity.dev);
  });
}
