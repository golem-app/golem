import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/backend_policy.dart';
import 'package:golem_flutter/broker/configured_inference_repository.dart';
import 'package:golem_flutter/broker/device_capability.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';

const _gib = 1024 * 1024 * 1024;

InferenceBackendConfig _resolve({
  String backend = '',
  String profile = '',
  String artifact = '',
  String modelPath = '',
  AppIdentity identity = AppIdentity.production,
  DeviceTier tier = DeviceTier.preferred,
  HostPlatform platform = HostPlatform.other,
  bool virtualDevice = false,
}) => resolveBackendPolicy(
  backendName: resolveBackendName(
    backendDefine: backend,
    identity: identity,
    virtualDevice: virtualDevice,
    artifactDefine: artifact,
    modelPathDefine: modelPath,
  ),
  profileDefine: profile,
  artifactDefine: artifact,
  modelPathDefine: modelPath,
  tier: tier,
  platform: platform,
);

/// The capability read that produces that tier, with both seams injected so no
/// test touches a platform channel or a native asset.
Future<DeviceCapabilities> _capabilities({
  String backendName = 'auto',
  int memoryOverride = 0,
  bool forceEngineUnsupported = false,
  bool? virtualDevice,
  Future<int?> Function()? probe,
  Future<bool?> Function(String)? engineProbe,
}) => probeDeviceCapabilities(
  backendName: backendName,
  physicalMemoryBytes: probe ?? () async => 8 * _gib,
  memoryOverrideBytes: memoryOverride,
  forceEngineUnsupported: forceEngineUnsupported,
  virtualDevice: virtualDevice,
  engineProbe: engineProbe ?? (name) async => true,
);

