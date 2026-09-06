import '../core/domain/generation_settings.dart';
import 'model_profile.dart';
import 'runtime.dart';

/// The process-wide sampling seed, from `GOLEM_SAMPLING_SEED` at build time
/// (0, the default, is none): what a request without a seed of its own
/// inherits at the engine, so a surface that records the seed a run used
/// resolves it here rather than reporting free sampling it did not do.
const int? launchSamplingSeed = int.fromEnvironment('GOLEM_SAMPLING_SEED') == 0
    ? null
    : int.fromEnvironment('GOLEM_SAMPLING_SEED');

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
