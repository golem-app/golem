import 'gemma4_chat_template.dart';
import 'qwen35_chat_template.dart';

export 'gemma4_chat_template.dart' show ReasoningStreamDelta;

/// A model-specific streaming parser: splits raw engine text into reasoning
/// and answer channels for one generation. Stateful; create one per
/// generation via [ModelProfile.newParser].
abstract interface class BrokerStreamParser {
  ReasoningStreamDelta consume(String text);
  ReasoningStreamDelta finish();
}

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
  /// stay overridable. See Qwen35Profile.sampling.
  final bool pinned;
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
}

final class Gemma4Profile implements ModelProfile {
  const Gemma4Profile();

  @override
  String get key => 'gemma4';

  @override
  String render(
    List<Map<String, String>> messages, {
    required bool reasoningEnabled,
  }) => Gemma4ChatTemplate.render(messages, reasoningEnabled: reasoningEnabled);

  @override
  List<String> get stopSequences => const [Gemma4ChatTemplate.turnEnd];

  @override
  List<int> get stopTokenIds => const [
    Gemma4ChatTemplate.eosTokenId,
    Gemma4ChatTemplate.turnEndTokenId,
  ];

  @override
  ProfileSampling sampling({required bool reasoningEnabled}) =>
      const ProfileSampling(maxTokens: 2048, temperature: 1, topP: 0.95);

  /// Gemma's channel markers are inline in the stream, so the parser does
  /// not depend on whether reasoning was requested.
  @override
  BrokerStreamParser newParser({required bool reasoningEnabled}) =>
      _Gemma4Parser();
}

final class _Gemma4Parser implements BrokerStreamParser {
  final ReasoningStreamParser _parser = ReasoningStreamParser();

  @override
  ReasoningStreamDelta consume(String text) => _parser.consume(text);

  @override
  ReasoningStreamDelta finish() => _parser.finish();
}

final class Qwen35Profile implements ModelProfile {
  const Qwen35Profile();

  @override
  String get key => 'qwen35';

  @override
  String render(
    List<Map<String, String>> messages, {
    required bool reasoningEnabled,
  }) => Qwen35ChatTemplate.render(messages, reasoningEnabled: reasoningEnabled);

  @override
  List<String> get stopSequences => const [Qwen35ChatTemplate.imEnd];

  @override
  List<int> get stopTokenIds => const [
    Qwen35ChatTemplate.imEndTokenId,
    Qwen35ChatTemplate.endOfTextTokenId,
  ];

  // The pinned repository publishes no sampling recommendation
  // (generation_config carries only eos ids), so these are the Qwen3-family
  // published mode-specific defaults. The split matters: thinking sampled
  // at the non-thinking settings loops mid-think until the token budget on
  // the Q4_0 build (docs/evals evidence, 2026-08-05). Qwen's thinking also
  // runs far longer than Gemma's reasoning channel, hence the 4096 budget.
  // Thinking-mode sampling is pinned: overriding it reintroduces the
  // endless-think repetition loop recorded in docs/evals (2026-08-05).
  @override
  ProfileSampling sampling({required bool reasoningEnabled}) => reasoningEnabled
      ? const ProfileSampling(
          maxTokens: 4096,
          temperature: 0.6,
          topP: 0.95,
          pinned: true,
        )
      : const ProfileSampling(maxTokens: 2048, temperature: 0.7, topP: 0.8);

  /// Qwen's primer decides the starting channel, so the parser must know
  /// whether reasoning was requested.
  @override
  BrokerStreamParser newParser({required bool reasoningEnabled}) =>
      _Qwen35Parser(reasoningEnabled: reasoningEnabled);
}

final class _Qwen35Parser implements BrokerStreamParser {
  _Qwen35Parser({required bool reasoningEnabled})
    : _parser = Qwen35StreamParser(reasoningEnabled: reasoningEnabled);

  final Qwen35StreamParser _parser;

  @override
  ReasoningStreamDelta consume(String text) => _parser.consume(text);

  @override
  ReasoningStreamDelta finish() => _parser.finish();
}

/// Profiles selectable via the `GOLEM_MODEL_PROFILE` dart-define; `gemma4`
/// is the default.
const modelProfiles = <String, ModelProfile>{
  'gemma4': Gemma4Profile(),
  'qwen35': Qwen35Profile(),
};
