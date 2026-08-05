import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/real_model_management_repository.dart';
import 'package:golem_flutter/core/services/artifact_downloader.dart';
import 'package:golem_flutter/core/services/device_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Real-network smoke for the download stack, macOS only:
///
///   flutter test integration_test/real_download_smoke_test.dart -d macos \
///     --flavor qa --dart-define=GOLEM_DOWNLOAD_SMOKE=true
///
/// Downloads only the small files (< 25 MB) of the pinned Qwen MLX artifact
/// through the full production stack — background_downloader, pinned
/// resolve URLs with CDN redirects, streaming SHA-256, the storage channel
/// — then exercises skip-if-valid and delete. CI never sets the define, so
/// this self-skips there and downloads nothing.
const _enabled = bool.fromEnvironment('GOLEM_DOWNLOAD_SMOKE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'small pinned files download, verify, skip-if-valid, and delete',
    skip: _enabled
        ? false
        : 'Set --dart-define=GOLEM_DOWNLOAD_SMOKE=true to run the '
              'real-network download smoke.',
    () async {
      final source = modelCatalog.firstWhere(
        (entry) => entry.key == 'qwen35-mlx',
      );
      final smallFiles = source.files
          .where((file) => file.bytes < 25 * 1000 * 1000)
          .toList();
      expect(smallFiles, isNotEmpty);
      final entry = ModelCatalogEntry(
        key: 'smoke-qwen35-mlx',
        displayName: 'Smoke ${source.displayName}',
        engine: source.engine,
        quantization: source.quantization,
        repository: source.repository,
        revision: source.revision,
        files: smallFiles,
      );

      final documents = await getApplicationDocumentsDirectory();
      final temp = await Directory.systemTemp.createTemp('golem-smoke-state-');
      addTearDown(() => temp.delete(recursive: true));
      final repository = RealModelManagementRepository(
        stateFile: File('${temp.path}/flutter-model-v2.json'),
        documentsDirectory: documents.path,
        catalog: [entry],
        downloader: BackgroundArtifactDownloader(),
        diskSpace: const DeviceStorageChannel(),
        backupExclusion: const DeviceStorageChannel(),
      );
      await repository.load();

      final states = await repository
          .download(entry.key)
          .timeout(const Duration(minutes: 5))
          .toList();
      final status = states.last.statusOf(entry.key);
      expect(
        status.phase,
        ArtifactPhase.installed,
        reason: 'last failure: ${status.failure}',
      );
      expect(status.downloadedBytes, entry.totalBytes);
      for (final spec in entry.files) {
        final file = File(
          '${documents.path}/${entry.installDirectory}/${spec.path}',
        );
        expect(await file.exists(), isTrue, reason: spec.path);
        expect(await file.length(), spec.bytes, reason: spec.path);
      }

      // Skip-if-valid: a second run re-downloads nothing and stays installed.
      final again = await repository.download(entry.key).toList();
      expect(again.last.statusOf(entry.key).phase, ArtifactPhase.installed);

      // Delete removes the smoke directory this test created.
      final deleted = await repository.delete(entry.key);
      expect(deleted.statusOf(entry.key).phase, ArtifactPhase.notDownloaded);
      expect(
        await Directory('${documents.path}/${entry.installDirectory}').exists(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
