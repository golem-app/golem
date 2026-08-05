import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/features/settings/settings_screen.dart';

import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_settings_repository.dart';

/// A frozen model state: this suite exercises the generation section only.
final class _StaticModels implements ModelManagementRepository {
  const _StaticModels(this.state);
  final ModelState state;

  @override
  Future<ModelState> load() async => state;

  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(state);

  @override
  Future<ModelState> pause(String artifactKey) async => state;

  @override
  Future<ModelState> cancel(String artifactKey) async => state;

  @override
  Future<ModelState> delete(String artifactKey) async => state;

  @override
  Future<ModelState> loadRuntime() async => state;

  @override
  Future<ModelState> unloadRuntime() async => state;
}

void main() {
  late InMemorySettingsRepository settings;

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    settings = InMemorySettingsRepository();
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(
          FakeInferenceRepository(eventDelay: Duration.zero),
        ),
        settingsRepositoryProvider.overrideWithValue(settings),
        modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
        modelManagementRepositoryProvider.overrideWithValue(
          _StaticModels(const ModelState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          theme: GolemTheme.theme(Brightness.light),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('steppers commit overrides, clamp together, and reset', (
    tester,
  ) async {
    await pumpSettings(tester);
    await reveal(tester, const Key('gen-max-tokens-gemma4'));

    // Default state advertises itself and offers no reset.
    expect(
      find.descendant(
        of: find.byKey(const Key('gen-max-tokens-gemma4')),
        matching: find.text('default'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('gen-reset-gemma4')), findsNothing);

    await tester.tap(find.byKey(const Key('gen-max-tokens-gemma4-minus')));
    await tester.pumpAndSettle();
    expect(settings.settings.overridesFor('gemma4').maxTokens, 1792);
    expect(
      find.descendant(
        of: find.byKey(const Key('gen-max-tokens-gemma4')),
        matching: find.text('default'),
      ),
      findsNothing,
    );

    // Shrinking the context below the budget clamps the budget with it.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    await container
        .read(settingsControllerProvider.notifier)
        .updateModel(
          'gemma4',
          settings.settings
              .overridesFor('gemma4')
              .copyWith(maxTokens: () => 8192),
        );
    await tester.pumpAndSettle();
    await reveal(tester, const Key('gen-context-gemma4'));
    await tester.tap(find.byKey(const Key('gen-context-gemma4-minus')));
    await tester.pumpAndSettle();
    final overrides = settings.settings.overridesFor('gemma4');
    expect(overrides.contextLength, 7168);
    expect(overrides.maxTokens, 7168);

    await reveal(tester, const Key('gen-reset-gemma4'));
    await tester.tap(find.byKey(const Key('gen-reset-gemma4')));
    await tester.pumpAndSettle();
    expect(settings.settings.models, isEmpty);
  });

  testWidgets('the temperature slider commits on drag end', (tester) async {
    await pumpSettings(tester);
    await reveal(tester, const Key('gen-temperature-qwen35'));

    await tester.drag(
      find.byKey(const Key('gen-temperature-qwen35')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    final committed = settings.settings.overridesFor('qwen35').temperature;
    expect(committed, isNotNull);
    expect(committed, isNot(0.7));

    // The Qwen card carries the pinned-thinking footnote.
    expect(find.textContaining('Thinking mode keeps'), findsOneWidget);
  });
}
