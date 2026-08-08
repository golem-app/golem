import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
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
    // The default effective model labels the chip and the honest
    // subtitle (nav bar and drawer header both carry the subtitle).
    expect(find.text('Gemma 4 E2B'), findsOneWidget);
    expect(find.text('Gemma 4 E2B · simulated'), findsAtLeastNWidgets(1));

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
    expect(find.text('Qwen 3.5 4B QAT · simulated'), findsAtLeastNWidgets(1));
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

  testWidgets('a real backend keeps other model rows disabled', (tester) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.mlx,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-mlx',
        modelPath: '/models/gemma',
        modelPathFromCatalog: true,
      ),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    // Only the running artifact stays tappable until #20; the footnote
    // explains the constraint honestly.
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const Key('model-picker-gemma4-mlx')),
          )
          .onPressed,
      isNotNull,
    );
    // Same-engine alternatives render but stay disabled…
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const Key('model-picker-qwen35-mlx')),
          )
          .onPressed,
      isNull,
    );
    // …while artifacts this build's engine can never load are hidden
    // outright (#63): no dead multi-gigabyte options.
    expect(find.byKey(const Key('model-picker-qwen35-gguf')), findsNothing);
    expect(find.byKey(const Key('model-picker-gemma4-gguf')), findsNothing);
    expect(find.textContaining('Golem is running Gemma 4 E2B'), findsOneWidget);
  });

  testWidgets('starter chips prefill and focus the composer', (tester) async {
    await pumpWithRepositories(tester, child: const ChatScreen());
    await tester.tap(find.byKey(const Key('starter-chip-rewrite')));
    await tester.pump();
    final field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('chat-composer')),
    );
    expect(field.controller!.text, 'Rewrite this so it reads clearly: ');
    expect(field.focusNode!.hasFocus, isTrue);
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
