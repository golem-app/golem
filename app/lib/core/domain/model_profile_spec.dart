/// Serializable description of what a broker profile applies around a
/// model-blind engine. Core stays inference-package-free: the built-in Gemma
/// and Qwen values are assembled in `lib/broker/model_profile.dart`, and a
/// custom repository may persist one of these specs (#43).
///
/// The rendering *algorithms* are a closed set — a spec selects a proven
/// strategy and supplies its markers, and a template it cannot express is
/// rejected rather than guessed at (handbook v4.2A §5.1).
library;

/// Each maps to one broker implementation; the spec supplies its markers.
enum ChatTemplateStrategy {
  /// One leading BOS, `<|turn>role\n…<turn|>\n`, optional system turn.
  gemmaTurns,

  /// No BOS, `<|im_start|>role\n…<|im_end|>\n`, plus a generation primer.
  chatMl,
}

/// How a streamed generation is split into reasoning and answer channels.
enum ReasoningParserMode {
  none,

  /// Inline `<|channel>label\n … <channel|>` segments (Gemma).
  channels,

  /// `<think> … </think>` spans (Qwen/ChatML).
  thinkTags,
}

/// Reasoning is never fed back to the model; this is how it is stripped.
enum HistoryStripMode { none, reasoningChannels, thinkBlocks }

/// A *proven* input kind — data, never inferred from a display or file name.
enum ModelInputModality { text, image }

final class ProfileSampling {
  const ProfileSampling({
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    this.topK,
    this.contextLength = 8192,
    this.presencePenalty,
    this.pinned = false,
  });

  /// Roomy enough that reasoning cannot silently starve the visible answer;
  /// a budget stop is still surfaced by the repository, never swallowed.
  final int maxTokens;
  final double temperature;
  final double topP;

  /// Null keeps top-k filtering off — the recorded eval baselines and the
  /// determinism probe were measured without it.
  final int? topK;

  /// Null keeps the presence penalty out of the engine's chain. Set, it is a
  /// profile-level correctness knob (never user-overridable): the published
  /// Qwen 3.5 lever against quantized think loops (#80).
  final double? presencePenalty;

  /// Token budget over prompt plus generation. 8192 sits far under Gemma's
  /// trained context and Qwen's 256k paper context, but keeps worst-case KV
  /// memory in the low hundreds of megabytes on an 8 GB phone
  /// (docs/decisions/0003-flavor-backend-defaults.md).
  final int contextLength;

  /// True when this mode's sampling fields are a correctness constraint user
  /// overrides must not touch; token budgets stay overridable.
  final bool pinned;

  Map<String, Object?> toJson() => {
    'maxTokens': maxTokens,
    'temperature': temperature,
    'topP': topP,
    if (topK != null) 'topK': topK,
    'contextLength': contextLength,
    if (presencePenalty != null) 'presencePenalty': presencePenalty,
    if (pinned) 'pinned': true,
  };

  factory ProfileSampling.fromJson(Map<String, Object?> json) {
    final maxTokens = _requirePositiveInt(json['maxTokens'], 'maxTokens');
    final temperature = _requireDouble(json['temperature'], 'temperature');
    final topP = _requireDouble(json['topP'], 'topP');
    if (temperature < 0) {
      throw const FormatException('temperature must not be negative');
    }
    if (topP <= 0 || topP > 1) {
      throw const FormatException('topP must be in (0, 1]');
    }
    final rawTopK = json['topK'];
    final rawPenalty = json['presencePenalty'];
    final presencePenalty = rawPenalty == null
        ? null
        : _requireDouble(rawPenalty, 'presencePenalty');
    if (presencePenalty != null && presencePenalty <= 0) {
      throw const FormatException('presencePenalty must be positive');
    }
    return ProfileSampling(
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      topK: rawTopK == null ? null : _requirePositiveInt(rawTopK, 'topK'),
      contextLength: _requirePositiveInt(
        json['contextLength'] ?? 8192,
        'contextLength',
      ),
      presencePenalty: presencePenalty,
      pinned: json['pinned'] as bool? ?? false,
    );
  }
}

