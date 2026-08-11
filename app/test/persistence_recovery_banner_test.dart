import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/chat/widgets/persistence_recovery_banner.dart';
import 'package:golem_flutter/features/chat/widgets/recovery_banner.dart';

import 'support/harness.dart';
import 'support/scripted_chat_history_repository.dart';

class _PersistenceHost extends ConsumerWidget {
  const _PersistenceHost({this.withInferenceFailure = false});

  final bool withInferenceFailure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persistence = ref.watch(
      chatControllerProvider.select(
        (value) => value.value?.persistencePhase ?? ChatPersistencePhase.idle,
      ),
    );
    return CupertinoPageScaffold(
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (persistence != ChatPersistencePhase.idle)
              PersistenceRecoveryBanner(phase: persistence),
            if (withInferenceFailure)
              const RecoveryBanner(
                failure: ChatFailure(
                  kind: ChatFailureKind.generic,
                  message: 'Generation failed independently.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<({ProviderContainer container, ScriptedChatHistoryRepository history})>
failedPersistence(WidgetTester tester) async {
  final history = ScriptedChatHistoryRepository();
  final container = buildContainer(chatHistory: history);
  addTearDown(container.dispose);
  await container.read(chatControllerProvider.future);
  final save = container.read(chatControllerProvider.notifier).newChat();
  history.saves.single.fail();
  await save;
  return (container: container, history: history);
}

void main() {
  testWidgets('retry exposes progress and clears only after success', (
    tester,
  ) async {
    setViewport(tester);
    final setup = await failedPersistence(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: setup.container,
        child: wrapApp(child: const _PersistenceHost()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('chat-persistence-banner')), findsOneWidget);
    expect(
      find.text(
        'Chat history isn’t saving. Your latest changes could be lost when '
        'you close the app.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('retry-chat-persistence')))
          .label,
      contains('Try again'),
    );

    await tester.tap(find.byKey(const Key('retry-chat-persistence')));
    await tester.pump();
    expect(setup.history.saves, hasLength(2));
    expect(find.text('Saving…'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const Key('retry-chat-persistence')),
          )
          .onPressed,
      isNull,
    );

    setup.history.saves[1].succeed();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-persistence-banner')), findsNothing);
    semantics.dispose();
  }, variant: bothChromes);

  testWidgets('persistence and inference recovery coexist', (tester) async {
    setViewport(tester);
    final setup = await failedPersistence(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: setup.container,
        child: wrapApp(
          child: const _PersistenceHost(withInferenceFailure: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('chat-persistence-banner')), findsOneWidget);
    expect(find.byKey(const Key('recovery-banner')), findsOneWidget);
    expect(find.byKey(const Key('retry-chat-persistence')), findsOneWidget);
    expect(find.byKey(const Key('retry-generation')), findsOneWidget);
    expect(find.byKey(const Key('discard-generation')), findsOneWidget);
  });

  testWidgets('target size, large text, and RTL remain accessible', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final setup = await failedPersistence(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: setup.container,
        child: CupertinoApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: const _PersistenceHost(),
        ),
      ),
    );
    await tester.pump();

    final size = tester.getSize(
      find.byKey(const Key('retry-chat-persistence')),
    );
    final minimum = defaultTargetPlatform == TargetPlatform.android ? 48 : 44;
    expect(size.width, greaterThanOrEqualTo(minimum));
    expect(size.height, greaterThanOrEqualTo(minimum));
    expect(tester.takeException(), isNull);
  }, variant: bothChromes);
}
