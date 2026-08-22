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

  testWidgets(
    'a running download shows one line of advice, nothing to wave away',
    (tester) async {
      await pumpWithRepositories(
        tester,
        model: state(ArtifactPhase.downloading),
        child: Column(children: [DownloadNoteBanner(entry: entry)]),
      );
      expect(
        find.text('Keep Golem open — downloads are fastest in the foreground.'),
        findsOneWidget,
      );
      // Advice, not a warning: no figures to read, no control to dismiss.
      expect(find.textContaining('MB/s'), findsNothing);
      expect(find.byType(CupertinoButton), findsNothing);
      expect(find.byKey(const Key('download-note-dismiss')), findsNothing);
    },
  );

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
      expect(find.textContaining('Keep Golem open'), findsNothing);
      expect(tester.getSize(find.byType(DownloadNoteBanner)), Size.zero);
    });
  }

  testWidgets('the margin applies only while visible', (tester) async {
    await pumpWithRepositories(
      tester,
      model: state(ArtifactPhase.paused),
      child: Column(
        children: [
          DownloadNoteBanner(
            entry: entry,
            margin: const EdgeInsetsDirectional.only(top: 14),
          ),
        ],
      ),
    );
    expect(tester.getSize(find.byType(DownloadNoteBanner)), Size.zero);
  });
}