/// The markers and role names one [ChatTemplateStrategy] needs. Fields a
/// strategy does not use stay null; validation refuses a missing required one.
final class ChatTemplateSpec {
  const ChatTemplateSpec({
    required this.strategy,
    required this.turnOpen,
    required this.turnClose,
    required this.systemRole,
    required this.userRole,
    required this.assistantRole,
    required this.historyStrip,
    this.bos,
    this.thoughtControl,
    this.channelStart,
    this.channelEnd,
    this.thinkStart,
    this.thinkEnd,
    this.reasoningPrimer,
    this.directPrimer,
    this.mediaMarker,
  });

  final ChatTemplateStrategy strategy;

  /// Emitted exactly once at the head of the prompt, or null when the model
  /// expects none. Both engines disable automatic BOS insertion, so this string
  /// is the only BOS there is.
  final String? bos;

  final String turnOpen;
  final String turnClose;

  final String systemRole;
  final String userRole;
  final String assistantRole;

  /// In the synthesized system turn when reasoning is on (gemmaTurns only).
  final String? thoughtControl;

  /// Inline reasoning-channel delimiters ([ReasoningParserMode.channels]).
  final String? channelStart;
  final String? channelEnd;

  /// Reasoning block delimiters ([ReasoningParserMode.thinkTags]).
  final String? thinkStart;
  final String? thinkEnd;

  /// Appended after the assistant turn opens ([ChatTemplateStrategy.chatMl]).
  final String? reasoningPrimer;
  final String? directPrimer;

  /// The placeholder an engine replaces with one image's encoded tokens, at its
  /// position in the turn; null when there is no proven image path. Stripped
  /// from authored content, so pasted text cannot claim an empty image slot.
  final String? mediaMarker;

  final HistoryStripMode historyStrip;

  /// Every marker that must be stripped from authored content before rendering,
  /// so pasted text cannot close or forge a turn. The union of what the spec
  /// *declares*, not a per-strategy list: any marker this template can emit
  /// must be strippable, or declaring it hands users a forgeable token.
  /// Stripping runs to a fixpoint, so a marker spliced earlier cannot survive.
  List<String> get controlMarkers => [
    ?bos,
    turnOpen,
    turnClose,
    ?thoughtControl,
    ?channelStart,
    ?channelEnd,
    ?thinkStart,
    ?thinkEnd,
    ?mediaMarker,
  ];

  Map<String, Object?> toJson() => {
    'strategy': strategy.name,
    'turnOpen': turnOpen,
    'turnClose': turnClose,
    'systemRole': systemRole,
    'userRole': userRole,
    'assistantRole': assistantRole,
    'historyStrip': historyStrip.name,
    if (bos != null) 'bos': bos,
    if (thoughtControl != null) 'thoughtControl': thoughtControl,
    if (channelStart != null) 'channelStart': channelStart,
    if (channelEnd != null) 'channelEnd': channelEnd,
    if (thinkStart != null) 'thinkStart': thinkStart,
    if (thinkEnd != null) 'thinkEnd': thinkEnd,
    if (reasoningPrimer != null) 'reasoningPrimer': reasoningPrimer,
    if (directPrimer != null) 'directPrimer': directPrimer,
    if (mediaMarker != null) 'mediaMarker': mediaMarker,
  };