void main() {
  test('qa defaults to the fake backend', () async {
    final config = _resolve(identity: AppIdentity.qa);
    expect(config.kind, InferenceBackendKind.fake);
    expect(config.simulatedInference, isTrue);
    expect(config.artifactKey, isNull);
    expect(config.modelPath, isNull);
    expect(config.profileKey, 'gemma4');
  });

  test('production and dev default to automatic platform policy', () async {
    for (final identity in [AppIdentity.production, AppIdentity.dev]) {
      final config = _resolve(identity: identity);
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
  });

  test('automatic policy selects MLX on iOS and GGUF on Android', () {
    final ios = _resolve(platform: HostPlatform.ios);
    expect(ios.kind, InferenceBackendKind.mlx);
    expect(ios.artifactKey, 'gemma4-mlx');
    expect(ios.modelPath, 'documents:models/gemma4-mlx');

    final iosLight = _resolve(
      platform: HostPlatform.ios,
      tier: DeviceTier.light,
    );
    expect(iosLight.artifactKey, 'qwen35-2b-mlx');

    final android = _resolve(platform: HostPlatform.android);
    expect(android.kind, InferenceBackendKind.llama);
    expect(android.artifactKey, 'gemma4-gguf');
    final androidLight = _resolve(
      platform: HostPlatform.android,
      tier: DeviceTier.light,
    );
    expect(androidLight.artifactKey, 'qwen35-2b-gguf');
  });

  test('the light tier selects the lighter Qwen', () async {
    final config = _resolve(tier: DeviceTier.light);
    expect(config.profileKey, 'qwen35');
    expect(config.artifactKey, 'qwen35-2b-gguf');
    expect(
      config.modelPath,
      'documents:models/qwen35-2b-gguf/Qwen3.5-2B-Q4_0.gguf',
    );
  });

  test('an unsupported device still resolves a nameable model', () async {
    // Nothing will load it — the controllers refuse first — but every label
    // and settings section stays addressable rather than blanking out.
    final config = _resolve(tier: DeviceTier.unsupported);
    expect(config.profileKey, 'qwen35');
    expect(config.artifactKey, 'qwen35-2b-gguf');
  });

  test('the capability read produces the tier the policy consumes', () async {
    Future<DeviceTier> tierFor(DeviceCapabilities capabilities) async =>
        classifyDevice(
          capabilities: capabilities,
          memoryFloorBytes: androidMemoryFloorBytes,
        ).tier;

    expect(await tierFor(await _capabilities()), DeviceTier.preferred);
    // Android totalMem reports net of kernel reservations: ~7.5 GB on a
    // nominal 8 GB phone. That must land on the Gemma side.
    expect(
      await tierFor(
        await _capabilities(probe: () async => (7.5 * _gib).round()),
      ),
      DeviceTier.preferred,
    );
    expect(
      await tierFor(await _capabilities(probe: () async => 4 * _gib)),
      DeviceTier.light,
    );
    expect(
      await tierFor(await _capabilities(probe: () async => 2 * _gib)),
      DeviceTier.unsupported,
    );
  });

  test('an unreachable probe reads as unknown, never as a refusal', () async {
    for (final probe in <Future<int?> Function()>[
      () async => null,
      () async => throw StateError('probe failed'),
      // Never completes: exercises the timeout without arming a real
      // delayed timer that would outlive the test.
      () => Completer<int?>().future,
    ]) {
      final capabilities = await _capabilities(probe: probe);
      expect(capabilities.physicalMemoryBytes, isNull, reason: 'probe: $probe');
      expect(
        classifyDevice(
          capabilities: capabilities,
          memoryFloorBytes: androidMemoryFloorBytes,
        ).tier,
        DeviceTier.light,
        reason: 'probe: $probe',
      );
    }
    // The engine half degrades the same way, and an engine nobody could ask
    // about must not be reported as missing.
    final unreachable = await _capabilities(
      engineProbe: (name) async => throw StateError('probe failed'),
    );
    expect(unreachable.engineSupported, isNull);
  });

  test('the simulated backend reads no device at all', () async {
    final capabilities = await _capabilities(
      backendName: 'fake',
      probe: () async => fail('the fake path must never probe memory'),
      engineProbe: (name) async => fail('the fake path has no engine to probe'),
    );
    expect(capabilities.physicalMemoryBytes, isNull);
    expect(capabilities.engineSupported, isNull);
  });

  test('the test-only defines reach both halves of the read', () async {
    final memory = await _capabilities(
      memoryOverride: 4 * _gib,
      probe: () async => fail('the override must bypass the probe'),
    );
    expect(memory.physicalMemoryBytes, 4 * _gib);

    final engine = await _capabilities(
      forceEngineUnsupported: true,
      engineProbe: (name) async => fail('the override must bypass the probe'),
    );
    expect(engine.engineSupported, isFalse);
  });

  test('device override defines are disabled for production identities', () {
    final production = deviceCapabilityOverridesFor(
      identity: AppIdentity.production,
      memoryOverrideBytes: 4 * _gib,
      forceEngineUnsupported: true,
    );
    expect(production.memoryOverrideBytes, 0);
    expect(production.forceEngineUnsupported, isFalse);

    final qa = deviceCapabilityOverridesFor(
      identity: AppIdentity.qa,
      memoryOverrideBytes: 4 * _gib,
      forceEngineUnsupported: true,
    );
    expect(qa.memoryOverrideBytes, 4 * _gib);
    expect(qa.forceEngineUnsupported, isTrue);
  });

  test('explicit defines override the flavor default in any build', () async {
    final fake = _resolve(backend: 'fake');
    expect(fake.kind, InferenceBackendKind.fake);

    // qa + explicit auto exercises the exact production composition — the
    // only real-path route on the physical iPhone.
    final auto = _resolve(backend: 'auto', identity: AppIdentity.qa);
    expect(auto.kind, InferenceBackendKind.llama);
    expect(auto.artifactKey, 'gemma4-gguf');

    // A supplied path is an operator sideload, profile defaulting to gemma4.
    final llama = _resolve(
      backend: 'llama',
      modelPath: 'documents:models/x.gguf',
      identity: AppIdentity.qa,
    );
    expect(llama.kind, InferenceBackendKind.llama);
    expect(llama.profileKey, 'gemma4');
    expect(llama.artifactKey, 'gemma4-gguf');
    expect(llama.modelPath, 'documents:models/x.gguf');
    expect(llama.modelPathFromCatalog, isFalse);

    final mlx = _resolve(
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
    final catalogMlx = _resolve(
      backend: 'mlx',
      profile: 'gemma4',
      identity: AppIdentity.qa,
    );
    expect(catalogMlx.artifactKey, 'gemma4-mlx');
    expect(catalogMlx.modelPath, 'documents:models/gemma4-mlx');
    expect(catalogMlx.modelPathFromCatalog, isTrue);
  });

  test('explicit profile and path override the auto policy choices', () async {
    final config = _resolve(
      profile: 'qwen35',
      modelPath: 'documents:models/sideloaded.gguf',
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
      final config = _resolve(
        backend: 'mlx',
        artifact: 'qwen35-2b-mlx',
        identity: AppIdentity.qa,
        tier: DeviceTier.light,
      );
      expect(config.kind, InferenceBackendKind.mlx);
      expect(config.profileKey, 'qwen35');
      expect(config.artifactKey, 'qwen35-2b-mlx');
      expect(config.modelPath, 'documents:models/qwen35-2b-mlx');
      expect(config.modelPathFromCatalog, isTrue);
    },
  );

  test('an exact auto artifact bypasses the device policy', () async {
    final config = _resolve(
      backend: 'auto',
      artifact: 'qwen35-2b-gguf',
      tier: DeviceTier.preferred,
    );
    expect(config.kind, InferenceBackendKind.llama);
    expect(config.profileKey, 'qwen35');
    expect(config.artifactKey, 'qwen35-2b-gguf');
  });

  test('catalog artifact overrides reject incoherent composition', () async {
    expect(
      () => _resolve(backend: 'mlx', artifact: 'qwen35-2b-gguf'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => _resolve(
        backend: 'mlx',
        profile: 'gemma4',
        artifact: 'qwen35-2b-mlx',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => _resolve(backend: 'mlx', artifact: 'missing'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => _resolve(
        backend: 'mlx',
        artifact: 'qwen35-2b-mlx',
        modelPath: '/tmp/sideload',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => _resolve(backend: 'fake', artifact: 'qwen35-2b-mlx'),
      throwsA(isA<StateError>()),
    );
  });

  test('an unknown backend value fails loudly', () async {
    expect(() => _resolve(backend: 'metal'), throwsA(isA<StateError>()));
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

  // The flag exists so a surface can say the tier picked this model. Either
  // define being present means a human picked it, so "neither was given" is the
  // condition — an "either was given" reading would credit the device policy
  // for a choice made on the command line.
  test('the tier is credited only when nothing else chose', () {
    const android = HostPlatform.android;
    expect(_resolve(platform: android).artifactFromDevicePolicy, isTrue);
    expect(
      _resolve(platform: android, profile: 'qwen35').artifactFromDevicePolicy,
      isFalse,
    );
    expect(
      _resolve(
        platform: android,
        artifact: 'gemma4-gguf',
      ).artifactFromDevicePolicy,
      isFalse,
    );
    expect(
      _resolve(
        platform: android,
        profile: 'gemma4',
        artifact: 'gemma4-gguf',
      ).artifactFromDevicePolicy,
      isFalse,
    );
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

  group('a virtual device (#148)', () {
    test('moves an internal build to the fake, and production not at all', () {
      for (final identity in [AppIdentity.qa, AppIdentity.dev]) {
        expect(
          resolveBackendName(
            backendDefine: '',
            identity: identity,
            virtualDevice: true,
            artifactDefine: '',
            modelPathDefine: '',
          ),
          'fake',
        );
      }
      // Production's composition stays a build-time fact: a detection that
      // ever answered wrong on a phone may refuse a shipping build, but must
      // never turn one into a simulation.
      expect(
        resolveBackendName(
          backendDefine: '',
          identity: AppIdentity.production,
          virtualDevice: true,
          artifactDefine: '',
          modelPathDefine: '',
        ),
        'auto',
      );
    });

    test('an explicit engine still wins, so the refusal stays reachable', () {
      expect(
        resolveBackendName(
          backendDefine: 'mlx',
          identity: AppIdentity.dev,
          virtualDevice: true,
          artifactDefine: '',
          modelPathDefine: '',
        ),
        'mlx',
      );
      expect(
        _resolve(
          backend: 'mlx',
          identity: AppIdentity.dev,
          virtualDevice: true,
        ).simulatedInference,
        isFalse,
      );
    });

    test('a physical device resolves exactly what it resolved before', () {
      expect(
        resolveBackendName(
          backendDefine: '',
          identity: AppIdentity.dev,
          virtualDevice: false,
          artifactDefine: '',
          modelPathDefine: '',
        ),
        'auto',
      );
      expect(
        resolveBackendName(
          backendDefine: '',
          identity: AppIdentity.qa,
          virtualDevice: false,
          artifactDefine: '',
          modelPathDefine: '',
        ),
        'fake',
      );
    });

    test(
      'a real engine there is classified out, not quietly simulated',
      () async {
        // The reading that reaches the classifier, on the path an explicit
        // engine define takes: healthy memory, an available engine, and still
        // refused.
        final capabilities = await _capabilities(
          backendName: 'mlx',
          virtualDevice: true,
        );
        expect(capabilities.virtualDevice, isTrue);
        expect(
          classifyDevice(
            capabilities: capabilities,
            memoryFloorBytes: deviceMemoryFloorBytes(
              reportsInstalledMemory: true,
            ),
          ).refusal,
          DeviceIneligibilityReason.virtualDevice,
        );
      },
    );

    test('the fake path still reads nothing about the device', () async {
      expect(
        (await _capabilities(
          backendName: 'fake',
          virtualDevice: true,
        )).virtualDevice,
        isNull,
      );
    });

    test('a probe that will not answer never refuses', () async {
      expect(
        await probeVirtualDevice(() async => throw StateError('no')),
        isNull,
      );
      expect(await probeVirtualDevice(() async => null), isNull);
    });

    test('an internal build composes the simulation end to end', () async {
      final resolved = await resolveConfiguredBackend(
        identity: AppIdentity.dev,
        isVirtualDevice: () async => true,
      );
      expect(resolved.virtualDevice, isTrue);
      expect(resolved.config.simulatedInference, isTrue);
      // Nothing was classified, so nothing is refused: the surfaces stay
      // usable and label themselves simulated.
      expect(resolved.eligibility.refusal, isNull);
      expect(resolved.eligibility.runsModels, isTrue);
    });

    test('a build that named a model keeps the real path', () {
      // The fake branch throws on an artifact and ignores a path, so swapping
      // under either would turn an operator's define into a terminal
      // misconfiguration pane or a silent simulation.
      expect(
        resolveBackendName(
          backendDefine: '',
          identity: AppIdentity.dev,
          virtualDevice: true,
          artifactDefine: 'qwen35-2b-mlx',
          modelPathDefine: '',
        ),
        'auto',
      );
      expect(
        resolveBackendName(
          backendDefine: '',
          identity: AppIdentity.dev,
          virtualDevice: true,
          artifactDefine: '',
          modelPathDefine: 'documents:my.gguf',
        ),
        'auto',
      );
      // And the artifact still resolves rather than throwing.
      expect(
        _resolve(
          identity: AppIdentity.dev,
          virtualDevice: true,
          artifact: 'qwen35-2b-mlx',
          platform: HostPlatform.ios,
        ).artifactKey,
        'qwen35-2b-mlx',
      );
    });

    test('model management follows inference, never leads it', () {
      // The precondition is simulated inference in every arm: a real engine
      // fed by a simulated install would "install" files that do not exist.
      expect(
        useFakeModelManagement(
          identity: AppIdentity.dev,
          simulatedInference: false,
          virtualDevice: true,
        ),
        isFalse,
      );
      expect(
        useFakeModelManagement(
          identity: AppIdentity.dev,
          simulatedInference: true,
          virtualDevice: true,
        ),
        isTrue,
      );
      // Unchanged on hardware: dev keeps the real downloader even when an
      // operator pins fake inference, and qa keeps the simulation.
      expect(
        useFakeModelManagement(
          identity: AppIdentity.dev,
          simulatedInference: true,
          virtualDevice: false,
        ),
        isFalse,
      );
      expect(
        useFakeModelManagement(
          identity: AppIdentity.qa,
          simulatedInference: true,
          virtualDevice: false,
        ),
        isTrue,
      );
      // Production's model management is a build-time fact too: the device
      // may not swap it, under the same gate resolveBackendName applies.
      expect(
        useFakeModelManagement(
          identity: AppIdentity.production,
          simulatedInference: true,
          virtualDevice: true,
        ),
        isFalse,
      );
    });
  });
}
