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
    // …and none of them reaches the reading. Without the excluded subtree the
    // caption, the number and the time left are absorbed into the node's own
    // label, which then announces "Download / Download · simulated / 40% /
    // About 2 minutes left" as one run-on string.
    expect(
      tester.getSemantics(find.byType(LabeledProgress)),
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
