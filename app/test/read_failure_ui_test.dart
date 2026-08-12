import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/settings/appearance_screen.dart';
import 'package:golem_flutter/features/settings/language_screen.dart';
import 'package:golem_flutter/features/settings/response_style_screen.dart';
import 'package:golem_flutter/features/settings/storage_screen.dart';
import 'package:golem_flutter/features/settings/models_screen.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';
import 'support/in_memory_settings_repository.dart';

/// A failed read renders as an error with a retry — never the eternal
/// spinner or a plausible zero.
void main() {
  testWidgets('storage shows an error pane and recovers on retry', (
    tester,
  ) async {
    // Empty history keeps the (0, 0) storage signature stable, so the
    // breakdown computes exactly once and the injected failure is not
    // consumed by a signature-driven recompute.
    final chatHistory = InMemoryChatHistoryRepository()..failingStoredBytes = 1;
    await pumpWithRepositories(
      tester,
      chatHistory: chatHistory,
      child: const StorageScreen(),
    );

    expect(find.byKey(const Key('storage-error')), findsOneWidget);
    expect(find.text("Couldn't read storage."), findsOneWidget);
    expect(find.byKey(const Key('storage-list')), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('storage-error')), findsNothing);
    expect(find.byKey(const Key('storage-list')), findsOneWidget);
  });

  testWidgets('a failed model-state load offers a retry, not raw text', (
    tester,
  ) async {
    final models = _FlakyModels(failingLoads: 1);
    await pumpWithRepositories(
      tester,
      models: models,
      child: const ModelsScreen(),
    );

    expect(find.byKey(const Key('models-load-error')), findsOneWidget);
    expect(find.text("Couldn't load model state."), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('models-load-error')), findsNothing);
    expect(find.byKey(const Key('models-list')), findsOneWidget);
  });

  testWidgets('a failed chat-history load offers a retry, not a dead root', (
    tester,
  ) async {
    final chatHistory = InMemoryChatHistoryRepository(seedHistory())
      ..failingLoads = 1;
    await pumpWithRepositories(
      tester,
      chatHistory: chatHistory,
      child: const ChatScreen(),
    );

    expect(find.byKey(const Key('chat-load-error')), findsOneWidget);
    expect(find.text("Couldn't load chat history."), findsOneWidget);
    expect(find.byKey(const Key('chat-composer')), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-load-error')), findsNothing);
    expect(find.byKey(const Key('chat-composer')), findsOneWidget);
  });

  testWidgets('a failed preferences load surfaces on Appearance with retry', (
    tester,
  ) async {
    final preferences = InMemoryPreferencesRepository()..failingLoads = 1;
    await pumpWithRepositories(
      tester,
      preferences: preferences,
      child: const AppearanceScreen(),
    );

    expect(find.byKey(const Key('preferences-load-error')), findsOneWidget);
    expect(find.byKey(const Key('toggle-metrics')), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('preferences-load-error')), findsNothing);
    expect(find.byKey(const Key('toggle-metrics')), findsOneWidget);
  });

  testWidgets('the shared retry action follows the active Polish locale', (
    tester,
  ) async {
    final preferences = InMemoryPreferencesRepository()..failingLoads = 1;
    await pumpWithRepositories(
      tester,
      locale: const Locale('pl'),
      preferences: preferences,
      child: const LanguageScreen(),
    );

    expect(
      find.byKey(const Key('language-preferences-load-error')),
      findsOneWidget,
    );
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);

    await tester.tap(find.text('Spróbuj ponownie'));
    await tester.pumpAndSettle();
    expect(find.text('Język'), findsWidgets);
  });

  testWidgets('the storage retry leaves a healthy model controller alone', (
    tester,
  ) async {
    final chatHistory = InMemoryChatHistoryRepository()..failingStoredBytes = 1;
    final models = _FlakyModels(failingLoads: 0);
    await pumpWithRepositories(
      tester,
      chatHistory: chatHistory,
      models: models,
      child: const StorageScreen(),
    );
    expect(find.byKey(const Key('storage-error')), findsOneWidget);
    final loadsBeforeRetry = models.loads;

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    // Only the failed breakdown recomputed: invalidating a healthy
    // ModelController would kill an in-flight download.
    expect(find.byKey(const Key('storage-list')), findsOneWidget);
    expect(models.loads, loadsBeforeRetry);
  });

  testWidgets('failed settings block sampling edits until retried', (
    tester,
  ) async {
    final settings = InMemorySettingsRepository()..failingLoads = 1;
    await pumpWithRepositories(
      tester,
      settings: settings,
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(advancedMode: true),
      ),
      child: const ResponseStyleScreen(),
    );

    expect(find.byKey(const Key('settings-load-error')), findsOneWidget);
    expect(find.byKey(const Key('gen-temperature-gemma4')), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-load-error')), findsNothing);
    expect(find.byKey(const Key('gen-temperature-gemma4')), findsOneWidget);
  });
}

/// Fails its first [failingLoads] loads, then behaves like [StaticModels].
final class _FlakyModels implements ModelManagementRepository {
  _FlakyModels({required this.failingLoads});
  int failingLoads;
  int loads = 0;
  static const _state = ModelState();

  @override
  Future<ModelState> load() async {
    loads++;
    if (failingLoads > 0) {
      failingLoads--;
      throw const PersistenceException(
        PersistenceFailureKind.read,
        'Could not read the stored model state.',
      );
    }
    return _state;
  }

  @override
  Future<ModelState> recordRuntime(RuntimePhase phase, {String? failure}) =>
      Future.value(_state);
  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(_state);
  @override
  Future<ModelState> pause(String artifactKey) async => _state;
  @override
  Future<ModelState> cancel(String artifactKey) async => _state;
  @override
  Future<ModelState> delete(String artifactKey) async => _state;
  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => _state;
}
