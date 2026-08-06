import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/response_style_mapping.dart';

void main() {
  test('balanced maps to no overrides for every profile', () {
    for (final profile in ['gemma4', 'qwen35', 'custom-anything']) {
      expect(
        styleOverridesFor(profile, ResponseStyle.balanced).isEmpty,
        isTrue,
        reason: 'balanced means the profile defaults for $profile',
      );
    }
  });

  test('precise and creative map to the pinned per-profile values', () {
    // These constants are the product mapping the Response style screen
    // promises; the PR states them and this test is the proof.
    final gemmaPrecise = styleOverridesFor('gemma4', ResponseStyle.precise);
    expect(gemmaPrecise.temperature, 0.3);
    expect(gemmaPrecise.topP, 0.9);
    final gemmaCreative = styleOverridesFor('gemma4', ResponseStyle.creative);
    expect(gemmaCreative.temperature, 1.3);
    expect(gemmaCreative.topP, 0.99);
    final qwenPrecise = styleOverridesFor('qwen35', ResponseStyle.precise);
    expect(qwenPrecise.temperature, 0.3);
    expect(qwenPrecise.topP, 0.8);
    final qwenCreative = styleOverridesFor('qwen35', ResponseStyle.creative);
    expect(qwenCreative.temperature, 1.0);
    expect(qwenCreative.topP, 0.95);
    // Styles steer sampling only — budgets stay the user's.
    for (final style in [ResponseStyle.precise, ResponseStyle.creative]) {
      for (final profile in ['gemma4', 'qwen35']) {
        final overrides = styleOverridesFor(profile, style);
        expect(overrides.maxTokens, isNull);
        expect(overrides.contextLength, isNull);
      }
    }
  });

  test('unknown profiles fall back to a temperature-only steer', () {
    final precise = styleOverridesFor('custom-x', ResponseStyle.precise);
    expect(precise.temperature, 0.3);
    expect(precise.topP, isNull);
    expect(
      styleOverridesFor('custom-x', ResponseStyle.creative).temperature,
      1.2,
    );
  });

  test('manual Advanced overrides win knob by knob over the style', () {
    final layered = layerOverrides(
      manual: const SamplingOverrides(temperature: 0.55, maxTokens: 4096),
      style: styleOverridesFor('gemma4', ResponseStyle.precise),
    );
    expect(layered.temperature, 0.55, reason: 'hand-set beats the style');
    expect(layered.topP, 0.9, reason: 'untouched knob falls to the style');
    expect(layered.maxTokens, 4096);
    expect(
      layered.topK,
      isNull,
      reason: 'what neither sets stays the profile default',
    );
  });
}