  factory ChatTemplateSpec.fromJson(Map<String, Object?> json) {
    final spec = ChatTemplateSpec(
      strategy: _requireEnum(
        ChatTemplateStrategy.values,
        json['strategy'],
        'strategy',
      ),
      turnOpen: _requireNonEmpty(json['turnOpen'], 'turnOpen'),
      turnClose: _requireNonEmpty(json['turnClose'], 'turnClose'),
      systemRole: _requireNonEmpty(json['systemRole'], 'systemRole'),
      userRole: _requireNonEmpty(json['userRole'], 'userRole'),
      assistantRole: _requireNonEmpty(json['assistantRole'], 'assistantRole'),
      historyStrip: _requireEnum(
        HistoryStripMode.values,
        json['historyStrip'],
        'historyStrip',
      ),
      bos: _optionalNonEmpty(json['bos'], 'bos'),
      thoughtControl: _optionalNonEmpty(
        json['thoughtControl'],
        'thoughtControl',
      ),
      channelStart: _optionalNonEmpty(json['channelStart'], 'channelStart'),
      channelEnd: _optionalNonEmpty(json['channelEnd'], 'channelEnd'),
      thinkStart: _optionalNonEmpty(json['thinkStart'], 'thinkStart'),
      thinkEnd: _optionalNonEmpty(json['thinkEnd'], 'thinkEnd'),
      reasoningPrimer: json['reasoningPrimer'] as String?,
      directPrimer: json['directPrimer'] as String?,
      mediaMarker: _optionalNonEmpty(json['mediaMarker'], 'mediaMarker'),
    );
    spec._validate();
    return spec;
  }

  /// Const construction cannot run this, so anything accepting a spec from
  /// outside the pinned set calls it explicitly ([ModelProfileSpec.validate]).
  void validate() => _validate();

  void _validate() {
    if (userRole == assistantRole) {
      throw const FormatException('userRole and assistantRole must differ');
    }
    switch (strategy) {
      case ChatTemplateStrategy.gemmaTurns:
        if (thoughtControl == null) {
          throw const FormatException('gemmaTurns requires thoughtControl');
        }
      case ChatTemplateStrategy.chatMl:
        if (reasoningPrimer == null || directPrimer == null) {
          throw const FormatException(
            'chatMl requires reasoningPrimer and directPrimer',
          );
        }
    }
    switch (historyStrip) {
      case HistoryStripMode.reasoningChannels:
        if (channelStart == null || channelEnd == null) {
          throw const FormatException(
            'reasoningChannels stripping requires channelStart and channelEnd',
          );
        }
      case HistoryStripMode.thinkBlocks:
        if (thinkStart == null || thinkEnd == null) {
          throw const FormatException(
            'thinkBlocks stripping requires thinkStart and thinkEnd',
          );
        }
      case HistoryStripMode.none:
        break;
    }
  }
}

final class ModelProfileSpec {
  const ModelProfileSpec({
    required this.key,
    required this.template,
    required this.parser,
    required this.stopSequences,
    required this.stopTokenIds,
    required this.reasoningSampling,
    required this.directSampling,
    this.inputModalities = const {ModelInputModality.text},
    this.imageTokenCost = 0,
  });

  /// Also the `GOLEM_MODEL_PROFILE` dart-define value for built-in profiles.
  final String key;

  final ChatTemplateSpec template;
  final ReasoningParserMode parser;

  /// Stop policy is the profile's, never the user's to override.
  final List<String> stopSequences;
  final List<int> stopTokenIds;

  final ProfileSampling reasoningSampling;
  final ProfileSampling directSampling;

  /// Declared, proven input kinds — only what has been validated (#18).
  final Set<ModelInputModality> inputModalities;

  /// Budget tokens one image costs. A vision encoder emits a fixed count per
  /// picture, unrelated to string length, so windowing must be told, not guess.
  final int imageTokenCost;

  bool get supportsImages => inputModalities.contains(ModelInputModality.image);

  ProfileSampling samplingFor({required bool reasoningEnabled}) =>
      reasoningEnabled ? reasoningSampling : directSampling;

