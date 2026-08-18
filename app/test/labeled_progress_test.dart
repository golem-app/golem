import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/widgets/labeled_progress.dart';

import 'support/harness.dart';

void main() {
  Future<void> pump(WidgetTester tester, LabeledProgress bar) =>
      tester.pumpWidget(
        wrapApp(
          child: Center(child: SizedBox(width: 300, child: bar)),
        ),
      );

  testWidgets('a transfer reads as one node, caption plus percentage', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const LabeledProgress(
        key: Key('bar'),
        semanticsLabel: 'Download',
        caption: 'Download',
        fraction: 0.25,
        percent: 25,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('bar'))),
      isSemantics(label: 'Download', value: '25 percent'),
    );
    handle.dispose();
  });

  testWidgets('the painted pieces announce nothing of their own', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const LabeledProgress(
        key: Key('bar'),
        semanticsLabel: 'Download',
        caption: 'Download · simulated',
        fraction: 0.4,
        percent: 40,
        detail: 'About 2 minutes left',
      ),
    );
    // Every string is painted…
    expect(find.text('Download · simulated'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('About 2 minutes left'), findsOneWidget);
    // …and neither the caption nor the number reaches the reading. Without
    // the excluded subtree they are absorbed into the node's own label, which
    // announces "Download / Download · simulated / 40%" as one run-on string.
    expect(
      tester.getSemantics(find.byKey(const Key('bar'))),
      isSemantics(label: 'Download', value: '40 percent'),
    );
    handle.dispose();
  });

  testWidgets('a bar under its own copy paints no caption and no percent', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const LabeledProgress(
        key: Key('bar'),
        semanticsLabel: 'Download',
        fraction: 0.6,
        percent: 60,
        showPercent: false,
      ),
    );
    expect(find.text('60%'), findsNothing);
    // The reading survives the missing caption: the setup banner's headline
    // says what is happening, and the bar is the only thing carrying how far.
    expect(
      tester.getSemantics(find.byKey(const Key('bar'))),
      isSemantics(label: 'Download', value: '60 percent'),
    );
    handle.dispose();
  });

  testWidgets('a card that is the whole screen reads its figures out', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const LabeledProgress(
        semanticsLabel: 'Download progress',
        fraction: 0.25,
        percent: 25,
        caption: '25%',
        showPercent: false,
        detailLeading: '1.00 GB of 4.00 GB',
        detail: 'About 2 minutes left',
        announceDetail: true,
      ),
    );
    // First run has always announced these: the size and the time left are the
    // only place a user there can learn them, and a bar that swallowed them
    // would leave "25 percent" as the entire reading of the screen.
    for (final figure in const ['1.00 GB of 4.00 GB', 'About 2 minutes left']) {
      expect(
        tester.getSemantics(find.text(figure)).label,
        figure,
        reason: figure,
      );
    }
    handle.dispose();
  });

  testWidgets('a phase with no percentage announces none', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const LabeledProgress(
        key: Key('bar'),
        semanticsLabel: 'Verifying files',
        fraction: 1,
        percent: 100,
        caption: 'Verifying files',
        showPercent: false,
        announcePercent: false,
      ),
    );
    // A verification is not 40% verified, painted or read out.
    expect(
      tester.getSemantics(find.byKey(const Key('bar'))),
      isSemantics(label: 'Verifying files', value: ''),
    );
    handle.dispose();
  });

  testWidgets('the trailing chip rides the caption line', (tester) async {
    await pump(
      tester,
      const LabeledProgress(
        semanticsLabel: 'Download',
        caption: 'Download',
        fraction: 0.5,
        percent: 50,
        trailing: Text('44.0 MB/s'),
      ),
    );
    final caption = tester.getRect(find.text('Download'));
    final chip = tester.getRect(find.text('44.0 MB/s'));
    final percent = tester.getRect(find.text('50%'));
    expect(chip.center.dy, closeTo(caption.center.dy, 1));
    expect(chip.left, greaterThan(caption.left));
    expect(percent.left, greaterThanOrEqualTo(chip.right));
  });
}
