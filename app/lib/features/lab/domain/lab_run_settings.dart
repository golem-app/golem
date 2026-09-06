import '../../../broker/context_window.dart' show contextPromptReserveTokens;
import '../../../core/domain/generation_settings.dart';
import '../../../core/domain/model_profile_spec.dart';

/// The bench's run settings: sparse, like the user's per-model overrides, so
/// a null field is the profile's shipped default and the Rig can say which
/// values are the user's. Never persisted — a bench run's settings live on
/// the run's own immutable configuration snapshot (#58).
final class LabRunSettings {
  const LabRunSettings({
    this.contextLength,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.reasoningEnabled = false,
    this.seed,
  });

  final int? contextLength;
  final int? maxTokens;
  final double? temperature;
  final double? topP;
  final int? topK;
  final bool reasoningEnabled;

  /// A fixed sampling seed for reproducible runs; null samples freely.
  final int? seed;

  /// The channel the engine already has for the user's sparse settings.
  SamplingOverrides toOverrides() => SamplingOverrides(
    temperature: temperature,
    topP: topP,
    topK: topK,
    maxTokens: maxTokens,
    contextLength: contextLength,
  );

  LabRunSettings copyWith({
    int? Function()? contextLength,
    int? Function()? maxTokens,
    double? Function()? temperature,
    double? Function()? topP,
    int? Function()? topK,
    bool? reasoningEnabled,
    int? Function()? seed,
  }) => LabRunSettings(
    contextLength: contextLength == null ? this.contextLength : contextLength(),
    maxTokens: maxTokens == null ? this.maxTokens : maxTokens(),
    temperature: temperature == null ? this.temperature : temperature(),
    topP: topP == null ? this.topP : topP(),
    topK: topK == null ? this.topK : topK(),
    reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
    seed: seed == null ? this.seed : seed(),
  );

  /// Every way these settings cannot be sent, against the profile's defaults
  /// for the mode and the artifact's configured context. The same reserve
  /// rule Settings enforces: the budget must leave room for a prompt.
  List<LabSettingsProblem> validate({
    required ProfileSampling defaults,
    required int contextCeiling,
  }) {
    final context = contextLength ?? defaults.contextLength;
    final budget = maxTokens ?? defaults.maxTokens;
    return [
      if (context < labContextFloor) LabSettingsProblem.contextBelowFloor,
      if (context > contextCeiling) LabSettingsProblem.contextAboveCeiling,
      if (budget < 1) LabSettingsProblem.maxTokensBelowOne,
      if (budget > context - contextPromptReserveTokens)
        LabSettingsProblem.maxTokensAboveBudget,
      if (temperature case final t? when t < 0 || t > 2)
        LabSettingsProblem.temperatureOutOfRange,
      if (topP case final p? when p <= 0 || p > 1)
        LabSettingsProblem.topPOutOfRange,
      if (topK case final k? when k < 0) LabSettingsProblem.topKNegative,
      if (seed case final s? when s < 0) LabSettingsProblem.seedNegative,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is LabRunSettings &&
      other.contextLength == contextLength &&
      other.maxTokens == maxTokens &&
      other.temperature == temperature &&
      other.topP == topP &&
      other.topK == topK &&
      other.reasoningEnabled == reasoningEnabled &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(
    contextLength,
    maxTokens,
    temperature,
    topP,
    topK,
    reasoningEnabled,
    seed,
  );
}

/// The smallest context the bench lets a run claim.
const labContextFloor = 512;

enum LabSettingsProblem {
  /// Not a validation failure: a run is in flight, and settings are locked.
  benchLocked,
  contextBelowFloor,
  contextAboveCeiling,
  maxTokensBelowOne,
  maxTokensAboveBudget,
  temperatureOutOfRange,
  topPOutOfRange,
  topKNegative,
  seedNegative,
}
