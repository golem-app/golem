import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/features/chat/application/generation_target.dart';

/// The pre-flight decision a send makes before touching the engine, extracted
/// from ChatController (#127). It used to be reachable only by driving a real
/// send through a container, which is also why the "no loadable set" arm went
/// unnoticed for so long.

ModelCatalogEntry _entry(String key, ModelEngine engine) => ModelCatalogEntry(
  key: key,
  displayName: key,
  engine: engine,
  quantization: '4-bit',
  repository: 'example/$key',
  revision: '0123456789abcdef',
  files: const [ModelArtifactFile(path: 'weights.bin', bytes: 4)],
  profileKey: 'gemma4',
);

final _catalog = [
  _entry('gemma4-mlx', ModelEngine.mlx),
  _entry('qwen35-mlx', ModelEngine.mlx),
];

const _fake = InferenceBackendConfig.fake();
const _mlx = InferenceBackendConfig(
  kind: InferenceBackendKind.mlx,
  profileKey: 'gemma4',
  artifactKey: 'gemma4-mlx',
  modelPath: 'documents:models/gemma4-mlx/weights.bin',
  // Without this the config reads as a sideload, which takes a different arm.
  modelPathFromCatalog: true,
);
const _sideloaded = InferenceBackendConfig(
  kind: InferenceBackendKind.mlx,
  profileKey: 'gemma4',
  modelPath: '/tmp/operators-own.bin',
);

GenerationTarget _resolve({
  InferenceBackendConfig backend = _fake,
  DeviceIneligibilityReason? deviceRefusal,
  String? conversationModelKey,
  String? residentModelKey,
  Set<String> loadableKeys = const {},
}) => resolveGenerationTarget(
  backend: backend,
  deviceRefusal: deviceRefusal,
  catalog: _catalog,
  conversationModelKey: conversationModelKey,
  residentModelKey: residentModelKey,
  loadableKeys: loadableKeys,
);

void main() {
  group('the device floor', () {
    test('an unsupported device stops before anything else is considered', () {
      // Ahead of the missing-model arm on purpose (#27): otherwise the banner
      // offers a multi-gigabyte download whose weights this device can never
      // load. Everything here would otherwise have resolved happily.
      final target = _resolve(
        backend: _mlx,
        deviceRefusal: DeviceIneligibilityReason.belowMemoryFloor,
        conversationModelKey: 'gemma4-mlx',
        loadableKeys: const {'gemma4-mlx'},
      );

      expect(
        target,
        isA<GenerationRefused>().having(
          (value) => value.failure.kind,
          'kind',
          ChatFailureKind.unsupportedDevice,
        ),
      );
    });

    test('the sideload exemption does not extend to the device floor', () {
      // An operator's own file needs the same memory and instruction set.
      expect(
        _resolve(
          backend: _sideloaded,
          deviceRefusal: DeviceIneligibilityReason.missingInstructionSet,
        ),
        isA<GenerationRefused>(),
      );
    });
  });

  group('a real engine', () {
    test("honours the chat's own choice when it is loadable", () {
      final target = _resolve(
        backend: _mlx,
        conversationModelKey: 'qwen35-mlx',
        loadableKeys: const {'gemma4-mlx', 'qwen35-mlx'},
      );

      expect(target, isA<GenerationReady>());
      expect((target as GenerationReady).key, 'qwen35-mlx');
      expect(target.entry?.key, 'qwen35-mlx');
    });

    test('refuses a stored choice whose weights are not loadable', () {
      // The whole point of #20: a label may name a model before it installs,
      // but the send that follows must not pretend it can run it. Falls back
      // to the boot artifact, which here is loadable.
      final target = _resolve(
        backend: _mlx,
        conversationModelKey: 'qwen35-mlx',
        loadableKeys: const {'gemma4-mlx'},
      );

      expect((target as GenerationReady).key, 'gemma4-mlx');
    });

    test('an empty loadable set fails fast into the download CTA', () {
      // Authoritative, not "unknown": nothing is installed, so prepare() could
      // only produce a cryptic missing-file error after a hang-like pause.
      final target = _resolve(
        backend: _mlx,
        conversationModelKey: 'gemma4-mlx',
      );

      expect(
        target,
        isA<GenerationRefused>()
            .having(
              (value) => value.failure.kind,
              'kind',
              ChatFailureKind.missingModel,
            )
            .having(
              (value) => value.failure.artifactKey,
              'artifactKey',
              'gemma4-mlx',
            ),
      );
    });

    test('a sideload proceeds with no key at all', () {
      // The operator's file is the model; no catalog entry describes it, so
      // there is nothing to name and nothing to refuse.
      final target = _resolve(backend: _sideloaded);

      expect(target, isA<GenerationReady>());
      expect((target as GenerationReady).key, isNull);
      expect(target.entry, isNull);
    });
  });

  group('the simulation', () {
    test('honours any choice, installed or not', () {
      final target = _resolve(conversationModelKey: 'qwen35-mlx');

      expect((target as GenerationReady).key, 'qwen35-mlx');
    });

    test('never refuses for a missing model', () {
      // It loads no weights, so gating it would only make QA depend on
      // hardware. Resident key fills in when the chat named nothing.
      final target = _resolve(residentModelKey: 'gemma4-mlx');

      expect(target, isA<GenerationReady>());
    });
  });

  test('a key that is not in the catalog resolves without an entry', () {
    // A custom repository the catalog no longer carries: the key still travels
    // to prepare(), which is the loud failure path, but there is no entry for
    // the installed check to consult.
    final target = _resolve(
      backend: _mlx,
      conversationModelKey: 'gone-mlx',
      loadableKeys: const {'gone-mlx'},
    );

    expect((target as GenerationReady).key, 'gone-mlx');
    expect(target.entry, isNull);
  });

  test('the not-installed refusal names the artifact it wants', () {
    expect(
      notInstalledFailure('gemma4-mlx').kind,
      ChatFailureKind.missingModel,
    );
    expect(notInstalledFailure('gemma4-mlx').artifactKey, 'gemma4-mlx');
  });
}
