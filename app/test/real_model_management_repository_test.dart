import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/real_model_management_repository.dart';
import 'package:golem_flutter/core/services/artifact_downloader.dart';
import 'package:golem_flutter/core/services/device_storage.dart';

const _fileOne = 'config.json';
const _fileTwo = 'weights/model.bin';
const _contentOne = 'artifact configuration';
const _contentTwo = 'binary weight payload!';

ModelCatalogEntry _entry() => ModelCatalogEntry(
  key: 'test-mlx',
  displayName: 'Test MLX',
  engine: ModelEngine.mlx,
  quantization: '4-bit',
  repository: 'example/test-mlx',
  revision: '0123456789abcdef',
  profileKey: 'gemma4',
  files: [
    ModelArtifactFile(
      path: _fileOne,
      bytes: _contentOne.length,
      sha256: sha256.convert(utf8.encode(_contentOne)).toString(),
    ),
    ModelArtifactFile(
      path: _fileTwo,
      bytes: _contentTwo.length,
      sha256: sha256.convert(utf8.encode(_contentTwo)).toString(),
      repository: 'projectors/test-weights',
      revision: 'fedcba9876543210',
    ),
  ],
);

/// Stands in for the OS and the plugin's stores, and deliberately **outlives**
/// any one repository: constructing a second [RealModelManagementRepository]
/// over the same platform is how a process recreation is expressed, which is
/// the only way the reconciliation this file pins can be tested at all.
final class _FakePlatform {
  _FakePlatform(this.documentsDirectory);

  final String documentsDirectory;

  final List<String> requestedUrls = [];

  /// Every destination a transfer was started for. A second entry for one
  /// destination is a second writer.
  final List<String> enqueued = [];
  final List<String> pausedRefs = [];
  final List<String> canceledRefs = [];

  /// Keyed by filename (the fixture's basenames are unique).
  final Map<String, ArtifactFileEvent> terminalEvents = {};
  final Map<String, String> contents = {
    'config.json': _contentOne,
    'model.bin': _contentTwo,
  };

  /// Destinations a download() is currently streaming.
  final Set<String> inFlight = {};

  /// Transfers the platform still holds although no download() is streaming
  /// them — what survives a process death. Value is the bytes already moved.
  final Map<String, int> surviving = {};

  /// Destinations whose surviving transfer has resume data.
  final Set<String> resumable = {};

  int initializeCalls = 0;
  int pauseCalls = 0;
  int cancelCalls = 0;
}

/// Scripted downloader: writes configured content (or garbage) into the
/// destination and replays a configured terminal event.
final class _ScriptedDownloader implements ArtifactFileDownloader {
  _ScriptedDownloader(this.platform);

  final _FakePlatform platform;

  List<String> get requestedUrls => platform.requestedUrls;
  Map<String, ArtifactFileEvent> get terminalEvents => platform.terminalEvents;
  Map<String, String> get contents => platform.contents;
  int get pauseCalls => platform.pauseCalls;
  int get cancelCalls => platform.cancelCalls;

  @override
  Future<void> initialize() async => platform.initializeCalls++;

  @override
  Future<ArtifactTransferSnapshot> inspect(ArtifactFileRef ref) async {
    final destination = ref.destination;
    final resumable = platform.resumable.contains(destination);
    if (platform.inFlight.contains(destination)) {
      return ArtifactTransferSnapshot(
        presence: ArtifactTransferPresence.running,
        receivedBytes: platform.surviving[destination],
        resumable: resumable,
      );
    }
    final bytes = platform.surviving[destination];
    if (bytes == null && !resumable) return const ArtifactTransferSnapshot();
    return ArtifactTransferSnapshot(
      presence: ArtifactTransferPresence.paused,
      receivedBytes: bytes,
      resumable: resumable,
    );
  }

