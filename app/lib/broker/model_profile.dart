import '../core/domain/model_catalog.dart' show unresolvedProfileKey;
import '../core/domain/model_profile_spec.dart';
import '../core/domain/models.dart';
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

/// Stateful; create one per generation via [ModelProfile.newParser].
abstract interface class BrokerStreamParser {
  ReasoningStreamDelta consume(String text);
  ReasoningStreamDelta finish();
}

/// Everything model-specific the broker applies around a model-blind engine.
/// Engines see none of it — only rendered prompts and explicit stop tokens.
abstract interface class ModelProfile {
  /// Registry key, also the `GOLEM_MODEL_PROFILE` dart-define value.
  String get key;

  String render(List<PromptMessage> messages, {required bool reasoningEnabled});

  List<String> get stopSequences;
  List<int> get stopTokenIds;

  /// Sampling legitimately differs by mode: Qwen publishes distinct thinking and
  /// non-thinking settings, and off-spec thinking sampling loops endlessly.
  ProfileSampling sampling({required bool reasoningEnabled});

  BrokerStreamParser newParser({required bool reasoningEnabled});

  /// Built-in profiles pin a spec; a custom repository persists one (#43).
  ModelProfileSpec get spec;
}

/// A profile assembled from [ModelProfileSpec] data. The algorithms stay a
/// closed set of proven implementations; the spec supplies only their markers,
/// roles, stop policy, and sampling — so a custom repository activates without
/// new code, and an inexpressible template is rejected, not approximated.
base class DataModelProfile implements ModelProfile {
  const DataModelProfile(this.spec);

  @override
  final ModelProfileSpec spec;

  @override
  String get key => spec.key;

  @override
  String render(
    List<PromptMessage> messages, {
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

/// For profiles that declare no reasoning channel: everything is the answer.
final class _VisibleOnlyParser implements BrokerStreamParser {
  @override
  ReasoningStreamDelta consume(String text) =>
      ReasoningStreamDelta(answer: text);

  @override
  ReasoningStreamDelta finish() => const ReasoningStreamDelta();
}

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
  // The template can express images; whether an artifact accepts one is the
  // catalog entry's call (#18).
  inputModalities: {ModelInputModality.text, ModelInputModality.image},
  // Gemma 4 tiles images dynamically, so there is no fixed token count: the
  // #18 bake-off measured 84–130 across the graded fixtures. Reserve
  // conservatively above that rather than trip the engine's own check.
  imageTokenCost: 256,
);

/// The pinned repository publishes no sampling recommendation
/// (generation_config carries only eos ids), so these are the Qwen3-family
/// published mode-specific defaults. The split matters: thinking sampled at the
/// non-thinking settings looped mid-think until the token budget on the Q4_0
/// build during the #33 bring-up (docs/evals, 2026-08-05 records the fix
/// passing). Thinking runs far longer than Gemma's channel, hence 4096, and is
/// pinned because overriding it revives that loop.
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
  // Both pinned MLX snapshots carry the vision tower and processor; artifact
  // capability is still the catalog's call, per-artifact.
  inputModalities: {ModelInputModality.text, ModelInputModality.image},
  // MLX caps Qwen at 262,144 pixels while GGUF takes the app's one-megapixel
  // ceiling: reserve the cross-engine worst case rather than undercount.
  imageTokenCost: 1280,
);

/// Aliases so call sites and tests can name the two pinned profiles.
final class Gemma4Profile extends DataModelProfile {
  const Gemma4Profile() : super(gemma4ProfileSpec);
}

final class Qwen35Profile extends DataModelProfile {
  const Qwen35Profile() : super(qwen35ProfileSpec);
}

/// Built-in profiles selectable via `GOLEM_MODEL_PROFILE`. Custom repositories
/// never enter this map — they arrive through a [ProfileRegistry].
final Map<String, ModelProfile> modelProfiles = Map.unmodifiable({
  'gemma4': const Gemma4Profile(),
  'qwen35': const Qwen35Profile(),
});

/// The built-ins plus any specs a resolved custom model brought with it.
/// Deliberately a value passed to the resolver, not a mutable global (handbook
/// v4.2A §2.1 prohibits app-authored mutable statics).
final class ProfileRegistry {
  const ProfileRegistry._(this._profiles);

  static final ProfileRegistry builtIn = ProfileRegistry._(modelProfiles);

  final Map<String, ModelProfile> _profiles;

  /// Each spec is validated here because the const constructor cannot: a
  /// half-described spec would silently fall back to another model's markers,
  /// and a colliding key would let one custom repository answer for another.
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
