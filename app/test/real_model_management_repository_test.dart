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
    ),
  ],
);

/// Scripted downloader: writes configured content (or garbage) into the
/// destination and replays a configured terminal event.
final class _ScriptedDownloader implements ArtifactFileDownloader {
  _ScriptedDownloader(this.documentsDirectory);

  final String documentsDirectory;
  final List<String> requestedUrls = [];
  // Keyed by filename (the downloader seam sees basenames, not paths).
  final Map<String, ArtifactFileEvent> terminalEvents = {};
  final Map<String, String> contents = {
    'config.json': _contentOne,
    'model.bin': _contentTwo,
  };
  int pauseCalls = 0;
  int cancelCalls = 0;

  @override
  Stream<ArtifactFileEvent> download({
    required String url,
    required String directory,
    required String filename,
    required int expectedBytes,
  }) async* {
    requestedUrls.add(url);
    yield ArtifactFileProgress(expectedBytes ~/ 2);
    final terminal = terminalEvents[filename] ?? const ArtifactFileComplete();
    if (terminal is ArtifactFileComplete) {
      final file = File('$documentsDirectory/$directory/$filename');
      await file.parent.create(recursive: true);
      await file.writeAsString(contents[filename]!);
      yield ArtifactFileProgress(expectedBytes);
    }
    yield terminal;
  }

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> cancel() async => cancelCalls++;
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
  late _ScriptedDownloader downloader;
  late _FixedDiskSpace diskSpace;
  late _RecordingBackupExclusion backup;

  RealModelManagementRepository repository({String? activeKey}) =>
      RealModelManagementRepository(
        stateFile: File('${temp.path}/state/flutter-model-v2.json'),
        documentsDirectory: '${temp.path}/documents',
        catalog: [_entry()],
        downloader: downloader,
        diskSpace: diskSpace,
        backupExclusion: backup,
        activeArtifactKey: activeKey,
        diskSpaceMargin: 10,
      );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('golem-real-repo-');
    addTearDown(() => temp.deleteSync(recursive: true));
    downloader = _ScriptedDownloader('${temp.path}/documents');
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
      'https://huggingface.co/example/test-mlx/resolve/0123456789abcdef/$_fileTwo',
    ]);
    expect(backup.excluded, ['${temp.path}/documents/models']);
    // The nested file landed inside the artifact directory.
    expect(
      File('${temp.path}/documents/models/test-mlx/$_fileTwo').existsSync(),
      isTrue,
    );
    // Installed and active: the runtime now loads.
    expect((await repo.loadRuntime()).runtime, RuntimePhase.loaded);
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
    expect(downloader.cancelCalls, 1);
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
      expect((await repo.loadRuntime()).runtime, RuntimePhase.loaded);

      final deleted = await repo.delete('test-mlx');
      expect(deleted.statusOf('test-mlx').phase, ArtifactPhase.notDownloaded);
      // Deleting the weights cannot leave a loaded runtime behind…
      expect(deleted.runtime, RuntimePhase.unloaded);
      // …and delete cancels the downloader like cancel does.
      expect(downloader.cancelCalls, 1);

      // Relaunch reconciliation applies the same rule to persisted state.
      await repo.download('test-mlx').drain<void>();
      await repo.loadRuntime();
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
    expect((await repo.loadRuntime()).runtime, RuntimePhase.loaded);

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

  test('runtime refuses to load without an installed active model', () async {
    final unconfigured = repository();
    await unconfigured.load();
    final noBackend = await unconfigured.loadRuntime();
    expect(noBackend.runtime, RuntimePhase.failed);
    expect(noBackend.failure, contains('build-time opt-in'));

    final configured = repository(activeKey: 'test-mlx');
    await configured.load();
    final notInstalled = await configured.loadRuntime();
    expect(notInstalled.runtime, RuntimePhase.failed);
    expect(notInstalled.failure, contains('install the active model'));
  });
}
