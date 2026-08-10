import '../core/domain/model_catalog.dart' show unresolvedProfileKey;
import '../core/domain/model_profile_spec.dart';
import 'gemma4_chat_template.dart';
import 'qwen35_chat_template.dart';

export '../core/domain/model_profile_spec.dart'
    show
        ChatTemplateSpec,
        ChatTemplateStrategy,
        HistoryStripMode,
        ModelInputModality,
        ModelProfileSpec,
        ProfileSampling,
        ReasoningParserMode;
export 'gemma4_chat_template.dart' show ReasoningStreamDelta;

/// A model-specific streaming parser: splits raw engine text into reasoning
/// and answer channels for one generation. Stateful; create one per
/// generation via [ModelProfile.newParser].
abstract interface class BrokerStreamParser {
  ReasoningStreamDelta consume(String text);
  ReasoningStreamDelta finish();
}

/// Everything model-specific the broker applies around a model-blind engine:
/// chat-template rendering, stop policy, sampling defaults, and
/// reasoning-channel parsing. Engines never see any of this — they receive
/// fully rendered prompts and explicit stop tokens per the Inferno boundary.
abstract interface class ModelProfile {
  /// Registry key, also the `GOLEM_MODEL_PROFILE` dart-define value.
  String get key;

  String render(
    List<Map<String, String>> messages, {
    required bool reasoningEnabled,
  });

  List<String> get stopSequences;
  List<int> get stopTokenIds;

  /// Sampling can legitimately differ by reasoning mode: Qwen's family
  /// guidance publishes distinct thinking and non-thinking settings, and
  /// off-spec thinking sampling produces endless-think repetition loops.
  ProfileSampling sampling({required bool reasoningEnabled});

  BrokerStreamParser newParser({required bool reasoningEnabled});

  /// The data this profile was built from. Built-in profiles carry a pinned
  /// spec; a supported custom repository persists one (#43).
  ModelProfileSpec get spec;
}

/// A profile assembled entirely from [ModelProfileSpec] data.
///
/// The rendering and parsing *algorithms* stay a closed set of proven
/// implementations; the spec supplies their markers, role names, stop policy,
/// and sampling. That is what lets a supported custom repository be activated
/// without new engine or broker code, while a template that cannot be
/// expressed this way is rejected rather than approximated.
base class DataModelProfile implements ModelProfile {
  const DataModelProfile(this.spec);

  @override
  final ModelProfileSpec spec;

  @override
  String get key => spec.key;

  @override
  String render(
    List<Map<String, String>> messages, {
    required bool reasoningEnabled,
  }) => switch (spec.template.strategy) {
    ChatTemplateStrategy.gemmaTurns => Gemma4ChatTemplate.render(
      messages,
      reasoningEnabled: reasoningEnabled,
      spec: spec.template,
    ),
    ChatTemplateStrategy.chatMl => Qwen35ChatTemplate.render(
      messages,
      reasoningEnabled: reasoningEnabled,
      spec: spec.template,
    ),
  };

  @override
  List<String> get stopSequences => spec.stopSequences;

  @override
  List<int> get stopTokenIds => spec.stopTokenIds;

  @override
  ProfileSampling sampling({required bool reasoningEnabled}) =>
      spec.samplingFor(reasoningEnabled: reasoningEnabled);

  @override
  BrokerStreamParser newParser({required bool reasoningEnabled}) =>
      switch (spec.parser) {
        ReasoningParserMode.channels => _ChannelParser(spec.template),
        ReasoningParserMode.thinkTags => _ThinkTagParser(
          spec.template,
          reasoningEnabled: reasoningEnabled,
        ),
        ReasoningParserMode.none => _VisibleOnlyParser(),
      };
}

final class _ChannelParser implements BrokerStreamParser {
  _ChannelParser(ChatTemplateSpec template)
    : _parser = ReasoningStreamParser(
        openMarker: template.channelStart ?? ReasoningStreamParser.channelStart,
        closeMarker: template.channelEnd ?? ReasoningStreamParser.channelEnd,
      );

  final ReasoningStreamParser _parser;

  @override
  ReasoningStreamDelta consume(String text) => _parser.consume(text);

  @override
  ReasoningStreamDelta finish() => _parser.finish();
}

final class _ThinkTagParser implements BrokerStreamParser {
  _ThinkTagParser(ChatTemplateSpec template, {required bool reasoningEnabled})
    : _parser = Qwen35StreamParser(
        reasoningEnabled: reasoningEnabled,
        openMarker: template.thinkStart ?? Qwen35ChatTemplate.thinkStart,
        closeMarker: template.thinkEnd ?? Qwen35ChatTemplate.thinkEnd,
      );

  final Qwen35StreamParser _parser;

  @override
  ReasoningStreamDelta consume(String text) => _parser.consume(text);

  @override
  ReasoningStreamDelta finish() => _parser.finish();
}