  @override
  Stream<ArtifactFileEvent> download(ArtifactFileRef ref) async* {
    await initialize();
    platform.requestedUrls.add(ref.sourceUrl);
    // Adoption reuses the surviving transfer rather than starting a second one,
    // so the enqueue log stays at one entry per destination.
    final adopted = platform.surviving.remove(ref.destination);
    if (adopted == null) {
      platform.enqueued.add(ref.destination);
    } else {
      yield ArtifactFileProgress(adopted);
    }
    platform.resumable.remove(ref.destination);
    platform.inFlight.add(ref.destination);
    try {
      yield ArtifactFileProgress(ref.expectedBytes ~/ 2);
      final terminal =
          platform.terminalEvents[ref.filename] ?? const ArtifactFileComplete();
      if (terminal is ArtifactFileComplete) {
        final file = File(
          '${platform.documentsDirectory}/${ref.directory}/${ref.filename}',
        );
        await file.parent.create(recursive: true);
        await file.writeAsString(platform.contents[ref.filename]!);
        yield ArtifactFileProgress(ref.expectedBytes);
      }
      yield terminal;
    } finally {
      platform.inFlight.remove(ref.destination);
    }
  }

  @override
  Future<bool> pause(ArtifactFileRef ref) async {
    platform.pausedRefs.add(ref.destination);
    // Only a transfer the platform actually holds can be paused; the seam
    // reports that honestly so the repository never claims a false pause.
    if (!platform.inFlight.contains(ref.destination) &&
        !platform.surviving.containsKey(ref.destination)) {
      return false;
    }
    platform.pauseCalls++;
    return true;
  }

  @override
  Future<bool> cancel(ArtifactFileRef ref) async {
    platform.canceledRefs.add(ref.destination);
    platform.cancelCalls++;
    platform.surviving.remove(ref.destination);
    platform.resumable.remove(ref.destination);
    return true;
  }
}

final class _FixedDiskSpace implements DiskSpaceProbe {
  _FixedDiskSpace(this.free);
  int? free;
  @override
  Future<int?> freeBytes(String path) async => free;
}

final class _RecordingBackupExclusion implements BackupExclusion {
  final List<String> excluded = [];
  @override
  Future<void> exclude(String path) async => excluded.add(path);
}

