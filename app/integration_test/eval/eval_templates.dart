import 'package:golem_flutter/broker/gemma4_chat_template.dart';

export 'package:golem_flutter/broker/gemma4_chat_template.dart'
    show ReasoningStreamDelta;

/// A model-specific streaming parser: splits raw engine text into reasoning
/// and answer channels exactly the way the app's broker does, so evaluation
/// scores what a user would actually see.
abstract interface class EvalStreamParser {
  ReasoningStreamDelta consume(String text);
  ReasoningStreamDelta finish();
}

/// Everything model-specific the harness needs to evaluate one model family:
/// prompt rendering, stop policy, and channel parsing. A future model plugs
/// into the harness by adding one entry to [evalTemplates].
abstract interface class EvalTemplate {
  String render(
    List<Map<String, String>> messages, {
    required bool reasoningEnabled,
  });
  List<String> get stopSequences;
  List<int> get stopTokenIds;
  EvalStreamParser newParser();
}

final class Gemma4EvalTemplate implements EvalTemplate {
  const Gemma4EvalTemplate();

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
  EvalStreamParser newParser() => _Gemma4StreamParser();
}

final class _Gemma4StreamParser implements EvalStreamParser {
  final ReasoningStreamParser _parser = ReasoningStreamParser();

  @override
  ReasoningStreamDelta consume(String text) => _parser.consume(text);

  @override
  ReasoningStreamDelta finish() => _parser.finish();
}

/// Registry keyed by the `GOLEM_EVAL_TEMPLATE` dart-define; `gemma4` is the
/// default.
const evalTemplates = <String, EvalTemplate>{'gemma4': Gemma4EvalTemplate()};
