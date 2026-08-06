import 'app_preferences.dart';
import 'generation_settings.dart';

/// Maps a response style onto explicit sampling values per model profile.
///
/// Balanced is deliberately empty — the profile's own recommended defaults
/// apply, so profile tuning reaches users who never picked a style. The
/// other two are explicit per-profile constants (provable in tests and on
/// the INFERNO_METRICS line). Qwen's pinned thinking-mode sampling is
/// unaffected: styles ride the same [SamplingOverrides] channel the broker
/// already refuses to apply to pinned modes.
const _styleTables = <String, Map<ResponseStyle, SamplingOverrides>>{
  'gemma4': {
    ResponseStyle.precise: SamplingOverrides(temperature: 0.3, topP: 0.9),
    ResponseStyle.creative: SamplingOverrides(temperature: 1.3, topP: 0.99),
  },
  'qwen35': {
    ResponseStyle.precise: SamplingOverrides(temperature: 0.3, topP: 0.8),
    ResponseStyle.creative: SamplingOverrides(temperature: 1.0, topP: 0.95),
  },
};

/// Fallback for profiles without an explicit table (custom repositories):
/// steer temperature only and leave everything else to the profile.
const _genericTable = <ResponseStyle, SamplingOverrides>{
  ResponseStyle.precise: SamplingOverrides(temperature: 0.3),
  ResponseStyle.creative: SamplingOverrides(temperature: 1.2),
};

SamplingOverrides styleOverridesFor(String profileKey, ResponseStyle style) =>
    (_styleTables[profileKey] ?? _genericTable)[style] ??
    const SamplingOverrides();

/// Layers the user's hand-set Advanced overrides on top of the style's
/// values, knob by knob: a manual value always wins, an untouched knob
/// falls to the style, and whatever neither sets stays the profile default.
SamplingOverrides layerOverrides({
  required SamplingOverrides manual,
  required SamplingOverrides style,
}) => SamplingOverrides(
  temperature: manual.temperature ?? style.temperature,
  topP: manual.topP ?? style.topP,
  topK: manual.topK ?? style.topK,
  maxTokens: manual.maxTokens ?? style.maxTokens,
  contextLength: manual.contextLength ?? style.contextLength,
);
