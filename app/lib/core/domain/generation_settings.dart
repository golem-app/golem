import 'dart:convert';

/// A user's sparse per-model sampling overrides: null means "use the model
/// profile's recommended default", so future default changes reach users
/// who never touched a control.
final class SamplingOverrides {
  const SamplingOverrides({
    this.temperature,
    this.topP,
    this.topK,
    this.maxTokens,
    this.contextLength,
  });

  final double? temperature;
  final double? topP;
  final int? topK;
  final int? maxTokens;
  final int? contextLength;

  bool get isEmpty =>
      temperature == null &&
      topP == null &&
      topK == null &&
      maxTokens == null &&
      contextLength == null;

  SamplingOverrides copyWith({
    double? Function()? temperature,
    double? Function()? topP,
    int? Function()? topK,
    int? Function()? maxTokens,
    int? Function()? contextLength,
  }) => SamplingOverrides(
    temperature: temperature == null ? this.temperature : temperature(),
    topP: topP == null ? this.topP : topP(),
    topK: topK == null ? this.topK : topK(),
    maxTokens: maxTokens == null ? this.maxTokens : maxTokens(),
    contextLength: contextLength == null ? this.contextLength : contextLength(),
  );

  Map<String, Object?> toJson() => {
    if (temperature != null) 'temperature': temperature,
    if (topP != null) 'topP': topP,
    if (topK != null) 'topK': topK,
    if (maxTokens != null) 'maxTokens': maxTokens,
    if (contextLength != null) 'contextLength': contextLength,
  };

  factory SamplingOverrides.fromJson(Map<String, Object?> json) =>
      SamplingOverrides(
        temperature: (json['temperature'] as num?)?.toDouble(),
        topP: (json['topP'] as num?)?.toDouble(),
        topK: json['topK'] as int?,
        maxTokens: json['maxTokens'] as int?,
        contextLength: json['contextLength'] as int?,
      );
}

/// Persisted generation preferences, keyed by model-profile key (`gemma4`,
/// `qwen35`). Only user-set values are stored; recommended defaults live in
/// the broker profiles and are applied at read time, never persisted.
final class GenerationSettings {
  const GenerationSettings({this.models = const {}});

  final Map<String, SamplingOverrides> models;

  SamplingOverrides overridesFor(String profileKey) =>
      models[profileKey] ?? const SamplingOverrides();

  GenerationSettings withModel(String profileKey, SamplingOverrides value) {
    final next = Map<String, SamplingOverrides>.from(models);
    if (value.isEmpty) {
      next.remove(profileKey);
    } else {
      next[profileKey] = value;
    }
    return GenerationSettings(models: next);
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'models': {
      for (final entry in models.entries)
        if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
    },
  };

  factory GenerationSettings.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported generation settings schema');
    }
    final rawModels = json['models'];
    return GenerationSettings(
      models: {
        if (rawModels is Map)
          for (final entry in rawModels.entries)
            if (entry.value is Map)
              entry.key as String: SamplingOverrides.fromJson(
                Map<String, Object?>.from(entry.value as Map),
              ),
      },
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
