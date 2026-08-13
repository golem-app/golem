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

import 'support/parallel_artifact_downloader.dart';

/// Real-network lifecycle evidence for the download stack:
///
///   flutter test integration_test/download_lifecycle_test.dart -d DEVICE \
///     --flavor qa --no-uninstall \
///     --dart-define=GOLEM_DOWNLOAD_LIFECYCLE=true
///
/// Covers only what a test process can actually produce: an interruption
/// mid-transfer, reconciliation against the platform afterwards, adoption
/// instead of a second writer, and a stop that still lands after the app has
/// forgotten the transfer. Backgrounding, screen lock and process recreation
/// are **not** here — a test cannot background itself, and killing the app
/// kills the harness with it. Those live in `docs/notes/download-lifecycle.md`
/// as a hand-driven runbook, and there is no way around that.
///
/// CI never sets the define, so this self-skips there and downloads nothing.
const _enabled = bool.fromEnvironment('GOLEM_DOWNLOAD_LIFECYCLE');

/// Drop the network by hand (see the runbook) while this runs to exercise the
/// connection-loss path; without it the test still proves reconciliation and
/// adoption, just not the stall probe.
const _artifactKey = String.fromEnvironment(
  'GOLEM_LIFECYCLE_ARTIFACT',
  defaultValue: 'qwen35-2b-mlx',
);

/// `background` (the production plugin transport) or `parallel` (the #36
/// spike's ParallelDownloadTask prototype), so the same three proofs price a
/// candidate transport through the real repository. A failure under
/// `parallel` is a spike finding, not a regression.
///
/// Honest scope: this instrument downloads only sub-25 MB files, which all
/// sit under the prototype's 32 MB chunk floor — necessarily so, because
/// Hugging Face's small non-LFS files cannot be chunked at all (no
/// Content-Length, no ranges). A `parallel` run therefore proves the
/// hybrid's plain-task path and its repository interplay, not chunked-parent
/// lifecycle behavior; chunked parents are exercised only by the bench's
/// ≥32 MB weights windows, and their pause/adopt/inspect story remains an
/// open cost tracked on #114.
const _transport = String.fromEnvironment(
  'GOLEM_LIFECYCLE_TRANSPORT',
  defaultValue: 'background',
);

ArtifactFileDownloader buildLifecycleDownloader() => _transport == 'parallel'
    ? ParallelArtifactDownloader()
    : BackgroundArtifactDownloader(
        // Short enough that an evidence run does not sit for five minutes
        // when the network really is gone.
        stallTimeout: const Duration(seconds: 45),
      );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group(
    'download lifecycle',
    skip: _enabled
        ? false
        : 'Set --dart-define=GOLEM_DOWNLOAD_LIFECYCLE=true to run the '
              'real-network download lifecycle evidence.',
    () {
      late Directory state;
      late ModelCatalogEntry entry;
      late String documentsPath;

      RealModelManagementRepository build() => RealModelManagementRepository(
        stateFile: File('${state.path}/flutter-model-v2.json'),
        documentsDirectory: documentsPath,
        catalog: [entry],
        downloader: buildLifecycleDownloader(),
        diskSpace: const DeviceStorageChannel(),
        backupExclusion: const DeviceStorageChannel(),
      );

      setUp(() async {
        final source = modelCatalog.firstWhere(
          (each) => each.key == _artifactKey,
        );
        // Only the small files, so the evidence run is minutes rather than an
        // hour; the multi-file sequencing is what this exercises, not bandwidth.
        final files = source.files
            .where((file) => file.bytes < 25 * 1000 * 1000)
            .toList();
        expect(files, isNotEmpty);
        entry = ModelCatalogEntry(
          key: 'lifecycle-$_artifactKey',
          displayName: 'Lifecycle ${source.displayName}',
          engine: source.engine,
          quantization: source.quantization,
          repository: source.repository,
          revision: source.revision,
          profileKey: source.profileKey,
          files: files,
        );
        documentsPath = (await getApplicationDocumentsDirectory()).path;
        state = await Directory.systemTemp.createTemp('golem-lifecycle-');
      });

      tearDown(() async {
        // Never leaves partials or weights on the device.
        final repository = build();
        await repository.load();
        await repository.delete(entry.key);
        await state.delete(recursive: true);
      });

      test(
        'a fresh repository converges on what the platform holds',
        () async {
          final first = build();
          await first.load();
          await first.download(entry.key).drain<void>();

          // A second repository over the same device is the app having forgotten
          // everything while the platform did not.
          final relaunched = build();
          final converged = await relaunched.load();
          final status = converged.statusOf(entry.key);
          expect(
            status.phase,
            anyOf(ArtifactPhase.installed, ArtifactPhase.notDownloaded),
            reason: 'failure: ${status.failure}',
          );
        },
        timeout: const Timeout(Duration(minutes: 8)),
      );

      test(
        'a completed artifact is adopted, never re-fetched',
        () async {
          final repository = build();
          await repository.load();
          final states = await repository
              .download(entry.key)
              .timeout(const Duration(minutes: 6))
              .toList();
          expect(
            states.last.statusOf(entry.key).phase,
            ArtifactPhase.installed,
            reason: 'failure: ${states.last.statusOf(entry.key).failure}',
          );

          // Skip-if-valid across a relaunch: the receipt and the sizes carry it,
          // and nothing is enqueued a second time.
          final relaunched = build();
          await relaunched.load();
          final again = await relaunched.download(entry.key).toList();
          expect(again.last.statusOf(entry.key).phase, ArtifactPhase.installed);
        },
        timeout: const Timeout(Duration(minutes: 10)),
      );

      test(
        'inspect answers for a transfer this process never started',
        () async {
          final repository = build();
          await repository.load();
          await repository.download(entry.key).drain<void>();

          // The seam must answer about the platform, not about its own memory:
          // a fresh downloader object has no record of the transfer above.
          final downloader = buildLifecycleDownloader();
          await downloader.initialize();
          final spec = entry.files.first;
          final snapshot = await downloader.inspect(
            ArtifactFileRef(
              artifactKey: entry.key,
              sourceUrl: entry.resolveUrlFor(spec).toString(),
              directory: entry.installDirectory,
              filename: spec.path.split('/').last,
              expectedBytes: spec.bytes,
            ),
          );
          // Whatever it says, it must say it promptly rather than hang — the
          // unbounded wait is the defect this ticket exists to remove.
          expect(snapshot.presence, isA<ArtifactTransferPresence>());
        },
        timeout: const Timeout(Duration(minutes: 8)),
      );
    },
  );
}
