import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/settings/appearance_screen.dart';
import 'package:golem_flutter/features/settings/models_screen.dart';

import 'support/harness.dart';

/// What a screen reader is told. None of it is visible on screen, so no
/// golden and no other suite here would notice it regressing.
void main() {
  List<String> announcements(WidgetTester tester) =>
      tester.takeAnnouncements().map((event) => event.message).toList();

  /// How many nodes in the whole tree carry [label] — the duplicate-reading
  /// count, which a single `getSemantics` assertion cannot see.
  int nodesLabelled(WidgetTester tester, String label) {
    var count = 0;
    void visit(SemanticsNode node) {
      if (node.label.contains(label)) count++;
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(tester.getSemantics(find.byType(CupertinoApp)));
    return count;
  }

  testWidgets('a toast says itself out loud', (tester) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      child: const ChatScreen(),
    );
    announcements(tester);

    await tester.tap(find.byKey(const Key('message-copy-assistant-md')));
    await tester.pump();

    expect(announcements(tester), contains('Copied to clipboard'));
    // The toast dismisses itself; drain its timer before moving on.
    await tester.pump(const Duration(milliseconds: 1600));
  });

  testWidgets('a turn announces where it starts and ends', (tester) async {
    await pumpWithRepositories(tester, child: const ChatScreen());
    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'Say something',
    );
    await tester.pump();
    announcements(tester);

    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();
    expect(announcements(tester), contains('Golem is responding'));

    await tester.pumpAndSettle();
    expect(announcements(tester), contains('Response finished'));
  });

  testWidgets(
    'the composer reads as read-only, never disabled, while generating',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWithRepositories(tester, child: const ChatScreen());
      final composer = find.byKey(const Key('chat-composer'));
      expect(
        tester.getSemantics(composer),
        isSemantics(isTextField: true, isEnabled: true, isReadOnly: false),
      );

      await tester.enterText(composer, 'Say something');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pump();

      expect(find.byKey(const Key('stop-button')), findsOneWidget);
      expect(
        tester.getSemantics(composer),
        isSemantics(isTextField: true, isEnabled: true, isReadOnly: true),
      );
      // A disabled field dropped focus by itself; a read-only one has to be
      // told, or the keyboard sits over the answer as it streams.
      expect(
        tester.widget<CupertinoTextField>(composer).focusNode?.hasFocus,
        isFalse,
      );

      await tester.pumpAndSettle();
      handle.dispose();
    },
  );

  testWidgets('a settings switch is one control, named once', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWithRepositories(tester, child: const AppearanceScreen());

    expect(
      tester.getSemantics(find.byKey(const Key('toggle-metrics'))),
      isSemantics(
        label: 'Show inference metrics',
        hasToggledState: true,
        isToggled: true,
        isEnabled: true,
      ),
    );
    // The row's text used to reach the card's node as well, so the label was
    // read once as prose and again as the switch.
    expect(nodesLabelled(tester, 'Show inference metrics'), 1);
    handle.dispose();
  });

  testWidgets('the text-size slider says what it is and where it sits', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpWithRepositories(tester, child: const AppearanceScreen());

    // Bare, a CupertinoSlider announces only its position along its own
    // track ("33%"), with no name and nothing tying it to text size.
    expect(
      tester.getSemantics(find.byKey(const Key('text-size-control'))),
      isSemantics(
        label: 'Text size',
        value: '100 percent',
        isSlider: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    // The sample bubble and the two size glyphs are dial face, not content.
    expect(nodesLabelled(tester, 'Looks about right.'), 0);
    handle.dispose();
  });

  testWidgets('a reasoning card is a button that reports its state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpWithRepositories(
      tester,
      history: seedHistory(),
      child: const ChatScreen(),
    );

    final header = find.byKey(const Key('reasoning-card-header'));
    expect(
      tester.getSemantics(header),
      isSemantics(label: 'Reasoning', value: 'Collapsed', isButton: true),
    );

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(header), isSemantics(value: 'Expanded'));
    handle.dispose();
  });

  testWidgets('a message is read once, with its speaker', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWithRepositories(
      tester,
      history: seedHistory(),
      child: const ChatScreen(),
    );

    // The bubble's wrapper used to restate the message it wrapped, so every
    // answer was spoken twice over.
    const answer =
        'Start slowly: coffee, a long walk, and an afternoon with a good book.';
    expect(nodesLabelled(tester, answer), 1);
    expect(
      nodesLabelled(tester, 'Suggest a calm weekend plan close to home.'),
      1,
    );
    // Who said it still leads the node that carries the words.
    expect(nodesLabelled(tester, 'Golem:'), 1);
    expect(nodesLabelled(tester, 'You:'), 1);

    // A code card is its own node, so the answer around it splits into
    // several. The speaker still belongs to exactly one of them.
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      child: const ChatScreen(),
    );
    expect(nodesLabelled(tester, 'Golem:'), 1);
    expect(nodesLabelled(tester, 'Use the built-in'), 1);
    handle.dispose();
  });

  testWidgets('a download reports its progress as one reading', (tester) async {
    final handle = tester.ensureSemantics();
    final entry = modelCatalog.firstWhere((item) => item.key == 'gemma4-gguf');
    final downloaded = entry.totalBytes ~/ 4;
    await pumpWithRepositories(
      tester,
      model: ModelState(
        artifacts: {
          'gemma4-gguf': ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: downloaded,
          ),
        },
      ),
      child: const ModelsScreen(),
    );

    final progress = find.byKey(const Key('model-progress-gemma4-gguf'));
    await tester.scrollUntilVisible(progress, 200);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(progress),
      isSemantics(label: 'Download', value: '25 percent'),
    );
    handle.dispose();
  });
}