void main() {
  late Directory temp;
  late _FakePlatform platform;
  late _ScriptedDownloader downloader;
  late _FixedDiskSpace diskSpace;
  late _RecordingBackupExclusion backup;

  RealModelManagementRepository repository({
    String? activeKey,
    List<ModelCatalogEntry>? catalog,
  }) => RealModelManagementRepository(
    stateFile: File('${temp.path}/state/flutter-model-v2.json'),
    documentsDirectory: '${temp.path}/documents',
    catalog: catalog ?? [_entry()],
    downloader: downloader,
    diskSpace: diskSpace,
    backupExclusion: backup,
    activeArtifactKey: activeKey,
    diskSpaceMargin: 10,
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('golem-real-repo-');
    addTearDown(() => temp.deleteSync(recursive: true));
    platform = _FakePlatform('${temp.path}/documents');
    downloader = _ScriptedDownloader(platform);
    diskSpace = _FixedDiskSpace(1 << 30);
    backup = _RecordingBackupExclusion();
  });

  test('downloads, verifies, installs, and hits pinned URLs', () async {
    final repo = repository(activeKey: 'test-mlx');
    await repo.load();
    final states = await repo.download('test-mlx').toList();
    expect(states.last.statusOf('test-mlx').phase, ArtifactPhase.installed);
    expect(
      states.last.statusOf('test-mlx').downloadedBytes,
      _entry().totalBytes,
    );
    expect(
      states.map((state) => state.statusOf('test-mlx').phase).toSet(),
      containsAll([
        ArtifactPhase.downloading,
        ArtifactPhase.verifying,
        ArtifactPhase.installed,
      ]),
    );
    expect(states.last.simulated, isFalse);
    expect(downloader.requestedUrls, [
      'https://huggingface.co/example/test-mlx/resolve/0123456789abcdef/$_fileOne',
      'https://huggingface.co/projectors/test-weights/resolve/fedcba9876543210/$_fileTwo',
    ]);
    expect(backup.excluded, ['${temp.path}/documents/models']);
    expect(
      File('${temp.path}/documents/models/test-mlx/$_fileTwo').existsSync(),
      isTrue,
    );
    // Installed and active: a reported loaded phase persists.
    expect(
      (await repo.recordRuntime(RuntimePhase.loaded)).runtime,
      RuntimePhase.loaded,
    );
  });

  test('skip-if-valid never re-downloads verified files', () async {
    final repo = repository();
    await repo.load();
    await repo.download('test-mlx').drain<void>();
    expect(downloader.requestedUrls, hasLength(2));
    downloader.requestedUrls.clear();
    final states = await repo.download('test-mlx').toList();
    expect(downloader.requestedUrls, isEmpty);
    expect(states.last.statusOf('test-mlx').phase, ArtifactPhase.installed);
  });

  test('insufficient disk space fails before any network use', () async {
    diskSpace.free = 5;
    final repo = repository();
    await repo.load();
    final states = await repo.download('test-mlx').toList();
    final status = states.single.statusOf('test-mlx');
    expect(status.phase, ArtifactPhase.failed);
    expect(status.failure, contains('free'));
    expect(status.failureReason?.kind, ArtifactFailureKind.insufficientStorage);
    expect(status.failureReason?.availableBytes, 5);
    expect(downloader.requestedUrls, isEmpty);
  });

  test('a SHA-256 mismatch deletes the file and fails the artifact', () async {
    downloader.contents[_fileOne] = 'corrupted content bytes!!';
    // Match the expected length so only the hash differs.
    downloader.contents[_fileOne] = 'x' * _contentOne.length;
    final repo = repository();
    await repo.load();
    final states = await repo.download('test-mlx').toList();
    final status = states.last.statusOf('test-mlx');
    expect(status.phase, ArtifactPhase.failed);
    expect(status.failure, contains('SHA-256'));
    expect(status.failureReason?.kind, ArtifactFailureKind.hashVerification);
    expect(status.failureReason?.fileName, _fileOne);
    expect(
      File('${temp.path}/documents/models/test-mlx/$_fileOne').existsSync(),
      isFalse,
    );
  });

  test('pause stops the stream without emitting past the pause', () async {
    downloader.terminalEvents[_fileOne] = const ArtifactFilePaused();
    final repo = repository();
    await repo.load();
    final stream = repo.download('test-mlx');
    final states = <ModelState>[];
    await for (final state in stream) {
      states.add(state);
      if (states.length == 2) {
        await repo.pause('test-mlx');
      }
    }
    expect(downloader.pauseCalls, 1);
    final after = await repository().load();
    expect(after.statusOf('test-mlx').phase, ArtifactPhase.paused);
  });

  test('cancel discards partial files; delete uninstalls', () async {
    final repo = repository();
    await repo.load();
    await repo.download('test-mlx').drain<void>();
    final cancelled = await repo.cancel('test-mlx');
    // A stop names only the artifact, so it must address every file of it —
    // otherwise a transfer the app forgot keeps writing into the directory
    // being deleted.
    expect(platform.canceledRefs, [
      'models/test-mlx/$_fileOne',
      'models/test-mlx/$_fileTwo',
    ]);
    expect(cancelled.statusOf('test-mlx').phase, ArtifactPhase.notDownloaded);
    expect(
      Directory('${temp.path}/documents/models/test-mlx').existsSync(),
      isFalse,
    );
    await repo.download('test-mlx').drain<void>();
    final deleted = await repo.delete('test-mlx');
    expect(deleted.statusOf('test-mlx').phase, ArtifactPhase.notDownloaded);
    expect(
      Directory('${temp.path}/documents/models/test-mlx').existsSync(),
      isFalse,
    );
  });

  // Crediting a partial the platform threw away shows a card at 60% whose
  // Resume restarts from zero — a bar that jumps backwards reads as lost work.
  test('an unresumable pause credits only verified bytes', () async {
    platform.terminalEvents[_fileOne] = const ArtifactFilePaused(
      userInitiated: false,
      resumable: false,
    );
    final repo = repository();
    await repo.load();
    final states = await repo.download('test-mlx').toList();
    final status = states.last.statusOf('test-mlx');
    expect(status.phase, ArtifactPhase.paused);
    // Nothing was verified before the first file stopped, so nothing counts.
    expect(status.downloadedBytes, 0);
  });

  test('a resumable pause keeps the streamed progress', () async {
    platform.terminalEvents[_fileOne] = const ArtifactFilePaused(
      userInitiated: false,
    );
    final repo = repository();
    await repo.load();
    final states = await repo.download('test-mlx').toList();
    final status = states.last.statusOf('test-mlx');
    expect(status.phase, ArtifactPhase.paused);
    expect(status.downloadedBytes, greaterThan(0));
  });

  // A second repository over the same platform is a relaunch: the app forgot
  // everything, the OS did not.
  group('reconciliation across a process recreation', () {
    Future<void> interrupt(RealModelManagementRepository repo) async {
      await repo.load();
      // Stop the stream the way a killed process would — mid-file, with no
      // terminal event and nothing persisted past the interruption.
      platform.terminalEvents[_fileOne] = const ArtifactFilePaused(
        userInitiated: false,
      );
      await repo.download('test-mlx').drain<void>();
      platform.terminalEvents.remove(_fileOne);
    }

    test('a transfer the OS is still running reads as downloading', () async {
      await interrupt(repository());
      // The platform kept the first file's transfer alive across the relaunch.
      platform.surviving['models/test-mlx/$_fileOne'] = 512;
      platform.inFlight.add('models/test-mlx/$_fileOne');

      final relaunched = await repository().load();
      // Not Paused: bytes are moving, and inviting Resume here is what put a
      // second writer on the file.
      expect(relaunched.statusOf('test-mlx').phase, ArtifactPhase.downloading);
      expect(relaunched.statusOf('test-mlx').downloadedBytes, 512);
    });

    test('a transfer the OS dropped reads as paused', () async {
      await interrupt(repository());
      final relaunched = await repository().load();
      expect(relaunched.statusOf('test-mlx').phase, ArtifactPhase.paused);
    });

    test('a resumable partial counts toward progress', () async {
      await interrupt(repository());
      // Partial bytes live in the plugin's staging file, never at the
      // destination, so only the platform can report them.
      platform.surviving['models/test-mlx/$_fileOne'] = 900;
      platform.resumable.add('models/test-mlx/$_fileOne');

      final relaunched = await repository().load();
      expect(relaunched.statusOf('test-mlx').phase, ArtifactPhase.paused);
      expect(relaunched.statusOf('test-mlx').downloadedBytes, 900);
    });

    test(
      'resuming adopts the surviving transfer instead of a second one',
      () async {
        await interrupt(repository());
        platform.surviving['models/test-mlx/$_fileOne'] = 900;
        platform.resumable.add('models/test-mlx/$_fileOne');
        platform.enqueued.clear();

        final repo = repository();
        await repo.load();
        await repo.download('test-mlx').drain<void>();

        // One enqueue per destination, ever: the surviving transfer was taken
        // over, not duplicated.
        expect(platform.enqueued, ['models/test-mlx/$_fileTwo']);
      },
    );

    test(
      'a stop after relaunch still reaches the surviving transfer',
      () async {
        await interrupt(repository());
        platform.surviving['models/test-mlx/$_fileOne'] = 900;

        // The previous process's downloader object is long gone; the refs are
        // re-derived from the catalog, so the stop still lands.
        final relaunched = repository();
        await relaunched.load();
        await relaunched.cancel('test-mlx');
        expect(platform.surviving, isEmpty);
      },
    );
  });

  test('load reconciles persisted state against the disk', () async {
    final repo = repository();
    await repo.load();
    await repo.download('test-mlx').drain<void>();
    // Externally removing one file demotes "installed" to "notDownloaded".
    File('${temp.path}/documents/models/test-mlx/$_fileOne').deleteSync();
    final demoted = await repository().load();
    expect(demoted.statusOf('test-mlx').phase, ArtifactPhase.notDownloaded);

    // A kill mid-download relaunches as paused at the on-disk byte count.
    await File('${temp.path}/state/flutter-model-v2.json').writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'runtime': 'loading',
        'failure': null,
        'artifacts': {
          'test-mlx': {'phase': 'downloading', 'downloadedBytes': 999999},
        },
      }),
    );
    final resumed = await repository().load();
    expect(resumed.statusOf('test-mlx').phase, ArtifactPhase.paused);
    // _fileTwo is still fully present on disk; _fileOne was removed above.
    expect(resumed.statusOf('test-mlx').downloadedBytes, _contentTwo.length);
    expect(resumed.runtime, RuntimePhase.unloaded);
  });

  test('right-length forgeries are hashed, rejected, and re-fetched', () async {
    // Stage both files at their exact pinned sizes with wrong content and no
    // verification receipt — the sparse-file spoof from review.
    for (final (path, length) in [
      (_fileOne, _contentOne.length),
      (_fileTwo, _contentTwo.length),
    ]) {
      final file = File('${temp.path}/documents/models/test-mlx/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('#' * length);
    }
    final repo = repository();
    await repo.load();
    final states = await repo.download('test-mlx').toList();
    // Both forgeries were hashed, deleted, and downloaded for real.
    expect(downloader.requestedUrls, hasLength(2));
    expect(states.last.statusOf('test-mlx').phase, ArtifactPhase.installed);
    expect(
      File(
        '${temp.path}/documents/models/test-mlx/.golem-verified.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('the verified fast path needs the receipt, not just sizes', () async {
    final repo = repository();
    await repo.load();
    await repo.download('test-mlx').drain<void>();

    // Receipt present: a lost state file re-earns installed with no
    // network and no re-hash prompt to the user beyond one tap.
    File('${temp.path}/state/flutter-model-v2.json').deleteSync();
    final rebuilt = repository();
    expect(
      (await rebuilt.load()).statusOf('test-mlx').phase,
      ArtifactPhase.notDownloaded,
    );
    downloader.requestedUrls.clear();
    final states = await rebuilt.download('test-mlx').toList();
    expect(downloader.requestedUrls, isEmpty);
    expect(states.last.statusOf('test-mlx').phase, ArtifactPhase.installed);

    // Receipt missing: "installed" is not re-earned by size alone on load…
    File(
      '${temp.path}/documents/models/test-mlx/.golem-verified.json',
    ).deleteSync();
    final demoted = await repository().load();
    expect(demoted.statusOf('test-mlx').phase, ArtifactPhase.notDownloaded);
    // …and a download hashes the files in place instead of trusting them.
    downloader.requestedUrls.clear();
    final rehashed = await repository().download('test-mlx').toList();
    expect(downloader.requestedUrls, isEmpty);
    expect(
      rehashed.map((state) => state.statusOf('test-mlx').phase),
      contains(ArtifactPhase.verifying),
    );
    expect(rehashed.last.statusOf('test-mlx').phase, ArtifactPhase.installed);
  });

  test(
    'an uncommanded pause is persisted instead of stranding the card',
    () async {
      downloader.terminalEvents[_fileOne] = const ArtifactFilePaused(
        userInitiated: false,
      );
      final repo = repository();
      await repo.load();
      final states = await repo.download('test-mlx').toList();
      final status = states.last.statusOf('test-mlx');
      expect(status.phase, ArtifactPhase.paused);
      expect(downloader.pauseCalls, 0);
    },
  );

  test(
    'delete stops an in-flight download and resets an active runtime',
    () async {
      final repo = repository(activeKey: 'test-mlx');
      await repo.load();
      await repo.download('test-mlx').drain<void>();
      expect(
        (await repo.recordRuntime(RuntimePhase.loaded)).runtime,
        RuntimePhase.loaded,
      );

      final deleted = await repo.delete('test-mlx');
      expect(deleted.statusOf('test-mlx').phase, ArtifactPhase.notDownloaded);
      // Deleting the weights cannot leave a loaded runtime behind…
      expect(deleted.runtime, RuntimePhase.unloaded);
      // …and delete stops every one of the entry's transfers, like cancel.
      expect(platform.canceledRefs, [
        'models/test-mlx/$_fileOne',
        'models/test-mlx/$_fileTwo',
      ]);

      // Relaunch reconciliation applies the same rule to persisted state.
      await repo.download('test-mlx').drain<void>();
      await repo.recordRuntime(RuntimePhase.loaded);
      Directory(
        '${temp.path}/documents/models/test-mlx',
      ).deleteSync(recursive: true);
      final reloaded = await repository(activeKey: 'test-mlx').load();
      expect(reloaded.statusOf('test-mlx').phase, ArtifactPhase.notDownloaded);
      expect(reloaded.runtime, RuntimePhase.unloaded);
    },
  );

  test('a persisted loaded phase never survives a relaunch', () async {
    final repo = repository(activeKey: 'test-mlx');
    await repo.load();
    await repo.download('test-mlx').drain<void>();
    expect(
      (await repo.recordRuntime(RuntimePhase.loaded)).runtime,
      RuntimePhase.loaded,
    );

    // The engine died with the process even though the install still
    // verifies: loaded is a claim about the engine and must reconcile to
    // unloaded on every fresh load(), or Settings reads "Ready" over a
    // cold engine.
    final relaunched = await repository(activeKey: 'test-mlx').load();
    expect(relaunched.statusOf('test-mlx').phase, ArtifactPhase.installed);
    expect(relaunched.runtime, RuntimePhase.unloaded);
  });

  test('an unknown free-space reading skips the preflight', () async {
    diskSpace.free = null;
    final repo = repository();
    await repo.load();
    final states = await repo.download('test-mlx').toList();
    expect(states.last.statusOf('test-mlx').phase, ArtifactPhase.installed);
  });

  test('a recorded failed phase persists with its message', () async {
    // The refusal decision lives in ModelController since #42 (covered in
    // controllers_test); the repository just records what it is told.
    final repo = repository();
    await repo.load();
    final failed = await repo.recordRuntime(
      RuntimePhase.failed,
      failure: 'Inference is a build-time opt-in; no backend is configured.',
    );
    expect(failed.runtime, RuntimePhase.failed);
    expect(failed.failure, contains('build-time opt-in'));

    final cleared = await repo.recordRuntime(RuntimePhase.unloaded);
    expect(cleared.runtime, RuntimePhase.unloaded);
    expect(cleared.failure, isNull);
  });

  group('addModel', () {
    ModelCatalogEntry custom() => ModelCatalogEntry(
      key: 'custom-example-12345678',
      displayName: 'Example',
      engine: ModelEngine.gguf,
      quantization: 'Q4_0',
      repository: 'example/custom',
      revision: 'a' * 40,
      profileKey: 'gemma4',
      files: [
        ModelArtifactFile(
          path: _fileOne,
          bytes: _contentOne.length,
          sha256: sha256.convert(utf8.encode(_contentOne)).toString(),
          role: ModelFileRole.weights,
        ),
      ],
    );

    test('a registered entry downloads like any pinned one', () async {
      final repo = repository();
      await repo.load();
      final added = await repo.addModel(custom());
      expect(
        added.statusOf('custom-example-12345678').phase,
        ArtifactPhase.notDownloaded,
      );
      final states = await repo.download('custom-example-12345678').toList();
      expect(
        states.last.statusOf('custom-example-12345678').phase,
        ArtifactPhase.installed,
      );
      expect(
        downloader.requestedUrls.single,
        'https://huggingface.co/example/custom/resolve/${'a' * 40}/$_fileOne',
      );
    });

    test('the caller\'s catalog list is never grown in place', () async {
      // main.dart passes the shared top-level `modelCatalog`, which the model
      // catalog provider also receives; extending it would leak custom entries
      // into the pinned set and make a top-level value mutable.
      final pinned = [_entry()];
      final repo = RealModelManagementRepository(
        stateFile: File('${temp.path}/state/flutter-model-v2.json'),
        documentsDirectory: '${temp.path}/documents',
        catalog: pinned,
        downloader: downloader,
        diskSpace: diskSpace,
        backupExclusion: backup,
      );
      await repo.load();
      await repo.addModel(custom());
      expect(pinned, hasLength(1));
      expect(pinned.single.key, 'test-mlx');
    });

    test('re-adding refreshes the entry without losing its install', () async {
      final repo = repository();
      await repo.load();
      await repo.addModel(custom());
      await repo.download('custom-example-12345678').drain<void>();

      // A repaste that resolved to the same commit must not present as fresh.
      final again = await repo.addModel(custom());
      expect(
        again.statusOf('custom-example-12345678').phase,
        ArtifactPhase.installed,
      );
      downloader.requestedUrls.clear();
      await repo.download('custom-example-12345678').drain<void>();
      expect(downloader.requestedUrls, isEmpty);
    });

    test('a re-add at a new commit re-earns its verification', () async {
      final repo = repository();
      await repo.load();
      await repo.addModel(custom());
      await repo.download('custom-example-12345678').drain<void>();

      // Receipts are scoped by revision, so the same bytes at a different
      // commit are unproven rather than inheriting the previous proof.
      final moved = ModelCatalogEntry(
        key: 'custom-example-12345678',
        displayName: 'Example',
        engine: ModelEngine.gguf,
        quantization: 'Q4_0',
        repository: 'example/custom',
        revision: 'b' * 40,
        profileKey: 'gemma4',
        files: custom().files,
      );
      final added = await repo.addModel(moved);
      expect(
        added.statusOf('custom-example-12345678').phase,
        ArtifactPhase.notDownloaded,
      );
    });
  });

  group('files published without a hash', () {
    // Hugging Face returns an LFS SHA-256 for large files and nothing for
    // small metadata ones, so a resolved custom repository (#52) mixes both
    // kinds inside one entry. The pinned half must lose no strictness.
    const unhashed = 'tokenizer_config.json';
    const unhashedBody = 'tokenizer configuration, unhashed upstream';

    ModelCatalogEntry mixedEntry() => ModelCatalogEntry(
      key: 'custom-mixed',
      displayName: 'Mixed',
      engine: ModelEngine.mlx,
      quantization: 'custom',
      repository: 'example/mixed',
      revision: 'aaaabbbbccccdddd',
      profileKey: 'gemma4',
      files: [
        ModelArtifactFile(
          path: _fileOne,
          bytes: _contentOne.length,
          sha256: sha256.convert(utf8.encode(_contentOne)).toString(),
        ),
        // The distinguishing case: no published hash at all.
        const ModelArtifactFile(path: unhashed, bytes: unhashedBody.length),
      ],
    );

    Map<String, Object?> receiptOf(String key) => Map<String, Object?>.from(
      jsonDecode(
            File(
              '${temp.path}/documents/models/$key/.golem-verified.json',
            ).readAsStringSync(),
          )
          as Map,
    );

    setUp(() => downloader.contents[unhashed] = unhashedBody);

    test('install records the digest the bytes actually hashed to', () async {
      final repo = repository(catalog: [mixedEntry()]);
      await repo.load();
      final states = await repo.download('custom-mixed').toList();
      expect(
        states.last.statusOf('custom-mixed').phase,
        ArtifactPhase.installed,
      );
      final files = receiptOf('custom-mixed')['files'] as Map;
      // Both kinds are receipted the same way: by content. The pinned file's
      // recorded value must equal what was published for it.
      expect(
        files[_fileOne],
        sha256.convert(utf8.encode(_contentOne)).toString(),
      );
      expect(
        files[unhashed],
        sha256.convert(utf8.encode(unhashedBody)).toString(),
      );
    });

    test('a matching size alone never re-earns the verified label', () async {
      // The trap this guards: comparing `receipt[path] != spec.sha256` treats a
      // missing entry and a null published hash as equal, so an unreceipted
      // file of the right length would have counted as installed.
      final repo = repository(catalog: [mixedEntry()]);
      await repo.load();
      await repo.download('custom-mixed').toList();

      // Keep the bytes, drop the receipt — a sideload, or a verify killed
      // midway.
      File(
        '${temp.path}/documents/models/custom-mixed/.golem-verified.json',
      ).deleteSync();
      final reloaded = await repository(catalog: [mixedEntry()]).load();
      expect(
        reloaded.statusOf('custom-mixed').phase,
        ArtifactPhase.notDownloaded,
      );

      // Re-downloading hashes what is already there rather than refetching.
      downloader.requestedUrls.clear();
      final states = await repository(
        catalog: [mixedEntry()],
      ).download('custom-mixed').toList();
      expect(
        states.last.statusOf('custom-mixed').phase,
        ArtifactPhase.installed,
      );
      expect(downloader.requestedUrls, isEmpty);
    });

    test('a pinned file in the same entry still needs its hash', () async {
      // Same length, different bytes, so only the hash can reject it.
      downloader.contents[_fileOne] = 'x' * _contentOne.length;
      final states = await repository(
        catalog: [mixedEntry()],
      ).download('custom-mixed').toList();
      final status = states.last.statusOf('custom-mixed');
      expect(status.phase, ArtifactPhase.failed);
      expect(status.failure, contains('failed SHA-256 verification'));
    });

    test('a wrong length is reported as a size failure', () async {
      // An unhashed file can only fail on length, and saying "failed SHA-256
      // verification" would name a check that never ran.
      downloader.contents[unhashed] = 'short';
      final states = await repository(
        catalog: [mixedEntry()],
      ).download('custom-mixed').toList();
      final status = states.last.statusOf('custom-mixed');
      expect(status.phase, ArtifactPhase.failed);
      expect(status.failure, contains('did not arrive at its expected size'));
      expect(status.failure, isNot(contains('SHA-256')));
      expect(status.failureReason?.kind, ArtifactFailureKind.unexpectedSize);
      expect(status.failureReason?.fileName, unhashed);
      expect(
        File(
          '${temp.path}/documents/models/custom-mixed/$unhashed',
        ).existsSync(),
        isFalse,
      );
    });
  });
}
