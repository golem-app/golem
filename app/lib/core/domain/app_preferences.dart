import 'dart:convert';

import 'model_catalog.dart';
import 'model_profile_spec.dart';
import 'resolved_repository.dart';

enum ThemeSetting { system, light, dark }

/// Consumers clamp [AppPreferences.textScale] into this range: the store's
/// leaves stay tolerant, so a hand-edited file must never reach
/// TextScaler.linear with a negative or absurd factor.
const minTextScale = 0.85;
const maxTextScale = 1.3;

/// [balanced] means the model profile's own sampling defaults; the other two
/// map onto explicit values per profile (see `response_style_mapping.dart`).
enum ResponseStyle { precise, balanced, creative }

/// A hand-added Hugging Face repository (Advanced mode). The catalog entry it
/// becomes is derived from [resolved], and synthesized until resolution (#52).
final class CustomModelSpec {
  const CustomModelSpec({
    required this.repository,
    required this.engine,
    this.revision = 'main',
    this.profile,
    this.resolved,
  });

  final String repository;
  final ModelEngine engine;

  /// May be a moving branch or tag; never what is downloaded — see [resolved].
  final String revision;

  /// The broker profile this repository was proven to match, or null while
  /// unresolved — such an entry lists and deletes but refuses activation (#43).
  final ModelProfileSpec? profile;

  /// What [revision] actually pointed at, and the exact files it names (#52).
  /// Null is a first-class state, not a half-filled one.
  final ResolvedRepository? resolved;

  /// Stable catalog key. The hash suffix keeps names that differ only in
  /// punctuation (org/foo_bar vs org/foo-bar) from colliding on one slug.
  String get key {
    final slug = repository.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
    return 'custom-$slug-${_fnv32(repository).toRadixString(16).padLeft(8, '0')}';
  }

