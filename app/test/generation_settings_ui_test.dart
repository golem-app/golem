import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/features/settings/response_style_screen.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';
import 'support/in_memory_preferences_repository.dart';
import 'support/in_memory_settings_repository.dart';

void main() {
  late InMemorySettingsRepository settings;

  // The sampling controls live on the Response style screen (Advanced
  // mode) and always edit the active profile, so each pump names the
  // profile under test through the backend signal.
  Future<void> pumpSettings(
    WidgetTester tester, {
    GenerationSettings seed = const GenerationSettings(),
    String profileKey = 'gemma4',
    ResponseStyle style = ResponseStyle.balanced,
  }) async {
    setViewport(tester);
    settings = InMemorySettingsRepository(seed);
    final container = ProviderContainer(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          InMemoryChatHistoryRepository(),
        ),
        inferenceRepositoryProvider.overrideWithValue(
          FakeInferenceRepository(eventDelay: Duration.zero),
        ),
        inferenceBackendProvider.overrideWithValue(
          InferenceBackendConfig(
            kind: InferenceBackendKind.fake,
            profileKey: profileKey,
          ),
        ),
        settingsRepositoryProvider.overrideWithValue(settings),
        preferencesRepositoryProvider.overrideWithValue(
          InMemoryPreferencesRepository(
            const AppPreferences(
              advancedMode: true,
            ).withStyle(profileKey, style),
          ),
        ),
        modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
        modelManagementRepositoryProvider.overrideWithValue(
          const StaticModels(ModelState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: wrapApp(child: const ResponseStyleScreen()),
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
            of: find.byKey(const Key('style-list')),
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

    // Shrinking the context clamps the budget with it, keeping the prompt
    // reserve free — the engines reject prompt + budget over the context,
    // so budget == context would fail every send.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ResponseStyleScreen)),
    );
    await container
        .read(settingsControllerProvider.notifier)
        .updateModel(
          'gemma4',
          settings.settings
              .overridesFor('gemma4')
              .copyWith(maxTokens: () => 7680),
        );
    await tester.pumpAndSettle();
    await reveal(tester, const Key('gen-context-gemma4'));
    await tester.tap(find.byKey(const Key('gen-context-gemma4-minus')));
    await tester.pumpAndSettle();
    final overrides = settings.settings.overridesFor('gemma4');
    expect(overrides.contextLength, 7168);
    expect(overrides.maxTokens, 7168 - 512);

    await reveal(tester, const Key('gen-reset-gemma4'));
    await tester.tap(find.byKey(const Key('gen-reset-gemma4')));
    await tester.pumpAndSettle();
    expect(settings.settings.models, isEmpty);
  });

  testWidgets('the budget stepper cannot reach the context ceiling', (
    tester,
  ) async {
    await pumpSettings(tester);
    await reveal(tester, const Key('gen-max-tokens-gemma4'));
    // Default context 8192: the plus button must stop at 8192 - 512, never
    // at a value the engines would reject on every send.
    final plus = find.byKey(const Key('gen-max-tokens-gemma4-plus'));
    for (var i = 0; i < 30; i++) {
      final button = tester.widget<CupertinoButton>(plus);
      if (button.onPressed == null) break;
      await tester.tap(plus);
      await tester.pumpAndSettle();
    }
    expect(settings.settings.overridesFor('gemma4').maxTokens, 8192 - 512);
    expect(
      tester.widget<CupertinoButton>(plus).onPressed,
      isNull,
      reason: 'the ceiling reserves prompt tokens by construction',
    );
  });

  testWidgets('shrinking Qwen context clamps its thinking budget too', (
    tester,
  ) async {
    await pumpSettings(tester, profileKey: 'qwen35');
    await reveal(tester, const Key('gen-context-qwen35'));
    // No maxTokens override: direct mode defaults to 2048 but thinking
    // mode to 4096, and the clamp must satisfy the larger of the two.
    final minus = find.byKey(const Key('gen-context-qwen35-minus'));
    for (var i = 0; i < 4; i++) {
      await tester.tap(minus);
      await tester.pumpAndSettle();
    }
    final overrides = settings.settings.overridesFor('qwen35');
    expect(overrides.contextLength, 4096);
    expect(
      overrides.maxTokens,
      2048,
      reason:
          'the hidden 4096 thinking default must clamp (it would always '
          'fail in a 4096 context), but never above the displayed 2048 — '
          'a clamp may lower the visible budget, not quietly raise it',
    );
  });

  testWidgets('hand-edited out-of-range settings render without throwing', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      seed: const GenerationSettings().withModel(
        'gemma4',
        // Below every legal range: the tolerant store accepts it, and the
        // controls must sanitize instead of throwing on clamp bounds.
        const SamplingOverrides(maxTokens: 64, contextLength: 512),
      ),
    );
    await reveal(tester, const Key('gen-context-gemma4'));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('gen-max-tokens-gemma4')), findsOneWidget);
  });

  testWidgets('the sampling card states the effective style values', (
    tester,
  ) async {
    // The card must show what generation will run — the style's values
    // layered under manual overrides — never the profile defaults while
    // a style silently steers them.
    await pumpSettings(tester, style: ResponseStyle.precise);
    await reveal(tester, const Key('gen-top-p-gemma4'));
    expect(find.text('0.30'), findsOneWidget, reason: 'precise temperature');
    expect(find.text('0.90'), findsOneWidget, reason: 'precise top-p');
    expect(find.textContaining('· precise'), findsNWidgets(2));
    // A hand-set knob wins and drops the style caption on that row only.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ResponseStyleScreen)),
    );
    await container
        .read(settingsControllerProvider.notifier)
        .updateModel('gemma4', const SamplingOverrides(temperature: 0.55));
    await tester.pumpAndSettle();
    expect(find.text('0.55'), findsOneWidget);
    expect(find.textContaining('· precise'), findsOneWidget);
  });

  testWidgets('the temperature slider commits on drag end', (tester) async {
    await pumpSettings(tester, profileKey: 'qwen35');
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
