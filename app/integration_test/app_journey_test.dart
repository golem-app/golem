import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/chrome/golem_nav_bar.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/services/image_intake.dart';
import 'package:golem_flutter/features/benchmark/application/benchmark_providers.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/widgets/attach_sheet.dart';
import 'package:integration_test/integration_test.dart';

import 'package:golem_flutter/main.dart' as app;

import '../test/support/image_fixtures.dart';
import 'package:golem_flutter/features/chat/application/chat_providers.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/features/settings/application/preferences_providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('complete fake-only Golem journey', (tester) async {
    await app.launch(picker: const _JourneyPicker());
    // launch() returns before the composition finishes, and the bootstrap
    // splash schedules no frames while it runs — pumpAndSettle alone could
    // settle on the splash. Poll the gate away on a real deadline instead.
    final gateDeadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byKey(const Key('launch-splash')).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(gateDeadline)) {
        fail('The startup gate never completed.');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // A clean QA container owns the complete first-run contract. Returning
    // device runs may already carry the marker, so the journey remains useful
    // without weakening the fresh-install assertions when the screen exists.
    if (find.byKey(const Key('first-run-welcome')).evaluate().isNotEmpty) {
      expect(find.byKey(const Key('first-run-ai-disclaimer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('first-run-get-started')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('first-run-model')), findsOneWidget);
      await tester.tap(find.byKey(const Key('first-run-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('model-download-consent')), findsOneWidget);
      expect(find.textContaining('no network'), findsOneWidget);
      await tester.tap(find.byKey(const Key('model-download-confirm')));
      // Cross the fake repository's first artifact-state update. First run
      // must remain in charge until the user explicitly starts chatting.
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.byKey(const Key('first-run-download-progress')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('first-run-start-chatting')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    if (find.byKey(const Key('empty-chat')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('new-chat-header')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('empty-chat')), findsOneWidget);

    // The integration journey owns the picker response but drives the real
    // sheet, composer tray, attachment store, fake inference, and bubble.
    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-photo-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-attachments')), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();

    final imageContainer = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final imageMessages = imageContainer
        .read(chatControllerProvider)
        .requireValue
        .active!
        .messages;
    final imageTurn = imageMessages.first;
    expect(imageTurn.hasImages, isTrue);
    expect(imageTurn.images.single.mimeType, 'image/png');
    expect(imageMessages.last.text, contains('image you attached'));
    expect(find.byKey(const Key('composer-attachments')), findsNothing);

    await tester.tap(find.byKey(const Key('chat-composer')));
    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'A private simulated hello',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-button')));
    await _pumpUntilFound(tester, find.byKey(const Key('stop-button')));
    expect(find.byKey(const Key('stop-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stop-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reasoning-toggle')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container
          .read(chatControllerProvider)
          .requireValue
          .active!
          .reasoningEnabled,
      isTrue,
    );
    await container
        .read(chatControllerProvider.notifier)
        .send('A complete answer');
    await tester.pump();
    expect(
      container
          .read(chatControllerProvider)
          .requireValue
          .active!
          .messages
          .last
          .reasoning,
      isNotEmpty,
    );

    // Switch this chat's model through the sheet, then send again on it: the
    // daily-use flow #20 exists to prove, driven the way a user drives it.
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-picker-sheet')), findsOneWidget);
    // The simulated catalog is the whole six, so the sheet scrolls (#79) and
    // reaching the last row is part of the flow rather than an aside.
    await tester.ensureVisible(
      find.byKey(const Key('model-picker-qwen35-gguf')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-picker-qwen35-gguf')));
    await tester.pumpAndSettle();
    expect(
      container.read(chatControllerProvider).requireValue.active!.modelKey,
      'qwen35-gguf',
    );
    // Every surface follows the choice at once, not on the next send.
    expect(find.text('Qwen 3.5 4B · simulated'), findsAtLeastNWidgets(1));
    await container
        .read(chatControllerProvider.notifier)
        .send('A turn on the switched model');
    await tester.pump();

    final chatCommands = container.read(chatControllerProvider.notifier);
    await chatCommands.regenerate();
    var active = container.read(chatControllerProvider).requireValue.active!;
    expect(active.messages.last.role, MessageRole.assistant);
    final editedUser = active.messages.lastWhere(
      (message) => message.role == MessageRole.user,
    );
    await chatCommands.editAndTruncate(
      editedUser.id,
      'Edited during the integration journey',
    );
    active = container.read(chatControllerProvider).requireValue.active!;
    expect(
      active.messages.any(
        (message) => message.text == 'Edited during the integration journey',
      ),
      isTrue,
    );

    // Branch from the settled assistant tail: a new conversation holds
    // the prefix, becomes active, and confirms with a toast. The edit ran
    // through the controller, so settle the rebuilt transcript first.
    await tester.pumpAndSettle();
    final branchSource = active.messages.last;
    expect(branchSource.role, MessageRole.assistant);
    final sourceConversationId = active.id;
    await tester.ensureVisible(
      find.byKey(Key('message-menu-${branchSource.id}')),
    );
    await tester.tap(find.byKey(Key('message-menu-${branchSource.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-message-branch')));
    await tester.pumpAndSettle();
    active = container.read(chatControllerProvider).requireValue.active!;
    expect(active.id, isNot(sourceConversationId));
    expect(find.text('New branch started'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));

    // Cross-chat search is a full screen now: the drawer button opens
    // it, the query debounces, and Cancel returns to the chat.
    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-field')), 'private');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-results')), findsOneWidget);
    expect(find.textContaining('private', findRichText: true), findsWidgets);
    await tester.tap(find.byKey(const Key('search-cancel')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();
    final firstConversation = _conversationId(tester);
    await tester.tap(find.byKey(Key('conversation-menu-$firstConversation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-pin-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Pinned'), findsWidgets);
    expect(
      container
          .read(chatControllerProvider)
          .requireValue
          .conversations
          .singleWhere((item) => item.id == firstConversation)
          .pinned,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 1600));

    await tester.tap(find.byKey(Key('conversation-menu-$firstConversation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-field')),
      'Renamed locally',
    );
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('conversation-menu-$firstConversation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.tap(find.byKey(const Key('new-chat-drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-drawer')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('simulation-banner')), findsOneWidget);

    // Models & downloads live one screen deeper now.
    await tester.tap(find.byKey(const Key('settings-model-row')));
    await tester.pumpAndSettle();
    final modelsScrollable = find.descendant(
      of: find.byKey(const Key('models-list')),
      matching: find.byType(Scrollable),
    );
    final modelCommands = container.read(modelControllerProvider.notifier);
    var model = container.read(modelControllerProvider).requireValue;
    if (model.statusOf('gemma4-mlx').phase != ArtifactPhase.installed) {
      await tester.scrollUntilVisible(
        find.byKey(const Key('model-download-gemma4-mlx')),
        240,
        scrollable: modelsScrollable,
      );
      await tester.tap(find.byKey(const Key('model-download-gemma4-mlx')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-download-confirm')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('model-pause-gemma4-mlx')),
      );
      await tester.pump(const Duration(milliseconds: 220));
      await tester.tap(find.byKey(const Key('model-pause-gemma4-mlx')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(modelControllerProvider)
            .requireValue
            .statusOf('gemma4-mlx')
            .phase,
        ArtifactPhase.paused,
      );
      await modelCommands.download('gemma4-mlx');
      await tester.pump();
      model = container.read(modelControllerProvider).requireValue;
      expect(model.statusOf('gemma4-mlx').phase, ArtifactPhase.installed);
    }

    await tester.scrollUntilVisible(
      find.byKey(const Key('runtime-toggle-button')),
      260,
      scrollable: modelsScrollable,
    );
    // scrollUntilVisible can stop with the button only clipping into
    // view; a tap there misses silently, so force it fully on-screen and
    // assert the toggle actually flipped the phase (the persisted state
    // survives reruns, so the direction depends on the last run).
    await tester.ensureVisible(find.byKey(const Key('runtime-toggle-button')));
    await tester.pumpAndSettle();
    final runtimeBefore = container
        .read(modelControllerProvider)
        .requireValue
        .runtime;
    final runtimeAfter = runtimeBefore == RuntimePhase.loaded
        ? RuntimePhase.unloaded
        : RuntimePhase.loaded;
    await tester.tap(find.byKey(const Key('runtime-toggle-button')));
    // The fake load's delay is timer- not frame-driven, so settle alone
    // can return mid-`loading`; poll the controller until it lands.
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (container.read(modelControllerProvider).requireValue.runtime ==
          runtimeAfter) {
        break;
      }
    }
    expect(
      container.read(modelControllerProvider).requireValue.runtime,
      runtimeAfter,
    );
    await _pageBack(tester);
    await tester.pumpAndSettle();
    final settingsScrollable = find.descendant(
      of: find.byKey(const Key('settings-list')),
      matching: find.byType(Scrollable),
    );

    // Advanced mode reveals the system-prompt row; response style commits
    // a per-profile preset the sampling layer picks up. The preference
    // persists across reruns, so normalize to off before driving the
    // switch through the UI.
    await container
        .read(preferencesControllerProvider.notifier)
        .setAdvancedMode(false);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('advanced-mode-switch')),
      240,
      scrollable: settingsScrollable,
    );
    await tester.ensureVisible(find.byKey(const Key('advanced-mode-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('advanced-mode-switch')));
    await tester.pumpAndSettle();
    expect(
      container.read(preferencesControllerProvider).requireValue.advancedMode,
      isTrue,
    );
    await tester.fling(
      find.byKey(const Key('settings-list')),
      const Offset(0, 1000),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-system-prompt-row')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-style-row')),
      -240,
      scrollable: settingsScrollable,
    );
    await tester.ensureVisible(find.byKey(const Key('settings-style-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-style-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('style-precise')));
    await tester.pumpAndSettle();
    expect(
      container
          .read(preferencesControllerProvider)
          .requireValue
          .styleFor('gemma4'),
      ResponseStyle.precise,
    );
    expect(find.byKey(const Key('gen-temperature-gemma4')), findsOneWidget);
    await _pageBack(tester);
    await tester.pumpAndSettle();

    // Language selection applies immediately and persists without restarting.
    // Return to English so the rest of this long-lived journey remains a
    // stable source-language smoke test as Polish grows.
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-language-row')),
      -240,
      scrollable: settingsScrollable,
    );
    await tester.tap(find.byKey(const Key('settings-language-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-polish')));
    await tester.pumpAndSettle();
    expect(find.text('Język'), findsWidgets);
    expect(
      container.read(preferencesControllerProvider).requireValue.language,
      AppLanguage.polish,
    );
    await _pageBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('Ustawienia'), findsWidgets);
    await tester.tap(find.byKey(const Key('settings-language-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-english')));
    await tester.pumpAndSettle();
    expect(
      container.read(preferencesControllerProvider).requireValue.language,
      AppLanguage.english,
    );
    await _pageBack(tester);
    await tester.pumpAndSettle();

    // Storage: the breakdown renders and the cache clears with a toast.
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-storage-row')),
      240,
      scrollable: settingsScrollable,
    );
    await tester.tap(find.byKey(const Key('settings-storage-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('storage-bar')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('clear-cache')),
      240,
      scrollable: find.descendant(
        of: find.byKey(const Key('storage-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('clear-cache')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('golem-toast')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    await _pageBack(tester);
    await tester.pumpAndSettle();

    // Legal information remains reachable and complete without a network.
    await tester.scrollUntilVisible(
      find.byKey(const Key('model-attribution-row')),
      260,
      scrollable: settingsScrollable,
    );
    await tester.tap(find.byKey(const Key('model-attribution-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-attribution-screen')), findsOneWidget);
    expect(find.text('GEMMA 4 E2B'), findsOneWidget);
    await _pageBack(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-source-licenses-row')),
      260,
      scrollable: settingsScrollable,
    );
    await tester.tap(find.byKey(const Key('open-source-licenses-row')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('licenses-list')),
      timeout: const Duration(seconds: 10),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('open-source-licenses-screen')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('license-llama.cpp')),
      260,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('licenses-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('llama.cpp'), findsOneWidget);
    await _pageBack(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-benchmark')),
      260,
      scrollable: find.descendant(
        of: find.byKey(const Key('settings-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('open-benchmark')));
    await tester.pumpAndSettle();
    final benchmarkRunButton = find.byKey(const Key('benchmark-run-button'));
    await tester.ensureVisible(benchmarkRunButton);
    await tester.pumpAndSettle();
    expect(benchmarkRunButton.hitTestable(), findsOneWidget);
    await tester.tap(benchmarkRunButton);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('benchmark-stop-button')),
    );
    await tester.tap(find.byKey(const Key('benchmark-stop-button')));
    await tester.pump();
    expect(container.read(benchmarkControllerProvider).result, isNull);
    await tester.tap(find.byKey(const Key('benchmark-run-button')));
    await _pumpUntilBenchmarkResult(tester, container);
    expect(container.read(benchmarkControllerProvider).result, isNotNull);
    final exportPath = await container
        .read(benchmarkControllerProvider.notifier)
        .export();
    expect(exportPath, isNotNull);

    // Persistence is exercised by the file repository during every mutation;
    // a subsequent app launch reads the same app-support file.
  });
}

Future<void> _pumpUntilBenchmarkResult(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final watch = Stopwatch()..start();
  while (container.read(benchmarkControllerProvider).result == null &&
      watch.elapsed < const Duration(seconds: 4)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pageBack(WidgetTester tester) async {
  final adaptiveBack = find.byType(GolemBackButton);
  if (adaptiveBack.evaluate().isNotEmpty) {
    await tester.tap(adaptiveBack.first);
    return;
  }
  await tester.pageBack();
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isEmpty && watch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

String _conversationId(WidgetTester tester) {
  final candidates = tester.widgetList<CupertinoMenuAnchor>(
    find.byType(CupertinoMenuAnchor),
  );
  for (final anchor in candidates) {
    final key = anchor.key;
    if (key is ValueKey<String> && key.value.startsWith('conversation-menu-')) {
      return key.value.substring('conversation-menu-'.length);
    }
  }
  throw StateError('Conversation menu was not found');
}

final class _JourneyPicker extends AttachmentPicker {
  const _JourneyPicker();

  @override
  Future<PreparedImage?> pick(
    AttachSource source, {
    String filesLabel = 'Images',
  }) async => PreparedImage(
    bytes: tinyPngBytes,
    mimeType: 'image/png',
    width: 2,
    height: 2,
  );
}
