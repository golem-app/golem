import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';

import 'support/harness.dart';

void main() {
  testWidgets('picking a model persists it and relabels chip and nav', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      child: const ChatScreen(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    // The default effective model labels the chip and the honest subtitle.
    expect(find.text('Gemma 4 E2B'), findsOneWidget);
    expect(find.text('Gemma 4 E2B · simulated'), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-picker-sheet')), findsOneWidget);
    expect(find.byKey(const Key('model-picker-manage')), findsOneWidget);

    await tester.tap(find.byKey(const Key('model-picker-qwen35-gguf')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-picker-sheet')), findsNothing);
    final active = container.read(chatControllerProvider).requireValue.active!;
    expect(active.modelKey, 'qwen35-gguf');
    expect(find.text('Qwen 3.5 4B QAT'), findsOneWidget);
    expect(find.text('Qwen 3.5 4B QAT · simulated'), findsOneWidget);
  });

  testWidgets('picking a model on a fresh session materializes the chat', (
    tester,
  ) async {
    await pumpWithRepositories(tester, child: const ChatScreen());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container.read(chatControllerProvider).requireValue.conversations,
      isEmpty,
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-picker-gemma4-gguf')));
    await tester.pumpAndSettle();
    final state = container.read(chatControllerProvider).requireValue;
    expect(state.conversations, hasLength(1));
    expect(state.active!.modelKey, 'gemma4-gguf');
  });

  testWidgets('the attach sheet is inert and its rows dismiss', (tester) async {
    await pumpWithRepositories(tester, child: const ChatScreen());
    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attach-sheet')), findsOneWidget);
    expect(
      find.textContaining('Attachments are read on device'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('attach-photo-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attach-sheet')), findsNothing);
  });
}
