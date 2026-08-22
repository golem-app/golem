import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/download_pace.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/features/models/artifact_transfer.dart';
import 'package:golem_flutter/features/models/widgets/transfer_card.dart';
import 'package:golem_flutter/l10n/generated/app_localizations.dart';

import 'support/harness.dart';

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
  Future<void> pump(
    WidgetTester tester, {
    required TransferDensity density,
    ArtifactPhase phase = ArtifactPhase.downloading,
    int verifiedBytes = 0,
    int downloadedBytes = 1000000000,
    DownloadPaceSnapshot? pace,
    bool simulated = false,
    bool showBytes = true,
  }) async {
    setViewport(tester);
    await tester.pumpWidget(
      wrapApp(
        child: Builder(
          builder: (context) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TransferCard(
                transfer: artifactTransfer(
                  entry: _entry,
                  status: ArtifactStatus(
                    phase: phase,
                    downloadedBytes: downloadedBytes,
                    verifiedBytes: verifiedBytes,
                  ),
                  localizations: AppLocalizations.of(context),
                  pace: pace,
                  simulated: simulated,
                ),
                density: density,
                semanticsLabel: 'Download progress',
                caption: 'Download',
                showBytes: showBytes,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the sign and the unit hold still while digits come and go', (
    tester,
  ) async {
    // "9%"→"10%" and "9.8 MB/s"→"10.2 MB/s" used to nudge the "%" and the
    // pill by a digit; each figure reserves its widest value instead.
    final percentEdges = <double>[];
    final pillWidths = <double>[];
    for (final (bytes, rate, label) in [
      (360000000, 9.8, '9%'),
      (400000000, 10.2, '10%'),
      (4000000000, 999.9, '100%'),
    ]) {
      await pump(
        tester,
        density: TransferDensity.prominent,
        downloadedBytes: bytes,
        pace: DownloadPaceSnapshot(
          artifactKey: 'test-gguf',
          mbPerSecond: rate,
          eta: const Duration(seconds: 100),
        ),
      );
      percentEdges.add(tester.getRect(find.text(label)).right);
      final chip = find.text('${rate.toStringAsFixed(1)} MB/s');
      pillWidths.add(
        tester
            .getSize(
              find.ancestor(of: chip, matching: find.byType(Container)).first,
            )
            .width,
      );
    }
    expect(percentEdges.toSet(), hasLength(1), reason: '$percentEdges');
    expect(pillWidths.toSet(), hasLength(1), reason: '$pillWidths');
  });

  testWidgets('both densities render the same projection', (tester) async {
    for (final density in TransferDensity.values) {
      await pump(
        tester,
        density: density,
        pace: const DownloadPaceSnapshot(
          artifactKey: 'test-gguf',
          mbPerSecond: 44,
          eta: Duration(seconds: 100),
        ),
      );
      expect(find.text('25%'), findsOneWidget, reason: '$density');
      expect(find.text('44.0 MB/s'), findsOneWidget, reason: '$density');
      expect(
        find.text('1.00 GB of 4.00 GB'),
        findsOneWidget,
        reason: '$density',
      );
      expect(
        find.text('About 2 minutes left'),
        findsOneWidget,
        reason: '$density',
      );
    }
  });

  testWidgets('the prominent density leads with the percentage', (
    tester,
  ) async {
    await pump(
      tester,
      density: TransferDensity.prominent,
      pace: const DownloadPaceSnapshot(
        artifactKey: 'test-gguf',
        mbPerSecond: 44,
        eta: Duration(seconds: 100),
      ),
    );
    // The percentage is the headline, so the caption is not painted and the
    // number is not repeated at the end of the line.
    expect(find.text('Download'), findsNothing);
    expect(find.text('25%'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('25%')).style!.fontSize,
      GolemText.hero.fontSize,
    );
    final percent = tester.getRect(find.text('25%'));
    final chip = tester.getRect(find.text('44.0 MB/s'));
    expect(percent.left, lessThan(chip.left));
    expect(percent.center.dy, closeTo(chip.center.dy, 1));
  });

  testWidgets('the dense density captions the bar', (tester) async {
    await pump(
      tester,
      density: TransferDensity.dense,
      pace: const DownloadPaceSnapshot(
        artifactKey: 'test-gguf',
        mbPerSecond: 44,
        eta: Duration(seconds: 100),
      ),
    );
    final caption = tester.getRect(find.text('Download'));
    final chip = tester.getRect(find.text('44.0 MB/s'));
    final percent = tester.getRect(find.text('25%'));
    expect(caption.center.dy, closeTo(chip.center.dy, 1));
    expect(caption.center.dy, closeTo(percent.center.dy, 1));
    expect(chip.left, greaterThan(caption.right));
    expect(percent.left, greaterThanOrEqualTo(chip.right));
  });

  testWidgets('a surface that already quotes the bytes is not repeated to', (
    tester,
  ) async {
    await pump(
      tester,
      density: TransferDensity.dense,
      showBytes: false,
      pace: const DownloadPaceSnapshot(
        artifactKey: 'test-gguf',
        mbPerSecond: 44,
        eta: Duration(seconds: 100),
      ),
    );
    expect(find.text('1.00 GB of 4.00 GB'), findsNothing);
    // The time left keeps its own line, right-aligned, as it always was.
    final remainder = tester.getRect(find.text('About 2 minutes left'));
    final track = tester.getRect(find.byType(TransferCard));
    expect(remainder.right, closeTo(track.right, 1));
  });

  testWidgets('a stopped transfer says so quietly, a live one in accent', (
    tester,
  ) async {
    await pump(
      tester,
      density: TransferDensity.dense,
      phase: ArtifactPhase.paused,
    );
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('3.00 GB left'), findsOneWidget);
  });

  testWidgets('a verification paints the hashed fraction', (tester) async {
    await pump(
      tester,
      density: TransferDensity.dense,
      phase: ArtifactPhase.verifying,
      verifiedBytes: 3000000000,
    );
    expect(
      tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor,
      0.75,
    );
    expect(find.text('Verifying'), findsOneWidget);
  });
}