  static const schemaVersion = 1;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'key': key,
    'template': template.toJson(),
    'parser': parser.name,
    'stopSequences': stopSequences,
    'stopTokenIds': stopTokenIds,
    'reasoningSampling': reasoningSampling.toJson(),
    'directSampling': directSampling.toJson(),
    'inputModalities': [
      for (final modality in ModelInputModality.values)
        if (inputModalities.contains(modality)) modality.name,
    ],
    if (imageTokenCost > 0) 'imageTokenCost': imageTokenCost,
  };

  /// For specs built by the const constructor; [fromJson] already validates.
  void validate() {
    template.validate();
    _validateParser(parser, template);
    if (supportsImages && template.mediaMarker == null) {
      throw const FormatException(
        'a template declaring image input must define mediaMarker',
      );
    }
    if (key.isEmpty) {
      throw const FormatException('key must be a non-empty string');
    }
    if (stopSequences.any((value) => value.isEmpty)) {
      throw const FormatException('stop sequences must not be empty');
    }
  }

  factory ModelProfileSpec.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported model profile schema');
    }
    final rawStops = json['stopSequences'];
    final rawStopIds = json['stopTokenIds'];
    final rawModalities = json['inputModalities'];
    if (rawStops is! List || rawStopIds is! List) {
      throw const FormatException(
        'stopSequences and stopTokenIds are required',
      );
    }
    // Checked so a malformed profile always surfaces as a FormatException: a
    // raw TypeError would escape the caller's guard and quarantine preferences.
    final rawTemplate = json['template'];
    final rawReasoning = json['reasoningSampling'];
    final rawDirect = json['directSampling'];
    if (rawTemplate is! Map || rawReasoning is! Map || rawDirect is! Map) {
      throw const FormatException(
        'template, reasoningSampling and directSampling are required objects',
      );
    }
    final modalities = <ModelInputModality>{
      if (rawModalities is List)
        for (final value in rawModalities)
          _requireEnum(ModelInputModality.values, value, 'inputModalities'),
    };
    if (modalities.isEmpty) modalities.add(ModelInputModality.text);
    final parser = _requireEnum(
      ReasoningParserMode.values,
      json['parser'],
      'parser',
    );
    final template = ChatTemplateSpec.fromJson(
      Map<String, Object?>.from(rawTemplate),
    );
    _validateParser(parser, template);
    if (modalities.contains(ModelInputModality.image) &&
        template.mediaMarker == null) {
      throw const FormatException(
        'a template declaring image input must define mediaMarker',
      );
    }
    return ModelProfileSpec(
      key: _requireNonEmpty(json['key'], 'key'),
      template: template,
      parser: parser,
      stopSequences: [
        for (final value in rawStops)
          _requireNonEmpty(value, 'stopSequences entry'),
      ],
      stopTokenIds: [
        for (final value in rawStopIds)
          if (value is int)
            value
          else
            throw const FormatException('stopTokenIds must be integers'),
      ],
      reasoningSampling: ProfileSampling.fromJson(
        Map<String, Object?>.from(rawReasoning),
      ),
      directSampling: ProfileSampling.fromJson(
        Map<String, Object?>.from(rawDirect),
      ),
      inputModalities: modalities,
      imageTokenCost: json['imageTokenCost'] == null
          ? 0
          : _requirePositiveInt(json['imageTokenCost'], 'imageTokenCost'),
    );
  }

  static void _validateParser(
    ReasoningParserMode parser,
    ChatTemplateSpec template,
  ) {
    switch (parser) {
      case ReasoningParserMode.channels:
        if (template.channelStart == null || template.channelEnd == null) {
          throw const FormatException(
            'channels parsing requires channelStart and channelEnd',
          );
        }
      case ReasoningParserMode.thinkTags:
        if (template.thinkStart == null || template.thinkEnd == null) {
          throw const FormatException(
            'thinkTags parsing requires thinkStart and thinkEnd',
          );
        }
      case ReasoningParserMode.none:
        break;
    }
  }
}

T _requireEnum<T extends Enum>(List<T> values, Object? raw, String field) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw FormatException('Unsupported $field: $raw');
}

String _requireNonEmpty(Object? raw, String field) {
  if (raw is String && raw.isNotEmpty) return raw;
  throw FormatException('$field must be a non-empty string');
}

String? _optionalNonEmpty(Object? raw, String field) {
  if (raw == null) return null;
  return _requireNonEmpty(raw, field);
}

int _requirePositiveInt(Object? raw, String field) {
  if (raw is int && raw > 0) return raw;
  throw FormatException('$field must be a positive integer');
}

double _requireDouble(Object? raw, String field) {
  if (raw is num) return raw.toDouble();
  throw FormatException('$field must be a number');
}
