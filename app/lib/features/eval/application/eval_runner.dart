import '../../../broker/runtime.dart';
import '../../../core/domain/generation_settings.dart';
import '../../../core/domain/models.dart';
import '../../../core/repositories/contracts.dart';
import '../domain/eval_spec.dart';

/// One artifact × engine cell of the evaluation matrix.
final class EvalCombo {
  const EvalCombo({
    required this.label,
    required this.path,
    required this.engine,
    this.profileKey,
  });

  final String label;
  final String path;
  final BrokerEngine engine;

  /// The broker profile this artifact must run under, when the combo knows
  /// its own identity (catalog installs do). Null for bare path defines,
  /// which carry no family — those fall back to the run's template.
  final String? profileKey;
}

final class EvalCheckResult {
  const EvalCheckResult({
    required this.description,
    required this.required,
    required this.passed,
  });

  final String description;
  final bool required;
  final bool passed;
}

final class EvalPromptResult {
  const EvalPromptResult({
    required this.promptId,
    this.answer = '',
    this.reasoning = '',
    this.stopReason,
    this.rawTextHash,
    this.rawTextLength = 0,
    this.metrics,
    this.checkResults = const [],
    this.error,
  });

  final String promptId;
  final String answer;
  final String reasoning;
  final String? stopReason;
  final String? rawTextHash;
  final int rawTextLength;
  final InferenceMetrics? metrics;
  final List<EvalCheckResult> checkResults;
  final String? error;

  bool get passed =>
      error == null &&
      checkResults.where((check) => check.required).every((c) => c.passed);
}

final class EvalComboResult {
  const EvalComboResult({
    required this.combo,
    required this.loadSeconds,
    required this.promptResults,
  });

  final EvalCombo combo;
  final double loadSeconds;
  final List<EvalPromptResult> promptResults;

  List<String> get failures => [
    for (final result in promptResults)
      if (result.error != null)
        '${result.promptId}: ${result.error}'
      else
        for (final check in result.checkResults)
          if (check.required && !check.passed)
            '${result.promptId}: failed ${check.description} '
                '(answer: ${result.answer})',
  ];
}

/// The single sampling seed a prompt set shares. The harness pins seeds at
/// repository construction (the app's own seed channel), so a spec mixing
/// seeds cannot be represented — refuse it loudly instead of mis-recording.
int uniformEvalSeed(List<EvalPrompt> prompts) {
  final seeds = prompts.map((prompt) => prompt.seed).toSet();
  if (seeds.length != 1) {
    throw StateError(
      'Eval prompts must share one seed; found ${seeds.join(', ')}.',
    );
  }
  return seeds.single;
}

/// Runs every prompt through the app's own [InferenceRepository], so template
/// rendering, sampling enforcement, reasoning parsing, and stop policy are
/// exactly what ships (#42). A failed generation becomes an error row and the
/// rest still run; a failed load propagates, because nothing after it could
/// mean anything.
Future<EvalComboResult> runEvalCombo({
  required InferenceRepository repository,
  required EvalCombo combo,
  required List<EvalPrompt> prompts,
  void Function(String message)? onProgress,
}) async {
  final loadWatch = Stopwatch()..start();
  await repository.prepare();
  loadWatch.stop();
  final results = <EvalPromptResult>[];
  for (final prompt in prompts) {
    onProgress?.call(
      '[${combo.label} · ${combo.engine.name}] ${prompt.id} '
      '(${results.length + 1}/${prompts.length})',
    );
    results.add(await _runPrompt(repository, prompt));
  }
  await repository.unload();
  return EvalComboResult(
    combo: combo,
    loadSeconds: loadWatch.elapsedMilliseconds / 1000,
    promptResults: results,
  );
}

Future<EvalPromptResult> _runPrompt(
  InferenceRepository repository,
  EvalPrompt prompt,
) async {
  final answer = StringBuffer();
  final reasoning = StringBuffer();
  InferenceMetrics? metrics;
  InferenceStopReason? stopReason;
  String? rawTextHash;
  var rawTextLength = 0;

  try {
    final events = repository.generate(
      context: [
        for (final message in prompt.messages)
          PromptMessage.text(message['role']!, message['content'] ?? ''),
      ],
      reasoningEnabled: prompt.reasoningEnabled,
      // Rides the same sparse-override channel user settings use; unset fields
      // fall to the profile's shipped mode-specific defaults, so the report
      // reflects app behavior.
      overrides: SamplingOverrides(
        maxTokens: prompt.maxTokens,
        temperature: prompt.temperature,
        topP: prompt.topP,
      ),
    );
    await for (final event in events) {
      switch (event) {
        case ReasoningDelta():
          reasoning.write(event.text);
        case AnswerDelta():
          answer.write(event.text);
        case AnswerResetEvent():
          answer.clear();
        case MetricsEvent():
          metrics = event.metrics;
        case CompletedEvent():
          stopReason = event.stopReason;
          rawTextHash = event.rawTextHash;
          rawTextLength = event.rawTextLength ?? 0;
      }
    }
  } on Exception catch (error) {
    return EvalPromptResult(promptId: prompt.id, error: '$error');
  }

  final answerText = answer.toString().trim();
  return EvalPromptResult(
    promptId: prompt.id,
    answer: answerText,
    reasoning: reasoning.toString().trim(),
    stopReason: stopReason?.name,
    rawTextHash: rawTextHash,
    rawTextLength: rawTextLength,
    metrics: metrics,
    checkResults: [
      for (final check in prompt.checks)
        EvalCheckResult(
          description: check.describe(),
          required: check.required,
          passed: check.passes(answerText),
        ),
      // Implicit on every prompt: a truncated answer can still satisfy its
      // content checks, so budget exhaustion must show up in the check list,
      // not only in the stop column. Evidence, not a gate.
      EvalCheckResult(
        description: 'stopped before the token budget [informational]',
        required: false,
        passed: stopReason != InferenceStopReason.maxTokens,
      ),
    ],
  );
}
