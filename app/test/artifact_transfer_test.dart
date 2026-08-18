import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/download_pace.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/models/artifact_transfer.dart';
import 'package:golem_flutter/l10n/bidi.dart';
import 'package:golem_flutter/l10n/generated/app_localizations_en.dart';

/// A four-gigabyte artifact in round numbers, so a quarter is exactly 25%.
const _entry = ModelCatalogEntry(
  key: 'test-gguf',
  displayName: 'Test',
  engine: ModelEngine.gguf,
  quantization: 'Q4_0',
  repository: 'example/test',
  revision: '0123456789abcdef',
  profileKey: 'gemma4',
  files: [
    ModelArtifactFile(path: 'model.gguf', bytes: 4000000000, sha256: 'aa'),
  ],
);

void main() {
  ArtifactTransferPresentation project(
    ArtifactStatus status, {
    DownloadPaceSnapshot? pace,
    bool simulated = false,
    String? deviceRefusal,
    bool sideloaded = false,
    bool admitted = true,
    bool downloadable = true,
    bool loadsHere = true,
    String? transferringKey,
  }) => artifactTransfer(
    entry: _entry,
    status: status,
    localizations: AppLocalizationsEn(),
    pace: pace,
    simulated: simulated,
    deviceRefusal: deviceRefusal,
    sideloaded: sideloaded,
    admitted: admitted,
    downloadable: downloadable,
    loadsHere: loadsHere,
    transferringKey: transferringKey,
  );

  group('the numbers', () {
    test('the fraction comes from the catalog total, never from the store', () {
      final transfer = project(
        const ArtifactStatus(
          phase: ArtifactPhase.downloading,
          downloadedBytes: 1000000000,
        ),
      );
      expect(transfer.fraction, closeTo(0.25, 0.0001));
      expect(transfer.percent, 25);
      expect(transfer.transferred, '1.00 GB');
      expect(transfer.total, '4.00 GB');
      expect(transfer.remaining, '3.00 GB');
    });

    test(
      'a byte count past the total is clamped rather than shown as 104%',
      () {
        final transfer = project(
          const ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: 4200000000,
          ),
        );
        expect(transfer.fraction, 1.0);
        expect(transfer.percent, 100);
      },
    );

    test('a verification is complete, not partway', () {
      // `real_model_management_repository` publishes `verifying` with the
      // bytes verified *so far*, one file at a time. Reading a fraction off
      // that would walk a finished download's bar backwards.
      final transfer = project(
        const ArtifactStatus(
          phase: ArtifactPhase.verifying,
          downloadedBytes: 400000000,
        ),
      );
      expect(transfer.fraction, 1.0);
      expect(transfer.percent, 100);
    });

    test('a sizeless entry reads zero instead of dividing by it', () {
      final transfer = artifactTransfer(
        entry: const ModelCatalogEntry(
          key: 'empty',
          displayName: 'Empty',
          engine: ModelEngine.gguf,
          quantization: 'Q4_0',
          repository: 'example/empty',
          revision: 'abc',
          profileKey: 'gemma4',
          files: [],
        ),
        status: const ArtifactStatus(phase: ArtifactPhase.downloading),
        localizations: AppLocalizationsEn(),
      );
      expect(transfer.fraction, 0);
      expect(transfer.percent, 0);
    });
  });

  group('the chip', () {
    test('a warming pace window shows nothing rather than a guess', () {
      final transfer = project(
        const ArtifactStatus(phase: ArtifactPhase.downloading),
      );
      expect(transfer.chip, isNull);
      expect(transfer.chipIsLive, isTrue);
    });

    test('a live rate is quoted to one decimal', () {
      final transfer = project(
        const ArtifactStatus(
          phase: ArtifactPhase.downloading,
          downloadedBytes: 1000000000,
        ),
        pace: const DownloadPaceSnapshot(
          artifactKey: 'test-gguf',
          mbPerSecond: 43.96,
          eta: Duration(seconds: 68),
        ),
      );
      expect(transfer.chip, '44.0 MB/s');
      expect(transfer.remainder, 'About 2 minutes left');
    });

    // The English fallback this file used to carry was flat, so the last
    // minute of every download read "About 1 minutes left". The ARB has always
    // held the plural; taking localizations non-null is what reaches it (#130).
    test('the last minute is singular', () {
      final transfer = project(
        const ArtifactStatus(
          phase: ArtifactPhase.downloading,
          downloadedBytes: 3900000000,
        ),
        pace: const DownloadPaceSnapshot(
          artifactKey: 'test-gguf',
          mbPerSecond: 43.96,
          eta: Duration(seconds: 20),
        ),
      );
      expect(transfer.remainder, 'About 1 minute left');
    });

    test('a snapshot for another artifact is not borrowed', () {
      final transfer = project(
        const ArtifactStatus(phase: ArtifactPhase.downloading),
        pace: const DownloadPaceSnapshot(
          artifactKey: 'someone-else',
          mbPerSecond: 44,
          eta: Duration(seconds: 30),
        ),
      );
      expect(transfer.chip, isNull);
      expect(transfer.remainder, isNull);
    });

    test('a stopped transfer names its phase and where it stopped', () {
      final paused = project(
        const ArtifactStatus(
          phase: ArtifactPhase.paused,
          downloadedBytes: 1000000000,
        ),
      );
      expect(paused.chip, 'Paused');
      expect(paused.chipIsLive, isFalse);
      expect(paused.remainder, '3.00 GB left');

      final failed = project(
        const ArtifactStatus(
          phase: ArtifactPhase.failed,
          downloadedBytes: 1000000000,
        ),
      );
      expect(failed.chip, 'Stopped');
      expect(failed.remainder, 'Stopped at 25%');
    });

    test('verification and completion carry neither chip nor remainder', () {
      for (final phase in [ArtifactPhase.verifying, ArtifactPhase.installed]) {
        final transfer = project(ArtifactStatus(phase: phase));
        expect(transfer.chip, isNull, reason: '$phase');
        expect(transfer.remainder, isNull, reason: '$phase');
      }
    });
  });

  group('the affordance', () {
    test('installed offers nothing at all', () {
      expect(
        project(
          const ArtifactStatus(phase: ArtifactPhase.installed),
        ).affordance,
        isNull,
      );
    });

    test('a download can be paused and a verification cannot', () {
      expect(
        project(
          const ArtifactStatus(phase: ArtifactPhase.downloading),
        ).affordance,
        isA<TransferInFlight>().having((it) => it.pausable, 'pausable', isTrue),
      );
      expect(
        project(
          const ArtifactStatus(phase: ArtifactPhase.verifying),
        ).affordance,
        isA<TransferInFlight>().having(
          (it) => it.pausable,
          'pausable',
          isFalse,
        ),
      );
    });

    test('the action follows the phase', () {
      expect(
        (project(const ArtifactStatus()).affordance! as TransferOffer).action,
        TransferAction.start,
      );
      expect(
        (project(const ArtifactStatus(phase: ArtifactPhase.paused)).affordance!
                as TransferOffer)
            .action,
        TransferAction.resume,
      );
      expect(
        (project(const ArtifactStatus(phase: ArtifactPhase.failed)).affordance!
                as TransferOffer)
            .action,
        TransferAction.retry,
      );
    });

    test('a first download owes no explanation', () {
      final offer =
          project(const ArtifactStatus()).affordance! as TransferOffer;
      expect(offer.enabled, isTrue);
      expect(offer.note, isNull);
    });

    test('a resume says how far it got, with the simulation qualifier', () {
      final offer =
          project(
                const ArtifactStatus(
                  phase: ArtifactPhase.paused,
                  downloadedBytes: 1000000000,
                ),
                simulated: true,
              ).affordance!
              as TransferOffer;
      expect(offer.note, 'Paused at 1.00 GB of 4.00 GB · simulated.');
    });

    // The kind and its redacted arguments, never the diagnostic string beside
    // them: that one quotes platform text and can name a path (#130).
    test('a failure words its kind, not the phase', () {
      final offer =
          project(
                const ArtifactStatus(
                  phase: ArtifactPhase.failed,
                  failure: '/Users/someone/models/x.gguf is missing.',
                  failureReason: ArtifactFailure(
                    ArtifactFailureKind.insufficientStorage,
                    requiredBytes: 2000000000,
                    availableBytes: 400000000,
                  ),
                ),
              ).affordance!
              as TransferOffer;
      expect(
        offer.note,
        AppLocalizationsEn().downloadInsufficientStorage(
          ltrIsolate('2.00 GB'),
          ltrIsolate('0.40 GB'),
        ),
      );
      expect(offer.note, isNot(contains('/Users/')));
    });

    test('an unclassified failure still offers a retry with a sentence', () {
      final offer =
          project(
                const ArtifactStatus(
                  phase: ArtifactPhase.failed,
                  failureReason: ArtifactFailure(ArtifactFailureKind.transfer),
                ),
              ).affordance!
              as TransferOffer;
      expect(offer.action, TransferAction.retry);
      expect(offer.note, AppLocalizationsEn().downloadFailed);
    });
  });

  group('what blocks an offer', () {
    test('one transfer at a time, and the block says which', () {
      final offer =
          project(
                const ArtifactStatus(),
                transferringKey: 'someone-else',
              ).affordance!
              as TransferOffer;
      expect(offer.block, TransferBlock.busy);
      expect(offer.enabled, isFalse);
      expect(offer.note, 'Another model is downloading.');
    });

    test('the artifact holding the slot is not blocked by itself', () {
      final offer =
          project(
                const ArtifactStatus(),
                transferringKey: 'test-gguf',
              ).affordance!
              as TransferOffer;
      expect(offer.block, isNull);
    });

    test('the device verdict outranks every other reason', () {
      final offer =
          project(
                const ArtifactStatus(),
                deviceRefusal: 'no',
                sideloaded: true,
                downloadable: false,
                transferringKey: 'someone-else',
              ).affordance!
              as TransferOffer;
      expect(offer.block, TransferBlock.deviceRefused);
      expect(offer.note, isNull, reason: 'the surface words this one');
    });

    test('a sideload has nothing to fetch', () {
      final offer =
          project(const ArtifactStatus(), sideloaded: true).affordance!
              as TransferOffer;
      expect(offer.block, TransferBlock.sideload);
      expect(offer.note, isNull, reason: 'the surface words this one');
    });

    test('an unadmitted artifact leaves its sentence to the caller', () {
      final offer =
          project(const ArtifactStatus(), admitted: false).affordance!
              as TransferOffer;
      expect(offer.block, TransferBlock.needsMoreMemory);
      expect(offer.note, isNull);
    });

    test('an unresolved repository cannot be fetched', () {
      final offer =
          project(const ArtifactStatus(), downloadable: false).affordance!
              as TransferOffer;
      expect(offer.block, TransferBlock.unresolvedRepository);
      expect(offer.note, isNull, reason: 'the surface words this one');
    });

    test('only a busy slot carries its own sentence', () {
      // Every other block is worded by the surface — the picker as the row's
      // blockReason, Settings in its own order under its own button — so a
      // second copy here would be copy nobody reads.
      for (final blocked in [
        () => project(const ArtifactStatus(), deviceRefusal: 'no'),
        () => project(const ArtifactStatus(), sideloaded: true),
        () => project(const ArtifactStatus(), admitted: false),
        () => project(const ArtifactStatus(), downloadable: false),
        () => project(const ArtifactStatus(), loadsHere: false),
      ]) {
        final offer = blocked().affordance! as TransferOffer;
        expect(offer.block, isNotNull);
        expect(offer.note, isNull);
      }
    });

    test('an artifact this engine cannot load is blocked', () {
      expect(
        (project(const ArtifactStatus(), loadsHere: false).affordance!
                as TransferOffer)
            .block,
        TransferBlock.otherEngine,
      );
      // A fake *backend* loads every format, but that is the caller's fact
      // to state through `loadsHere`; a simulated *download* says nothing
      // about which weights an engine can map.
      expect(
        (project(
                  const ArtifactStatus(),
                  loadsHere: false,
                  simulated: true,
                ).affordance!
                as TransferOffer)
            .block,
        TransferBlock.otherEngine,
      );
    });

    test('a running transfer is described whatever the verdict', () {
      // Settings has no tier gate, so it can start a download this device is
      // not admitted to; hiding it would blame a transfer nothing shows.
      final transfer = project(
        const ArtifactStatus(phase: ArtifactPhase.downloading),
        admitted: false,
        deviceRefusal: 'no',
      );
      expect(transfer.affordance, isA<TransferInFlight>());
    });
  });
}
