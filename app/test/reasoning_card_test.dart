import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/widgets/message_bubble.dart';

import 'support/harness.dart';
import 'support/in_memory_preferences_repository.dart';

const _thoughts =
    'First thought.\nSecond thought.\nThird thought.\nFourth thought.\n'
    'Fifth thought.';

ChatMessage _message({required bool streaming}) => ChatMessage.text(
  id: 'assistant-1',
  role: MessageRole.assistant,
  text: streaming ? '' : 'The answer.',
  createdAt: DateTime.utc(2026, 8, 22),
  reasoning: _thoughts,
  isStreaming: streaming,
);

Widget _bubble(ChatMessage message) => Column(
  children: [
    MessageBubble(
      message: message,
      canRegenerate: false,
      idle: !message.isStreaming,
    ),
  ],
);

/// A streaming bubble pulses its dot forever, so these pumps never settle.
Future<void> _pump(
  WidgetTester tester,
  ChatMessage message, {
  double textScale = 1,
  AppPreferences preferences = const AppPreferences(),
}) async {
  await pumpWithRepositories(
    tester,
    textScale: textScale,
    preferences: InMemoryPreferencesRepository(preferences),
    settle: false,
    child: _bubble(message),
  );
  await tester.pump();
}

void main() {
  final header = find.byKey(const Key('reasoning-card-header'));
  final peek = find.byKey(const Key('reasoning-peek'));
  final thoughts = find.text(_thoughts);

  testWidgets('a live card arrives collapsed, with a three-line peek', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _message(streaming: true));

    expect(tester.getSemantics(header).value, 'Collapsed');
    expect(peek, findsOneWidget);
    expect(find.descendant(of: peek, matching: thoughts), findsOneWidget);
    // Three footnote lines (15pt × 1.4), and not a pixel of a fourth.
    expect(tester.getSize(peek).height, 63);
    // The peek is decoration: nothing in it reads out, on any token.
    expect(find.bySemanticsLabel(RegExp('First thought')), findsNothing);
    semantics.dispose();
  });

  testWidgets('the peek scales with the text', (tester) async {
    await _pump(tester, _message(streaming: true), textScale: 1.3);
    expect(tester.getSize(peek).height, closeTo(63 * 1.3, 0.01));
  });

  testWidgets('a tap expands a live card and the peek goes', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _message(streaming: true));
    await tester.tap(header);
    await tester.pump();

    expect(tester.getSemantics(header).value, 'Expanded');
    expect(peek, findsNothing);
    expect(thoughts, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a settled card has neither peek nor thoughts', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _message(streaming: false));
    expect(tester.getSemantics(header).value, 'Collapsed');
    expect(peek, findsNothing);
    expect(thoughts, findsNothing);
    semantics.dispose();
  });

  testWidgets('a card left alone while live settles collapsed', (tester) async {
    // One tree, re-pumped: the latch this guards against lived in State.
    Widget wrap(ChatMessage message) =>
        ProviderScope(child: wrapApp(child: _bubble(message)));
    await tester.pumpWidget(wrap(_message(streaming: true)));
    expect(peek, findsOneWidget);
    await tester.pumpWidget(wrap(_message(streaming: false)));
    expect(peek, findsNothing);
    expect(thoughts, findsNothing);
  });

  testWidgets('the preference opens a live card instead of peeking', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      _message(streaming: true),
      preferences: const AppPreferences(expandReasoning: true),
    );
    expect(tester.getSemantics(header).value, 'Expanded');
    expect(peek, findsNothing);
    expect(thoughts, findsOneWidget);
    semantics.dispose();
  });
}
