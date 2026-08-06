import 'dart:convert';

import 'model_catalog.dart';

/// The user's theme choice; [system] follows the platform brightness.
enum ThemeSetting { system, light, dark }

/// Bounds the appearance slider enforces. The store's leaves stay
/// deliberately tolerant, so every consumer of [AppPreferences.textScale]
/// clamps into this range — a hand-edited file must never reach
/// TextScaler.linear with a negative or absurd factor.
const minTextScale = 0.85;
const maxTextScale = 1.3;

/// How much room the model gets to improvise. [balanced] means the model
/// profile's own defaults; the other two map onto explicit sampling values
/// per profile (see `response_style_mapping.dart`).
enum ResponseStyle { precise, balanced, creative }

/// A hand-added Hugging Face repository (Advanced mode). Pure data: the
/// catalog entry it becomes is derived, and real download wiring for
/// arbitrary repositories stays with #20.
final class CustomModelSpec {
  const CustomModelSpec({
    required this.repository,
    required this.engine,
    this.revision = 'main',
  });

  final String repository;
  final ModelEngine engine;
  final String revision;

  /// Stable catalog key derived from the repository name. The hash
  /// suffix keeps repositories whose names differ only in punctuation
  /// (org/foo_bar vs org/foo-bar) from colliding on one slug and
  /// silently replacing each other's card and download state.
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

  /// The repository tail, as the display name ("mlx-community/foo" → "foo").
  String get displayName =>
      repository.contains('/') ? repository.split('/').last : repository;

  /// The derived catalog entry the UI and the fake downloader operate on.
  /// The size is a deterministic synthesis from the repository name (1.2 to
  /// about 3.2 decimal GB) — nothing was fetched, so nothing real is known;
  /// stability matters more than truth for goldens and journeys, and the
  /// real wiring arrives with #20.
  ModelCatalogEntry toCatalogEntry() {
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
      files: [ModelArtifactFile(path: 'weights.bin', bytes: bytes, sha256: '')],
    );
  }

  Map<String, Object?> toJson() => {
    'repository': repository,
    'engine': engine.name,
    if (revision != 'main') 'revision': revision,
  };

  factory CustomModelSpec.fromJson(Map<String, Object?> json) =>
      CustomModelSpec(
        repository: json['repository'] as String,
        engine: ModelEngine.values.byName(json['engine'] as String),
        revision: json['revision'] as String? ?? 'main',
      );
}

/// App-wide user preferences: appearance, transcript behavior, privacy,
/// Advanced mode, response styles, and hand-added repositories. Sparse on
/// disk — only non-default values are written, so future default changes
/// reach users who never touched a control. Generation sampling overrides
/// stay in [GenerationSettings]; this file never duplicates them.
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

  /// Custom system prompt; null means the model's default behavior.
  final String? systemPrompt;

  /// Per-profile response style; absent means [ResponseStyle.balanced].
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

  /// Balanced entries are removed, keeping the persisted map sparse.
  AppPreferences withStyle(String profileKey, ResponseStyle style) {
    final next = Map<String, ResponseStyle>.from(responseStyles);
    if (style == ResponseStyle.balanced) {
      next.remove(profileKey);
    } else {
      next[profileKey] = style;
    }
    return copyWith(responseStyles: next);
  }

  /// Appends a custom repository; a re-add of the same derived key replaces
  /// the earlier spec instead of duplicating the card.
  AppPreferences withCustomModel(CustomModelSpec spec) => copyWith(
    customModels: [
      for (final item in customModels)
        if (item.key != spec.key) item,
      spec,
    ],
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
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
    if (json['schemaVersion'] != 1) {
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