  static int _fnv32(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  String get displayName =>
      repository.contains('/') ? repository.split('/').last : repository;

  /// The derived catalog entry the UI and the downloader operate on. Without
  /// [resolved] it is synthesized with a deterministic size from the repository
  /// name, so the fake backend's goldens and journeys stay stable.
  ModelCatalogEntry toCatalogEntry() {
    final resolution = resolved;
    if (resolution != null) {
      return ModelCatalogEntry(
        key: key,
        displayName: resolution.displayName ?? displayName,
        engine: engine,
        quantization: resolution.quantization,
        repository: repository,
        // The commit, never the ref: an installed entry cannot be moved
        // underneath by a branch advancing.
        revision: resolution.commitSha,
        files: resolution.files,
        profileKey: profile?.key ?? unresolvedProfileKey,
        // No image capability: that needs a proven #18 path for this exact
        // artifact on this exact engine, which no custom entry has yet.
      );
    }
    // FNV-1a over the repository string: stable across runs and platforms.
    var hash = 0xcbf29ce484222325;
    for (final unit in '$repository@$revision'.codeUnits) {
      hash = ((hash ^ unit) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final bytes = 1200 * 1000 * 1000 + (hash % (2000 * 1000 * 1000));
    return ModelCatalogEntry(
      key: key,
      displayName: displayName,
      engine: engine,
      quantization: 'custom',
      repository: repository,
      revision: revision,
      // No hash: nothing was fetched, and '' would claim a published one.
      files: [ModelArtifactFile(path: 'weights.bin', bytes: bytes)],
      profileKey: profile?.key ?? unresolvedProfileKey,
    );
  }

  Map<String, Object?> toJson() => {
    'repository': repository,
    'engine': engine.name,
    if (revision != 'main') 'revision': revision,
    if (profile != null) 'profile': profile!.toJson(),
    if (resolved != null) 'resolved': resolved!.toJson(),
  };

  /// A stored profile or resolution that no longer parses is dropped rather
  /// than failing the whole file, and dropped independently of each other.
  factory CustomModelSpec.fromJson(Map<String, Object?> json) {
    final rawProfile = json['profile'];
    ModelProfileSpec? profile;
    if (rawProfile is Map) {
      try {
        profile = ModelProfileSpec.fromJson(
          Map<String, Object?>.from(rawProfile),
        );
      } on FormatException {
        profile = null;
      }
    }
    final rawResolved = json['resolved'];
    ResolvedRepository? resolved;
    if (rawResolved is Map) {
      try {
        resolved = ResolvedRepository.fromJson(
          Map<String, Object?>.from(rawResolved),
        );
      } on FormatException {
        resolved = null;
      }
    }
    return CustomModelSpec(
      repository: json['repository'] as String,
      engine: ModelEngine.values.byName(json['engine'] as String),
      revision: json['revision'] as String? ?? 'main',
      profile: profile,
      resolved: resolved,
    );
  }
}

/// App-wide user preferences. Sparse on disk — only non-default values are
/// written, so future default changes reach users who never touched a control.
/// Generation sampling overrides stay in [GenerationSettings].
final class AppPreferences {
  const AppPreferences({
    this.theme = ThemeSetting.system,
    this.textScale = 1.0,
    this.showMetrics = true,
    this.expandReasoning = false,
    this.hapticsOnSend = true,
    this.saveHistory = true,
    this.advancedMode = false,
    this.systemPrompt,
    this.responseStyles = const {},
    this.customModels = const [],
  });

  final ThemeSetting theme;
  final double textScale;
  final bool showMetrics;
  final bool expandReasoning;
  final bool hapticsOnSend;
  final bool saveHistory;
  final bool advancedMode;

  /// Null means the model's default behavior.
  final String? systemPrompt;

  final Map<String, ResponseStyle> responseStyles;

  final List<CustomModelSpec> customModels;

  ResponseStyle styleFor(String profileKey) =>
      responseStyles[profileKey] ?? ResponseStyle.balanced;

  AppPreferences copyWith({
    ThemeSetting? theme,
    double? textScale,
    bool? showMetrics,
    bool? expandReasoning,
    bool? hapticsOnSend,
    bool? saveHistory,
    bool? advancedMode,
    String? Function()? systemPrompt,
    Map<String, ResponseStyle>? responseStyles,
    List<CustomModelSpec>? customModels,
  }) => AppPreferences(
    theme: theme ?? this.theme,
    textScale: textScale ?? this.textScale,
    showMetrics: showMetrics ?? this.showMetrics,
    expandReasoning: expandReasoning ?? this.expandReasoning,
    hapticsOnSend: hapticsOnSend ?? this.hapticsOnSend,
    saveHistory: saveHistory ?? this.saveHistory,
    advancedMode: advancedMode ?? this.advancedMode,
    systemPrompt: systemPrompt == null ? this.systemPrompt : systemPrompt(),
    responseStyles: responseStyles ?? this.responseStyles,
    customModels: customModels ?? this.customModels,
  );

  AppPreferences withStyle(String profileKey, ResponseStyle style) {
    final next = Map<String, ResponseStyle>.from(responseStyles);
    if (style == ResponseStyle.balanced) {
      next.remove(profileKey);
    } else {
      next[profileKey] = style;
    }
    return copyWith(responseStyles: next);
  }

  AppPreferences withCustomModel(CustomModelSpec spec) => copyWith(
    customModels: [
      for (final item in customModels)
        if (item.key != spec.key) item,
      spec,
    ],
  );

  /// v2 added each custom repository's proven profile (#43), v3 its resolved
  /// commit and files (#52); both additive, so a v1 or v2 file loads as-is.
  static const schemaVersion = 3;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    if (theme != ThemeSetting.system) 'theme': theme.name,
    if (textScale != 1.0) 'textScale': textScale,
    if (!showMetrics) 'showMetrics': showMetrics,
    if (expandReasoning) 'expandReasoning': expandReasoning,
    if (!hapticsOnSend) 'hapticsOnSend': hapticsOnSend,
    if (!saveHistory) 'saveHistory': saveHistory,
    if (advancedMode) 'advancedMode': advancedMode,
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
    if (responseStyles.isNotEmpty)
      'responseStyles': {
        for (final entry in responseStyles.entries)
          if (entry.value != ResponseStyle.balanced)
            entry.key: entry.value.name,
      },
    if (customModels.isNotEmpty)
      'customModels': [for (final spec in customModels) spec.toJson()],
  };

  factory AppPreferences.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    // v1 and v2 are read directly: every version since has only added an
    // optional key inside a custom repository, so an older entry is unresolved.
    if (version != 1 && version != 2 && version != schemaVersion) {
      throw const FormatException('Unsupported app preferences schema');
    }
    final rawStyles = json['responseStyles'];
    final rawCustom = json['customModels'];
    return AppPreferences(
      theme: ThemeSetting.values.byName(
        json['theme'] as String? ?? ThemeSetting.system.name,
      ),
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
      showMetrics: json['showMetrics'] as bool? ?? true,
      expandReasoning: json['expandReasoning'] as bool? ?? false,
      hapticsOnSend: json['hapticsOnSend'] as bool? ?? true,
      saveHistory: json['saveHistory'] as bool? ?? true,
      advancedMode: json['advancedMode'] as bool? ?? false,
      systemPrompt: json['systemPrompt'] as String?,
      responseStyles: {
        if (rawStyles is Map)
          for (final entry in rawStyles.entries)
            entry.key as String: ResponseStyle.values.byName(
              entry.value as String,
            ),
      },
      customModels: [
        if (rawCustom is List)
          for (final item in rawCustom)
            if (item is Map)
              CustomModelSpec.fromJson(Map<String, Object?>.from(item)),
      ],
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
