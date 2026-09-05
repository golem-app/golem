import '../core/domain/generation_settings.dart';
import 'model_profile.dart';
import 'runtime.dart';

/// The sampling a request actually carries to the engine: the profile's
/// mode-specific defaults with the user's sparse overrides layered on, except
/// where the profile pins them (a correctness constraint — see the Qwen
/// profile); token budgets stay the user's to size, and the presence penalty
/// is the profile's alone. One function, so the repository sends exactly what
/// the bench shows (#58): a displayed "effective value" is this call, not a
/// second reading of the same rules.
///
/// Returns the parameters and whether any user override reached them.
(BrokerSamplingParameters, bool) effectiveSampling({
  required ModelProfile profile,
  required ProfileSampling defaults,
  SamplingOverrides? overrides,
  int? seed,
}) {
  final user = overrides ?? const SamplingOverrides();
  final samplingOverridable = !defaults.pinned;
  final applied =
      user.maxTokens != null ||
      user.contextLength != null ||
      (samplingOverridable &&
          (user.temperature != null || user.topP != null || user.topK != null));
  return (
    BrokerSamplingParameters(
      maxTokens: user.maxTokens ?? defaults.maxTokens,
      temperature: samplingOverridable
          ? (user.temperature ?? defaults.temperature)
          : defaults.temperature,
      topP: samplingOverridable ? (user.topP ?? defaults.topP) : defaults.topP,
      topK: samplingOverridable ? (user.topK ?? defaults.topK) : defaults.topK,
      // A correctness knob, never a preference: no user channel exists.
      presencePenalty: defaults.presencePenalty,
      contextLength: user.contextLength ?? defaults.contextLength,
      seed: seed,
      stopSequences: profile.stopSequences,
      stopTokenIds: profile.stopTokenIds,
    ),
    applied,
  );
}
