import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/features/benchmark/benchmark_screen.dart';
import 'package:golem_flutter/features/settings/response_style_screen.dart';

import 'support/harness.dart';
import 'support/in_memory_preferences_repository.dart';
import 'support/in_memory_settings_repository.dart';

void main() {
  testWidgets('reset button width', (tester) async {
    await pumpWithRepositories(
      tester,
      preferences: InMemoryPreferencesRepository(
        const AppPreferences(advancedMode: true),
      ),
      settings: InMemorySettingsRepository(
        const GenerationSettings(
          models: {'gemma4': SamplingOverrides(temperature: 0.9)},
        ),
      ),
      child: const ResponseStyleScreen(),
    );
    final reset = find.byKey(const Key('gen-reset-gemma4'));
    // ignore: avoid_print
    print('PROBE reset found=${reset.evaluate().length}');
    if (reset.evaluate().isNotEmpty) {
      // ignore: avoid_print
      print(
        'PROBE reset size ${tester.getSize(reset)} topLeft ${tester.getTopLeft(reset)}',
      );
    }
    final minus = find.byKey(const Key('gen-max-tokens-gemma4-minus'));
    // ignore: avoid_print
    print('PROBE stepper found=${minus.evaluate().length}');
  }, variant: androidChrome);

  testWidgets('default prefs build the sampling card?', (tester) async {
    await pumpWithRepositories(tester, child: const ResponseStyleScreen());
    // ignore: avoid_print
    print(
      'PROBE default steppers=${find.byKey(const Key('gen-max-tokens-gemma4-minus')).evaluate().length}',
    );
  }, variant: androidChrome);

  testWidgets('benchmark segment width', (tester) async {
    await pumpWithRepositories(tester, child: const BenchmarkScreen());
    final picker = find.byKey(const Key('benchmark-phase-picker'));
    // ignore: avoid_print
    print('PROBE picker size ${tester.getSize(picker)}');
  }, variant: androidChrome);
}
