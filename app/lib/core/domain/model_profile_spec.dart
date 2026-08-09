/// Serializable description of everything a broker profile applies around a
/// model-blind engine: chat-template rendering, stop policy, sampling
/// defaults, reasoning parsing, and declared input capabilities.
///
/// Core stays inference-package-free. The built-in Gemma and Qwen values are
/// assembled in `lib/broker/model_profile.dart`; a custom repository may
/// persist one of these specs so a downloaded model can be activated without
/// changing engine code (#43).
///
/// The rendering *algorithms* are deliberately a closed set. A spec selects a
/// proven strategy and supplies its markers; it never describes a new one.
/// A repository whose template cannot be expressed this way is rejected
/// rather than guessed at — see handbook v4.2A §5.1.
library;

/// The proven chat-template algorithms. Each maps to one implementation in
/// the broker; the spec supplies that implementation's markers and role names.
enum ChatTemplateStrategy {
  /// Gemma-style turns: a single leading BOS, `<|turn>role\n…<turn|>\n`, and
  /// an optional synthesized system turn carrying the thought control.
  gemmaTurns,

  /// ChatML turns: no BOS, `<|im_start|>role\n…<|im_end|>\n`, and a
  /// generation primer that opens or closes a reasoning block.
  chatMl,
}

/// How a streamed generation is split into reasoning and answer channels.
enum ReasoningParserMode {
  /// Everything the engine emits is the visible answer.
  none,

  /// Inline `<|channel>label\n … <channel|>` segments (Gemma).
  channels,

  /// `<think> … </think>` spans (Qwen/ChatML).
  thinkTags,
}

/// How an assistant turn already in the transcript is cleaned before it is
/// rendered back into the prompt. Reasoning is never fed back to the model.
enum HistoryStripMode { none, reasoningChannels, thinkBlocks }

/// An input kind a model/engine/artifact path has been *proven* to accept.
/// Capability is data, never inferred from a display name or file name.
enum ModelInputModality { text, image }

/// A model's default sampling policy for one reasoning mode.
final class ProfileSampling {
  const ProfileSampling({
    required this.maxTokens,
    required this.temperature,
    required this.topP,
    this.topK,
    this.contextLength = 8192,
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

  /// On-device token budget over prompt plus generation. 8192 sits far
  /// under Gemma's trained context and Qwen's 256k paper context but keeps
  /// worst-case KV memory in the low hundreds of megabytes on an 8 GB
  /// phone (rationale: docs/decisions/0003-flavor-backend-defaults.md).
  final int contextLength;

  /// True when this mode's sampling fields (temperature/topP/topK) are a
  /// correctness constraint user overrides must not touch; token budgets
  /// stay overridable. See the Qwen thinking-mode spec.
  final bool pinned;

  Map<String, Object?> toJson() => {
    'maxTokens': maxTokens,
    'temperature': temperature,
    'topP': topP,
    if (topK != null) 'topK': topK,
    'contextLength': contextLength,
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
    return ProfileSampling(
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      topK: rawTopK == null ? null : _requirePositiveInt(rawTopK, 'topK'),
      contextLength: _requirePositiveInt(
        json['contextLength'] ?? 8192,
        'contextLength',
      ),
      pinned: json['pinned'] as bool? ?? false,
    );
  }
}

/// The markers and role names one [ChatTemplateStrategy] needs.
///
/// Fields a strategy does not use stay null. Validation refuses a spec whose
/// strategy is missing a marker it requires, so a half-described template can
/// never reach an engine.
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
  });

  final ChatTemplateStrategy strategy;

  /// Emitted exactly once at the head of the prompt, or null when the model
  /// expects no literal BOS. Both engines tokenize with automatic BOS
  /// insertion disabled, so this string is the only BOS there is.
  final String? bos;

  final String turnOpen;
  final String turnClose;

  final String systemRole;
  final String userRole;
  final String assistantRole;

  /// Written inside the synthesized system turn when reasoning is enabled
  /// ([ChatTemplateStrategy.gemmaTurns] only).
  final String? thoughtControl;

  /// Inline reasoning-channel delimiters ([ReasoningParserMode.channels]).
  final String? channelStart;
  final String? channelEnd;

  /// Reasoning block delimiters ([ReasoningParserMode.thinkTags]).
  final String? thinkStart;
  final String? thinkEnd;

  /// Appended after the assistant turn is opened, per reasoning mode
  /// ([ChatTemplateStrategy.chatMl]). Null means nothing is appended.
  final String? reasoningPrimer;
  final String? directPrimer;

  final HistoryStripMode historyStrip;

  /// Every marker that must be stripped from user- or model-authored content
  /// before it is rendered, so pasted text cannot close a turn or forge one.
  ///
  /// This is the union of every marker the spec *declares*, not a per-strategy
  /// list: any marker this template can emit must also be strippable from
  /// content, or a spec that declares it hands users a forgeable token. For
  /// the two pinned specs the union reproduces the exact lists (and order) the
  /// hand-written implementations used. Stripping runs to a fixpoint, so a
  /// marker spliced together by an earlier removal cannot survive.
  List<String> get controlMarkers => [
    ?bos,
    turnOpen,
    turnClose,
    ?thoughtControl,
    ?channelStart,
    ?channelEnd,
    ?thinkStart,
    ?thinkEnd,
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
    );
    spec._validate();
    return spec;
  }

  /// Refuses a spec whose strategy or history-strip mode needs a marker the
  /// spec does not carry, and one whose role names collide (which would make
  /// an assistant turn indistinguishable from a user turn).
  ///
  /// Const construction cannot run this, so anything that accepts a spec from
  /// outside the pinned set calls it explicitly (see [ModelProfileSpec.validate]).
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

/// One complete, serializable broker profile.
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
  });

  /// Registry key, also the `GOLEM_MODEL_PROFILE` dart-define value for
  /// built-in profiles.
  final String key;

  final ChatTemplateSpec template;
  final ReasoningParserMode parser;

  /// Stop policy is the profile's, never the user's to override.
  final List<String> stopSequences;
  final List<int> stopTokenIds;

  final ProfileSampling reasoningSampling;
  final ProfileSampling directSampling;

  /// Declared, proven input kinds. Image transport and native execution are
  /// separate work (#18); this field only records what has been validated.
  final Set<ModelInputModality> inputModalities;

  bool get supportsImages => inputModalities.contains(ModelInputModality.image);

  ProfileSampling samplingFor({required bool reasoningEnabled}) =>
      reasoningEnabled ? reasoningSampling : directSampling;

  /// Bumped only when a persisted spec's shape changes incompatibly.
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
  };

  /// Validates an instance built by the const constructor. [fromJson] already
  /// validates; this is for specs that arrive any other way.
  void validate() {
    template.validate();
    _validateParser(parser, template);
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
    // Every nested object is checked here so a malformed profile always
    // surfaces as a FormatException. A raw TypeError would escape the
    // caller's guard and quarantine the whole preferences file.
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
