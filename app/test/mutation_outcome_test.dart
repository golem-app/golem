import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/features/settings/appearance_screen.dart';

import 'package:golem_flutter/features/chat/application/chat_providers.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/features/settings/application/preferences_providers.dart';
import 'package:golem_flutter/features/settings/application/settings_providers.dart';
import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';
import 'support/in_memory_settings_repository.dart';

/// A failed save can never keep presenting as saved: commands return false,
/// state rolls back to a value-equal previous, and nothing is thrown.
void main() {
  group('SettingsController.updateModel', () {
    test('rolls back a failed save and reports it', () async {
      final repository = InMemorySettingsRepository();
      final container = buildContainer(settings: repository);
      addTearDown(container.dispose);
      final controller = container.read(settingsControllerProvider.notifier);
      final subscription = container.listen(
        settingsControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(settingsControllerProvider.future);
      final previous = container.read(settingsControllerProvider).requireValue;

      repository.failingSaves = 1;
      final saved = await controller.updateModel(
        'gemma4',
        const SamplingOverrides(temperature: 0.9),
      );

      expect(saved, isFalse);
      expect(container.read(settingsControllerProvider).requireValue, previous);
      expect(repository.settings, previous);

      // The same command succeeds once the store recovers.
      final retried = await controller.updateModel(
        'gemma4',
        const SamplingOverrides(temperature: 0.9),
      );
      expect(retried, isTrue);
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .overridesFor('gemma4')
            .temperature,
        0.9,
      );
      expect(repository.settings.overridesFor('gemma4').temperature, 0.9);
    });

    test(
      'overlapping failures roll back to the last persisted value',
      () async {
        final repository = InMemorySettingsRepository();
        final container = buildContainer(settings: repository);
        addTearDown(container.dispose);
        final controller = container.read(settingsControllerProvider.notifier);
        await container.read(settingsControllerProvider.future);
        final persisted = container
            .read(settingsControllerProvider)
            .requireValue;

        repository.failingSaves = 2;
        // Both commits fail; the second one's "previous" is the first one's
        // unpersisted optimistic value, which must NOT survive the rollback.
        final first = controller.updateModel(
          'gemma4',
          const SamplingOverrides(temperature: 0.2),
        );
        final second = controller.updateModel(
          'gemma4',
          const SamplingOverrides(temperature: 1.1),
        );
        expect(await first, isFalse);
        expect(await second, isFalse);
        expect(
          container.read(settingsControllerProvider).requireValue,
          persisted,
        );
        expect(repository.settings, persisted);
      },
    );

    test('a stale failure cannot clobber a newer successful commit', () async {
      final repository = InMemorySettingsRepository();
      final container = buildContainer(settings: repository);
      addTearDown(container.dispose);
      final controller = container.read(settingsControllerProvider.notifier);
      await container.read(settingsControllerProvider.future);

      repository.failingSaves = 1;
      // Both commits run concurrently: the first fails, the second lands.
      final first = controller.updateModel(
        'gemma4',
        const SamplingOverrides(temperature: 0.2),
      );
      final second = controller.updateModel(
        'gemma4',
        const SamplingOverrides(temperature: 1.1),
      );
      expect(await first, isFalse);
      expect(await second, isTrue);
      expect(
        container
            .read(settingsControllerProvider)
            .requireValue
            .overridesFor('gemma4')
            .temperature,
        1.1,
      );
    });
  });

  group('PreferencesController', () {
    test('rolls back a failed commit and reports it', () async {
      final repository = InMemoryPreferencesRepository();
      final container = buildContainer(preferences: repository);
      addTearDown(container.dispose);
      final controller = container.read(preferencesControllerProvider.notifier);
      await container.read(preferencesControllerProvider.future);

      repository.failingSaves = 1;
      final saved = await controller.setTheme(ThemeSetting.dark);

      expect(saved, isFalse);
      expect(
        container.read(preferencesControllerProvider).requireValue.theme,
        ThemeSetting.system,
      );
      expect(repository.preferences.theme, ThemeSetting.system);

      expect(await controller.setTheme(ThemeSetting.dark), isTrue);
      expect(repository.preferences.theme, ThemeSetting.dark);
    });

    test('a failed history wipe keeps save-history on', () async {
      final chatHistory = InMemoryChatHistoryRepository(seedHistory());
      final preferences = InMemoryPreferencesRepository();
      final container = buildContainer(
        preferences: preferences,
        chatHistory: chatHistory,
      );
      addTearDown(container.dispose);
      final controller = container.read(preferencesControllerProvider.notifier);
      await container.read(preferencesControllerProvider.future);

      chatHistory.failingSaves = 1;
      final saved = await controller.setSaveHistory(false);

      expect(saved, isFalse);
      // The preference never flipped and the chats never left the disk.
      expect(
        container.read(preferencesControllerProvider).requireValue.saveHistory,
        isTrue,
      );
      expect(preferences.preferences.saveHistory, isTrue);
      expect(chatHistory.snapshot.conversations, isNotEmpty);
    });

    test('a wipe that lands under a failed commit is undone', () async {
      final chatHistory = InMemoryChatHistoryRepository(seedHistory());
      final preferences = InMemoryPreferencesRepository();
      final container = buildContainer(
        preferences: preferences,
        chatHistory: chatHistory,
      );
      addTearDown(container.dispose);
      final controller = container.read(preferencesControllerProvider.notifier);
      await container.read(preferencesControllerProvider.future);
      await container.read(chatControllerProvider.future);

      preferences.failingSaves = 1;
      final saved = await controller.setSaveHistory(false);

      expect(saved, isFalse);
      // The toggle stayed on, so the successful wipe was rolled back too:
      // disk must match what the UI claims it kept.
      expect(
        container.read(preferencesControllerProvider).requireValue.saveHistory,
        isTrue,
      );
      expect(chatHistory.snapshot.conversations, isNotEmpty);
    });

    test('a failed preference save keeps the custom model out', () async {
      final preferences = InMemoryPreferencesRepository();
      final container = buildContainer(preferences: preferences);
      addTearDown(container.dispose);
      final controller = container.read(preferencesControllerProvider.notifier);
      await container.read(preferencesControllerProvider.future);
      final models = await container.read(modelControllerProvider.future);

      preferences.failingSaves = 1;
      final added = await controller.addCustomModel(
        const CustomModelSpec(
          repository: 'org/model',
          engine: ModelEngine.gguf,
        ),
      );

      expect(added, isFalse);
      expect(
        container.read(preferencesControllerProvider).requireValue.customModels,
        isEmpty,
      );
      // The model card was never registered behind the failed preference.
      expect(container.read(modelControllerProvider).requireValue, models);
    });
  });

  group('ChatController.deleteAllChats', () {
    test('a failed wipe keeps the chats visible', () async {
      final chatHistory = InMemoryChatHistoryRepository(seedHistory());
      final container = buildContainer(chatHistory: chatHistory);
      addTearDown(container.dispose);
      final controller = container.read(chatControllerProvider.notifier);
      await container.read(chatControllerProvider.future);

      chatHistory.failingSaves = 1;
      final deleted = await controller.deleteAllChats();

      expect(deleted, isFalse);
      expect(
        container.read(chatControllerProvider).requireValue.conversations,
        isNotEmpty,
      );
      expect(chatHistory.snapshot.conversations, isNotEmpty);

      expect(await controller.deleteAllChats(), isTrue);
      expect(
        container.read(chatControllerProvider).requireValue.conversations,
        isEmpty,
      );
      expect(chatHistory.snapshot.conversations, isEmpty);
    });
  });

  testWidgets('a failed toggle snaps back and toasts', (tester) async {
    final repository = InMemoryPreferencesRepository();
    await pumpWithRepositories(
      tester,
      preferences: repository,
      child: const AppearanceScreen(),
    );
    repository.failingSaves = 1;

    await tester.tap(find.byKey(const Key('toggle-metrics')));
    await tester.pump();
    await tester.pumpAndSettle();

    // The stored value never changed, the switch shows it again, and the
    // failure was announced.
    expect(repository.preferences.showMetrics, isTrue);
    final toggle = tester.widget<CupertinoSwitch>(
      find.byKey(const Key('toggle-metrics')),
    );
    expect(toggle.value, isTrue);
    expect(find.text("Couldn't save. Try again."), findsOneWidget);
    // The toast dismisses itself; drain its timer before teardown.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byKey(const Key('golem-toast')), findsNothing);
  });
}
