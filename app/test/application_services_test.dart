import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/application/storage_breakdown_service.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/repository_resolution.dart';
import 'package:golem_flutter/core/domain/resolved_repository.dart';
import 'package:golem_flutter/core/domain/model_profile_spec.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_repository_resolver.dart';
import 'package:golem_flutter/core/services/cache_probe.dart';
import 'package:golem_flutter/core/services/device_storage.dart';
import 'package:golem_flutter/features/models/application/custom_repository_controller.dart';
import 'package:golem_flutter/features/models/application/custom_repository_workflow.dart';
import 'package:golem_flutter/features/preferences/application/preferences_providers.dart';

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

  group('CustomRepositoryController', () {
    ProviderContainer containerWith(CustomRepositoryResolver resolver) {
      final container = buildContainer(
        model: const ModelState(simulated: true),
        resolver: resolver,
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a resolution survives the card being rebuilt from scratch', () async {
      // The reason this is a controller and not screen state: the Models list
      // disposes off-screen children, so a resolution used to depend on the
      // card staying on screen (#129).
      final container = containerWith(
        _ScriptedResolver([
          RepositoryResolved(
            resolved: _resolved,
            profile: null,
            templateFingerprint: null,
          ),
        ]),
      );
      final controller = container.read(
        customRepositoryControllerProvider.notifier,
      );
      controller.edit(repository: 'org/tiny-GGUF');
      await controller.resolve();
      expect(
        container.read(customRepositoryControllerProvider).outcome,
        isA<AddResolved>(),
      );
      expect(
        container.read(customRepositoryControllerProvider).repository,
        'org/tiny-GGUF',
        reason: 'the typed text travels with the resolution',
      );
    });

    test('editing or switching engine drops a stale resolution', () async {
      final container = containerWith(
        _ScriptedResolver([
          RepositoryResolved(
            resolved: _resolved,
            profile: null,
            templateFingerprint: null,
          ),
        ]),
      );
      final controller = container.read(
        customRepositoryControllerProvider.notifier,
      );
      controller.edit(repository: 'org/tiny-GGUF');
      await controller.resolve();
      controller.edit(repository: 'org/tiny-GGU');
      expect(
        container.read(customRepositoryControllerProvider).outcome,
        isA<AddIdle>(),
      );
      await controller.resolve();
      controller.selectEngine(ModelEngine.gguf);
      expect(
        container.read(customRepositoryControllerProvider).outcome,
        isA<AddIdle>(),
      );
    });

    test('an answer for a repository the user retyped is dropped', () async {
      // Resolving takes seconds of network. The edit already published
      // AddIdle, and this answer describes something no longer on screen.
      final resolver = _GatedResolver();
      final container = containerWith(resolver);
      final controller = container.read(
        customRepositoryControllerProvider.notifier,
      );
      controller.edit(repository: 'org/slow');
      final pending = controller.resolve();
      controller.edit(repository: 'org/other');
      resolver.complete(
        RepositoryResolved(
          resolved: _resolved,
          profile: null,
          templateFingerprint: null,
        ),
      );
      await pending;
      expect(
        container.read(customRepositoryControllerProvider).outcome,
        isA<AddIdle>(),
      );
    });

    test(
      'a weight choice resolves again with the file the user picked',
      () async {
        final resolver = _RecordingResolver();
        final container = containerWith(resolver);
        final controller = container.read(
          customRepositoryControllerProvider.notifier,
        );
        controller.edit(repository: 'org/tiny-GGUF');
        await controller.resolve(weightsFile: 'tiny-Q4_0.gguf');
        expect(resolver.weightsFiles, ['tiny-Q4_0.gguf']);
      },
    );

    test('a committed add persists the spec and clears the draft', () async {
      final container = containerWith(
        _ScriptedResolver([
          RepositoryResolved(
            resolved: _resolved,
            profile: null,
            templateFingerprint: null,
          ),
        ]),
      );
      final controller = container.read(
        customRepositoryControllerProvider.notifier,
      );
      controller.edit(repository: 'org/tiny-GGUF', revision: 'abc123');
      await controller.resolve();
      expect(await controller.add(), isTrue);
      final draft = container.read(customRepositoryControllerProvider);
      expect(draft.repository, isEmpty);
      expect(draft.outcome, isA<AddIdle>());
      final stored = (await container.read(
        preferencesControllerProvider.future,
      )).customModels;
      expect(stored.single.repository, 'org/tiny-GGUF');
      expect(stored.single.revision, 'abc123');
    });

    test('add refuses without a resolution on screen', () async {
      final container = containerWith(const DeterministicRepositoryResolver());
      final controller = container.read(
        customRepositoryControllerProvider.notifier,
      );
      controller.edit(repository: 'org/tiny-GGUF');
      expect(await controller.add(), isFalse);
    });
  });
}

final _resolved = ResolvedRepository(
  commitSha: 'a' * 40,
  quantization: 'Q4_0',
  displayName: 'Tiny',
  files: const [
    ModelArtifactFile(
      path: 'tiny.gguf',
      bytes: 1000,
      role: ModelFileRole.weights,
    ),
  ],
);

/// Replays scripted resolutions, and records the weights file each pass asked
/// for so the two-step choice can be asserted.
final class _ScriptedResolver implements CustomRepositoryResolver {
  _ScriptedResolver(this.outcomes);

  final List<RepositoryResolution> outcomes;
  int _calls = 0;

  @override
  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    String ref = 'main',
    String? weightsFile,
    Set<String> existingKeys = const {},
  }) async {
    final index = _calls < outcomes.length ? _calls : outcomes.length - 1;
    _calls++;
    return outcomes[index];
  }
}

/// Answers only when the test says so, which is how a slow Hub read is staged
/// against an edit that lands while it is in flight.
final class _GatedResolver implements CustomRepositoryResolver {
  final _gate = Completer<RepositoryResolution>();

  void complete(RepositoryResolution outcome) => _gate.complete(outcome);

  @override
  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    String ref = 'main',
    String? weightsFile,
    Set<String> existingKeys = const {},
  }) => _gate.future;
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
  final List<String?> weightsFiles = [];

  @override
  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    String ref = 'main',
    String? weightsFile,
    Set<String> existingKeys = const {},
  }) async {
    this.existingKeys = existingKeys;
    weightsFiles.add(weightsFile);
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
