import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/models/widgets/download_note_banner.dart';

import 'support/harness.dart';

void main() {
  final entry = modelCatalog.firstWhere((entry) => entry.key == 'gemma4-mlx');

  ModelState state(ArtifactPhase phase) => ModelState(
    simulated: true,
    artifacts: {
      entry.key: ArtifactStatus(phase: phase, downloadedBytes: 900000000),
    },
  );

  testWidgets('shows only while downloading and dismisses on tap', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      model: state(ArtifactPhase.downloading),
      child: Column(children: [DownloadNoteBanner(entry: entry)]),
    );
    expect(find.text('Keep Golem open for full speed.'), findsOneWidget);
    expect(find.textContaining('slows background downloads'), findsOneWidget);

    await tester.tap(find.byKey(const Key('download-note-dismiss')));
    await tester.pump();
    expect(find.text('Keep Golem open for full speed.'), findsNothing);
  });

  for (final phase in [
    ArtifactPhase.notDownloaded,
    ArtifactPhase.paused,
    ArtifactPhase.verifying,
    ArtifactPhase.failed,
    ArtifactPhase.installed,
  ]) {
    testWidgets('renders nothing while ${phase.name}', (tester) async {
      await pumpWithRepositories(
        tester,
        model: state(phase),
        child: Column(children: [DownloadNoteBanner(entry: entry)]),
      );
      expect(find.text('Keep Golem open for full speed.'), findsNothing);
    });
  }

  testWidgets('the note stands down when leaving would cost no extra time', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      model: ModelState(
        simulated: true,
        artifacts: {
          entry.key: ArtifactStatus(
            phase: ArtifactPhase.downloading,
            // ~50 MB left: background and foreground both round to "about
            // 1 minute", so the comparison would contradict itself.
            downloadedBytes: entry.totalBytes - 50000000,
          ),
        },
      ),
      child: Column(children: [DownloadNoteBanner(entry: entry)]),
    );
    expect(find.text('Keep Golem open for full speed.'), findsNothing);
  });

  testWidgets('one dismissal hides every surface sharing the state', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      model: state(ArtifactPhase.downloading),
      child: Column(
        children: [
          DownloadNoteBanner(entry: entry, key: const Key('surface-a')),
          DownloadNoteBanner(
            entry: entry,
            compact: true,
            key: const Key('surface-b'),
          ),
        ],
      ),
    );
    expect(find.text('Keep Golem open for full speed.'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('download-note-dismiss')).first);
    await tester.pump();
    expect(find.text('Keep Golem open for full speed.'), findsNothing);
  });

  testWidgets('dismiss control is an accessible labeled button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpWithRepositories(
      tester,
      model: state(ArtifactPhase.downloading),
      child: Column(children: [DownloadNoteBanner(entry: entry)]),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('download-note-dismiss'))),
      matchesSemantics(
        label: 'Dismiss',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('Arabic keeps the MB/s figure intact under RTL', (tester) async {
    await pumpWithRepositories(
      tester,
      locale: const Locale('ar'),
      model: state(ArtifactPhase.downloading),
      child: Column(children: [DownloadNoteBanner(entry: entry)]),
    );
    final body = tester
        .widgetList<Text>(find.textContaining('MB/s'))
        .single
        .data!;
    // Widget tests run as TargetPlatform.android, so the Android pacing shows.
    expect(body, contains('\u20661.2 MB/s\u2069'));
    expect(tester.takeException(), isNull);
  });
}
