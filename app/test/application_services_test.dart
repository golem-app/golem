import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/application/storage_breakdown_service.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/repository_resolution.dart';
import 'package:golem_flutter/core/domain/model_profile_spec.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/services/cache_probe.dart';
import 'package:golem_flutter/core/services/device_storage.dart';
import 'package:golem_flutter/features/settings/application/custom_repository_workflow.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';

void main() {
  group('DirectoryCacheProbe', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('golem-cache-probe-');
      addTearDown(() => temp.deleteSync(recursive: true));
    });

    test('sums and clears ordinary scratch', () async {
      File('${temp.path}/spill.bin').writeAsStringSync('0123456789');
      final probe = DirectoryCacheProbe(temp.path);
      expect(await probe.sizeBytes(), 10);
      await probe.clear();
      expect(await probe.sizeBytes(), 0);
      expect(temp.existsSync(), isTrue);
    });

    // Android stages a small file's partial transfer in the cache directory,
    // so an unguarded clear silently discards a paused download's progress.
    test('a partial transfer survives Clear cache', () async {
      final partial = File(
        '${temp.path}/com.bbflight.background_downloader1234',
      )..writeAsStringSync('half a model');
      File('${temp.path}/spill.bin').writeAsStringSync('junk');
      await DirectoryCacheProbe(temp.path).clear();
      expect(partial.existsSync(), isTrue);
      expect(File('${temp.path}/spill.bin').existsSync(), isFalse);
    });

    // Counting bytes that Clear cannot free would promise space the button
    // does not deliver.
    test('a partial transfer is not counted as reclaimable', () async {
      File(
        '${temp.path}/com.bbflight.background_downloader1234',
      ).writeAsStringSync('half a model');
      expect(await DirectoryCacheProbe(temp.path).sizeBytes(), 0);
    });
  });

  group('StorageBreakdownService', () {
    test('sums required inputs and reads the probes', () async {
      final history = InMemoryChatHistoryRepository(seedHistory());
      final service = StorageBreakdownService(
        history: history,
        cache: FakeCacheProbe(),
        free: const FakeDiskSpace(1000),
        capacity: const FakeDiskCapacity(2000),
        documentsPath: '/tmp/docs',
      );
      final models = const ModelState().withArtifact(
        'gemma4-gguf',
        const ArtifactStatus(
          phase: ArtifactPhase.installed,
          downloadedBytes: 42,
        ),
      );
      final breakdown = await service.compute(models: models);
      expect(breakdown.modelsBytes, 42);
      expect(breakdown.chatsBytes, greaterThan(0));
      expect(breakdown.freeBytes, 1000);
      expect(breakdown.totalBytes, 2000);
      expect(breakdown.usedBytes, greaterThanOrEqualTo(42));
    });

    test('a failed required input propagates', () async {
      final history = InMemoryChatHistoryRepository()..failingStoredBytes = 1;
      final service = StorageBreakdownService(history: history);
      await expectLater(
        service.compute(models: const ModelState()),
        throwsA(isA<PersistenceException>()),
      );
    });

    test('a failed optional probe degrades to unknown, not zero', () async {
      final service = StorageBreakdownService(
        history: InMemoryChatHistoryRepository(),
        cache: _ThrowingCacheProbe(),
        free: _ThrowingDiskSpace(),
        capacity: _ThrowingDiskCapacity(),
        documentsPath: '/tmp/docs',
      );
      final breakdown = await service.compute(models: const ModelState());
      expect(breakdown.cacheBytes, 0);
      expect(breakdown.freeBytes, isNull);
      expect(breakdown.totalBytes, isNull);
    });
  });

  group('CustomRepositoryWorkflow', () {
    const spec = ModelProfileSpec(
      key: 'gemma4',
      template: ChatTemplateSpec(
        strategy: ChatTemplateStrategy.gemmaTurns,
        turnOpen: '<|turn>',
        turnClose: '<turn|>',
        systemRole: 'system',
        userRole: 'user',
        assistantRole: 'model',
        historyStrip: HistoryStripMode.none,
        thoughtControl: '<ctrl>',
      ),
      parser: ReasoningParserMode.none,
      stopSequences: ['<turn|>'],
      stopTokenIds: [1],
      reasoningSampling: ProfileSampling(
        maxTokens: 100,
        temperature: 1,
        topP: 0.9,
      ),
      directSampling: ProfileSampling(
        maxTokens: 100,
        temperature: 1,
        topP: 0.9,
      ),
    );

    test('collides only pinned keys and profiled custom entries', () async {
      final recorder = _RecordingResolver();
      final workflow = CustomRepositoryWorkflow(resolver: recorder);
      await workflow.resolve(
        repository: 'org/new',
        engine: ModelEngine.gguf,
        ref: 'main',
        pinned: modelCatalog,
        custom: const [
          // Profiled: collides.
          CustomModelSpec(
            repository: 'org/proven',
            engine: ModelEngine.gguf,
            profile: spec,
          ),
          // Unprofiled: re-adding is the card's own repair path.
          CustomModelSpec(repository: 'org/unproven', engine: ModelEngine.gguf),
        ],
      );
      expect(
        recorder.existingKeys,
        containsAll({
          for (final entry in modelCatalog) entry.key,
          customCatalogKeyFor('org/proven'),
        }),
      );
      expect(
        recorder.existingKeys,
        isNot(contains(customCatalogKeyFor('org/unproven'))),
      );
    });

    test(
      'an escaped resolver error becomes a rejection, not a strand',
      () async {
        final workflow = CustomRepositoryWorkflow(
          resolver: _ThrowingResolver(),
        );
        final outcome = await workflow.resolve(
          repository: 'org/broken',
          engine: ModelEngine.gguf,
          ref: 'main',
          pinned: const [],
          custom: const [],
        );
        expect(outcome, isA<RepositoryRejected>());
        final rejected = outcome as RepositoryRejected;
        expect(rejected.reason, RepositoryRejection.malformedMetadata);
        expect(rejected.cause, isA<StateError>());
      },
    );
  });
}

final class _ThrowingCacheProbe implements CacheProbe {
  @override
  Future<int> sizeBytes() async => throw StateError('probe down');
  @override
  Future<void> clear() async {}
}

final class _ThrowingDiskSpace implements DiskSpaceProbe {
  @override
  Future<int?> freeBytes(String path) async => throw StateError('probe down');
}

final class _ThrowingDiskCapacity implements DiskCapacityProbe {
  @override
  Future<int?> totalBytes(String path) async => throw StateError('probe down');
}

final class _RecordingResolver implements CustomRepositoryResolver {
  Set<String> existingKeys = const {};

  @override
  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    String ref = 'main',
    String? weightsFile,
    Set<String> existingKeys = const {},
  }) async {
    this.existingKeys = existingKeys;
    return const RepositoryRejected(RepositoryRejection.duplicateEntry);
  }
}

final class _ThrowingResolver implements CustomRepositoryResolver {
  @override
  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    String ref = 'main',
    String? weightsFile,
    Set<String> existingKeys = const {},
  }) async => throw StateError('escaped the contract');
}