/// Everything the engine emits is the visible answer. Used by profiles that
/// declare no reasoning channel at all.
final class _VisibleOnlyParser implements BrokerStreamParser {
  @override
  ReasoningStreamDelta consume(String text) =>
      ReasoningStreamDelta(answer: text);

  @override
  ReasoningStreamDelta finish() => const ReasoningStreamDelta();
}

/// The pinned Gemma 4 profile.
const gemma4ProfileSpec = ModelProfileSpec(
  key: 'gemma4',
  template: gemma4TemplateSpec,
  parser: ReasoningParserMode.channels,
  stopSequences: [Gemma4ChatTemplate.turnEnd],
  stopTokenIds: [
    Gemma4ChatTemplate.eosTokenId,
    Gemma4ChatTemplate.turnEndTokenId,
  ],
  // Gemma's sampling is mode-independent.
  reasoningSampling: ProfileSampling(
    maxTokens: 2048,
    temperature: 1,
    topP: 0.95,
  ),
  directSampling: ProfileSampling(maxTokens: 2048, temperature: 1, topP: 0.95),
);

/// The pinned Qwen 3.5 profile.
///
/// The pinned repository publishes no sampling recommendation
/// (generation_config carries only eos ids), so these are the Qwen3-family
/// published mode-specific defaults. The split matters: thinking sampled at
/// the non-thinking settings looped mid-think until the token budget on the
/// Q4_0 build during the #33 bring-up (docs/evals, 2026-08-05, records the
/// fixed configuration passing). Qwen's thinking also runs far longer than
/// Gemma's reasoning channel, hence the 4096 budget. Thinking-mode sampling
/// is pinned: overriding it reintroduces that endless-think repetition loop.
const qwen35ProfileSpec = ModelProfileSpec(
  key: 'qwen35',
  template: qwen35TemplateSpec,
  parser: ReasoningParserMode.thinkTags,
  stopSequences: [Qwen35ChatTemplate.imEnd],
  stopTokenIds: [
    Qwen35ChatTemplate.imEndTokenId,
    Qwen35ChatTemplate.endOfTextTokenId,
  ],
  reasoningSampling: ProfileSampling(
    maxTokens: 4096,
    temperature: 0.6,
    topP: 0.95,
    pinned: true,
  ),
  directSampling: ProfileSampling(maxTokens: 2048, temperature: 0.7, topP: 0.8),
);

/// Named aliases for the two pinned profiles. They are ordinary data-backed
/// profiles; the classes exist so call sites and tests can name them.
final class Gemma4Profile extends DataModelProfile {
  const Gemma4Profile() : super(gemma4ProfileSpec);
}

final class Qwen35Profile extends DataModelProfile {
  const Qwen35Profile() : super(qwen35ProfileSpec);
}

/// Built-in profiles selectable via the `GOLEM_MODEL_PROFILE` dart-define;
/// `gemma4` is the default. Custom repositories never enter this map — they
/// are resolved through a [ProfileRegistry] carrying their persisted spec.
final Map<String, ModelProfile> modelProfiles = Map.unmodifiable({
  'gemma4': const Gemma4Profile(),
  'qwen35': const Qwen35Profile(),
});

/// An immutable profile lookup: the built-ins plus any specs a resolved
/// custom model brought with it.
///
/// Deliberately a value passed to the resolver rather than a mutable global —
/// app-authored mutable static singletons are prohibited (handbook v4.2A
/// §2.1). Composition decides which registry a build resolves against.
final class ProfileRegistry {
  const ProfileRegistry._(this._profiles);

  /// The two pinned profiles and nothing else.
  static final ProfileRegistry builtIn = ProfileRegistry._(modelProfiles);

  final Map<String, ModelProfile> _profiles;

  /// A registry extended with custom specs.
  ///
  /// Each spec is validated here because the const constructor cannot: a spec
  /// reaching a renderer half-described would silently fall back to another
  /// model's markers. Keys are rejected when they collide with a built-in, with
  /// the unresolved sentinel, or with another spec in the same call — any of
  /// which would let one custom repository answer for another.
  ProfileRegistry withSpecs(Iterable<ModelProfileSpec> specs) {
    if (specs.isEmpty) return this;
    final next = Map<String, ModelProfile>.from(_profiles);
    for (final spec in specs) {
      spec.validate();
      if (modelProfiles.containsKey(spec.key)) {
        throw ArgumentError.value(
          spec.key,
          'spec.key',
          'collides with a built-in profile',
        );
      }
      if (spec.key == unresolvedProfileKey) {
        throw ArgumentError.value(
          spec.key,
          'spec.key',
          'is reserved for entries with no resolved profile',
        );
      }
      if (next.containsKey(spec.key)) {
        throw ArgumentError.value(
          spec.key,
          'spec.key',
          'is already registered',
        );
      }
      next[spec.key] = DataModelProfile(spec);
    }
    return ProfileRegistry._(Map.unmodifiable(next));
  }

  ModelProfile? operator [](String key) => _profiles[key];

  Iterable<String> get keys => _profiles.keys;
}
