import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';

void main() {
  test('model state v2 round-trips artifacts and drops wiring stamps', () {
    const state = ModelState(
      artifacts: {
        'gemma4-mlx': ArtifactStatus(
          phase: ArtifactPhase.paused,
          downloadedBytes: 123456789,
        ),
        'qwen35-gguf': ArtifactStatus(
          phase: ArtifactPhase.failed,
          downloadedBytes: 42,
          failure: 'Needs 3.4 GB free; 1.1 GB available.',
        ),
      },
      runtime: RuntimePhase.loaded,
      failure: 'runtime message',
      activeArtifactKey: 'gemma4-mlx',
      simulated: true,
    );
    final json = state.toJson();
    expect(json['schemaVersion'], 2);
    // Wiring stamps come from the repository configuration on every load;
    // persisting them would let stale configuration lie after a rebuild.
    expect(json.containsKey('activeArtifactKey'), isFalse);
    expect(json.containsKey('simulated'), isFalse);

    final decoded = ModelState.fromJson(json);
    expect(decoded.statusOf('gemma4-mlx').phase, ArtifactPhase.paused);
    expect(decoded.statusOf('gemma4-mlx').downloadedBytes, 123456789);
    expect(decoded.statusOf('qwen35-gguf').phase, ArtifactPhase.failed);
    expect(decoded.statusOf('qwen35-gguf').failure, contains('3.4 GB'));
    expect(decoded.runtime, RuntimePhase.loaded);
    expect(decoded.failure, 'runtime message');
    expect(decoded.activeArtifactKey, isNull);
    expect(decoded.simulated, isFalse);

    final stamped = decoded.stamp(
      activeArtifactKey: 'gemma4-mlx',
      simulated: true,
    );
    expect(stamped.activeModelInstalled, isFalse);
    final installed = stamped.withArtifact(
      'gemma4-mlx',
      const ArtifactStatus(phase: ArtifactPhase.installed),
    );
    // copyWith and withArtifact carry the stamps through transitions.
    expect(installed.simulated, isTrue);
    expect(installed.activeModelInstalled, isTrue);
  });

  test('v1 model state files are rejected as an unknown schema', () {
    expect(
      () => ModelState.fromJson({'schemaVersion': 1, 'backend': 'mlx'}),
      throwsFormatException,
    );
  });

  test('the broker catalog mirrors the pinned Inferno manifest', () {
    final byKey = {for (final entry in modelCatalog) entry.key: entry};
    expect(byKey.keys, [
      'gemma4-mlx',
      'gemma4-gguf',
      'qwen35-2b-mlx',
      'qwen35-2b-gguf',
      'qwen35-mlx',
      'qwen35-gguf',
    ]);
    const artifacts = {
      'gemma4-mlx': gemma4E2BMlx4Bit,
      'gemma4-gguf': gemma4E2BGgufQ4,
      'qwen35-2b-mlx': qwen35TwoBMlx4Bit,
      'qwen35-2b-gguf': qwen35TwoBGgufQ4,
      'qwen35-mlx': qwen35Mlx4Bit,
      'qwen35-gguf': qwen35GgufQ4,
    };
    for (final MapEntry(:key, value: artifact) in artifacts.entries) {
      final entry = byKey[key]!;
      expect(entry.repository, artifact.repository, reason: key);
      expect(entry.revision, artifact.revision, reason: key);
      expect(entry.files.length, artifact.files.length, reason: key);
      for (var i = 0; i < entry.files.length; i++) {
        expect(entry.files[i].path, artifact.files[i].path, reason: key);
        expect(entry.files[i].bytes, artifact.files[i].bytes, reason: key);
        expect(entry.files[i].sha256, artifact.files[i].sha256, reason: key);
        expect(
          entry.files[i].repository,
          artifact.files[i].repository,
          reason: key,
        );
        expect(
          entry.files[i].revision,
          artifact.files[i].revision,
          reason: key,
        );
      }
      expect(
        entry.totalBytes,
        artifact.files.fold<int>(0, (sum, file) => sum + file.bytes),
        reason: key,
      );
      expect(entry.installDirectory, 'models/$key', reason: key);
      expect(
        entry.repositoryUrl.toString(),
        'https://huggingface.co/${artifact.repository}/tree/${artifact.revision}',
        reason: key,
      );
    }
  });

  test('a per-file source overrides the artifact download location', () {
    final entry = modelCatalog.singleWhere((item) => item.key == 'gemma4-gguf');
    final projector = entry.files.singleWhere(
      (file) => file.role == ModelFileRole.projector,
    );
    expect(
      entry.resolveUrlFor(projector).toString(),
      'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/'
      'resolve/64ef033dc9f85a88f88e70cceb0a7457366bea64/'
      'mmproj-gemma-4-E2B-it-Q8_0.gguf',
    );
  });

  test('the active artifact derives from the inference dart-defines', () {
    expect(
      activeArtifactKeyFor(backend: 'mlx', modelProfile: 'gemma4'),
      'gemma4-mlx',
    );
    expect(
      activeArtifactKeyFor(backend: 'llama', modelProfile: 'qwen35'),
      'qwen35-gguf',
    );
    expect(
      activeArtifactKeyFor(backend: 'fake', modelProfile: 'gemma4'),
      isNull,
    );
    // Every derivable key names a real catalog entry.
    final keys = {for (final entry in modelCatalog) entry.key};
    for (final profile in ['gemma4', 'qwen35']) {
      for (final backend in ['mlx', 'llama']) {
        expect(
          keys,
          contains(
            activeArtifactKeyFor(backend: backend, modelProfile: profile),
          ),
        );
      }
    }
  });
}
