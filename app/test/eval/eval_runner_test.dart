import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/hash.dart';
import 'package:golem_flutter/broker/inferno_inference_repository.dart';
import 'package:golem_flutter/broker/runtime.dart';

import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/features/eval/application/eval_runner.dart';
import 'package:golem_flutter/features/eval/domain/eval_spec.dart';

/// Replays one scripted event list per generate call, recording lifecycle
/// calls and rendered prompts, so runner behavior is testable without models.
/// A [_boom] entry in a script makes that stream throw mid-generation.
const _boom = 'boom';

final class _ScriptedRuntime implements BrokerRuntime {
  _ScriptedRuntime(this.script);

  final List<List<Object>> script;
  final renderedPrompts = <String>[];
  var loads = 0;
  var unloads = 0;
  var releases = 0;

  @override
  void releaseEngine() => releases++;
  var _generateCalls = 0;

  @override
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
    BrokerLoadOptions options = const BrokerLoadOptions(),
    String? projectorPath,
  }) async {
    loads += 1;
  }

  @override
  Future<void> unload() async {
    unloads += 1;
  }

  @override
  Future<void> cancel() async {}

  @override
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request) {
    renderedPrompts.add(request.prompt);
    final events = script[_generateCalls++];
    return Stream.fromIterable(events).map((event) {
      if (event is BrokerRuntimeEvent) return event;
      throw const BrokerRuntimeException(_boom);
    });
  }
}

const _combo = EvalCombo(
  label: 'model.gguf',
  path: '/local/model.gguf',
  engine: BrokerEngine.llamaCpp,
);

const _metrics = BrokerRuntimeMetrics(
  decodeTokensPerSecond: 40,
  promptTokensPerSecond: 100,
  generatedTokenCount: 12,
  elapsedSeconds: 0.5,
  promptTokenCount: 20,
  timeToFirstTokenSeconds: 0.1,
  peakPhysicalFootprintBytes: 1024,
);

/// The runner drives the app's own repository over the scripted runtime
/// (#42), so these tests also cover the repository's event translation.
Future<EvalComboResult> _run(
  _ScriptedRuntime runtime,
  List<EvalPrompt> prompts,
) => runEvalCombo(
  repository: InfernoInferenceRepository(
    runtime,
    engine: BrokerEngine.llamaCpp,
    modelPath: '/local/model.gguf',
    profile: const Gemma4Profile(),
    seed: uniformEvalSeed(prompts),
  ),
  combo: _combo,
  prompts: prompts,
);

void main() {
  test(
    'a run splits channels, hashes raw text, and scores the answer',
    () async {
      final runtime = _ScriptedRuntime([
        [
          const BrokerTextDelta('<|channel>thought\nponder'),
          const BrokerTextDelta('<channel|>The answer is **Jupiter**.'),
          const BrokerMetricsDelta(_metrics),
          const BrokerGenerationCompleted(BrokerStopReason.stopToken),
        ],
      ]);
      final result = await _run(runtime, [
        EvalPrompt(
          id: 'p1',
          messages: [
            {'role': 'user', 'content': 'Largest planet?'},
          ],
          checks: [
            EvalCheck.contains('jupiter'),
            EvalCheck.notContains('ponder'),
          ],
        ),
      ]);

      expect(runtime.loads, 1);
      expect(runtime.unloads, 1);
      // The runner renders through the same template as the app.
      expect(runtime.renderedPrompts.single, startsWith('<bos><|turn>user\n'));
      expect(runtime.renderedPrompts.single, endsWith('<|turn>model\n'));

      final row = result.promptResults.single;
      expect(row.answer, 'The answer is **Jupiter**.');
      expect(row.reasoning, 'ponder');
      expect(row.stopReason, 'stopToken');
      // The hash covers raw pre-parser text — markers, reasoning, and all.
      expect(
        row.rawTextHash,
        fnv1a64(
          '<|channel>thought\nponder<channel|>The answer is **Jupiter**.',
        ),
      );
      expect(row.metrics?.peakPhysicalFootprintBytes, 1024);
      // Both checks score the answer channel only: reasoning text ("ponder")
      // must not leak into notContains.
      expect(row.checkResults.map((c) => c.passed), everyElement(isTrue));
      expect(row.passed, isTrue);
      expect(result.failures, isEmpty);
    },
  );

  test(
    'required checks gate the result; informational ones never do',
    () async {
      final runtime = _ScriptedRuntime([
        [
          const BrokerTextDelta('Saturn.'),
          const BrokerGenerationCompleted(BrokerStopReason.stopToken),
        ],
        [
          const BrokerTextDelta('Jupiter, obviously.'),
          const BrokerGenerationCompleted(BrokerStopReason.stopToken),
        ],
      ]);
      final result = await _run(runtime, [
        EvalPrompt(
          id: 'wrong-answer',
          messages: [
            {'role': 'user', 'content': 'Largest planet?'},
          ],
          checks: [EvalCheck.contains('Jupiter')],
        ),
        EvalPrompt(
          id: 'wordy-answer',
          messages: [
            {'role': 'user', 'content': 'One word only.'},
          ],
          checks: [
            EvalCheck.contains('Jupiter'),
            EvalCheck.regexp(r'^\w+$', required: false),
          ],
        ),
      ]);

      expect(result.promptResults[0].passed, isFalse);
      expect(result.promptResults[1].passed, isTrue);
      expect(result.failures, hasLength(1));
      expect(result.failures.single, contains('wrong-answer'));
      expect(result.failures.single, contains('Saturn.'));
    },
  );

  test(
    'a failed generation becomes an error row and the run continues',
    () async {
      final runtime = _ScriptedRuntime([
        [const BrokerTextDelta('partial'), _boom],
        [
          const BrokerTextDelta('fine'),
          const BrokerGenerationCompleted(BrokerStopReason.endOfSequence),
        ],
      ]);
      final result = await _run(runtime, [
        EvalPrompt(
          id: 'exploding',
          messages: [
            {'role': 'user', 'content': 'a'},
          ],
          checks: [EvalCheck.contains('anything')],
        ),
        EvalPrompt(
          id: 'surviving',
          messages: [
            {'role': 'user', 'content': 'b'},
          ],
          checks: [EvalCheck.contains('fine')],
        ),
      ]);

      expect(result.promptResults[0].error, contains('boom'));
      expect(result.promptResults[0].passed, isFalse);
      expect(result.promptResults[1].passed, isTrue);
      expect(runtime.unloads, 1);
      expect(result.failures.single, contains('exploding'));
    },
  );

  test('budget exhaustion surfaces as a failed informational check', () async {
    final runtime = _ScriptedRuntime([
      [
        const BrokerTextDelta('Jupiter is the largest'),
        const BrokerGenerationCompleted(BrokerStopReason.maxTokens),
      ],
    ]);
    final result = await _run(runtime, [
      EvalPrompt(
        id: 'truncated',
        messages: [
          {'role': 'user', 'content': 'Largest planet?'},
        ],
        checks: [EvalCheck.contains('Jupiter')],
      ),
    ]);

    // The content check passes on the truncated text; the implicit budget
    // check records the truncation in the check list without gating the run.
    final row = result.promptResults.single;
    expect(row.passed, isTrue);
    expect(result.failures, isEmpty);
    final budget = row.checkResults.singleWhere(
      (check) => check.description.contains('token budget'),
    );
    expect(budget.required, isFalse);
    expect(budget.passed, isFalse);
  });

  test('the default spec is coherent', () {
    final ids = defaultEvalPrompts.map((prompt) => prompt.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final prompt in defaultEvalPrompts) {
      expect(prompt.checks, isNotEmpty, reason: '${prompt.id} has no checks');
      expect(
        prompt.checks.any((check) => check.required),
        isTrue,
        reason: '${prompt.id} cannot pass or fail without a required check',
      );
    }
    // The determinism anchor must keep the probe's exact sampling policy so
    // its hash stays comparable with docs/notes/determinism-probe.md.
    final anchor = defaultEvalPrompts.singleWhere(
      (prompt) => prompt.id == evalAnchorPromptId,
    );
    expect(anchor.seed, 7);
    // The harness pins one seed per run at repository construction; the
    // shipped spec must stay representable.
    expect(uniformEvalSeed(defaultEvalPrompts), 7);
    expect(anchor.temperature, 1);
    expect(anchor.topP, 0.95);
    expect(anchor.maxTokens, 2048);
    expect(anchor.reasoningEnabled, isFalse);
    expect(
      anchor.messages.single['content'],
      'Name the largest planet in the solar system.',
    );
    // The broker's profile registry serves the harness template keys.
    expect(modelProfiles.keys, containsAll(['gemma4', 'qwen35']));
  });

  test('the Arabic smoke suite is bounded and requires Arabic answers', () {
    expect(evalPromptsForSuite(defaultEvalSuite), same(defaultEvalPrompts));
    expect(
      evalPromptsForSuite(arabicSmokeEvalSuite),
      same(arabicSmokeEvalPrompts),
    );
    expect(arabicSmokeEvalPrompts, hasLength(2));
    expect(uniformEvalSeed(arabicSmokeEvalPrompts), 7);
    for (final prompt in arabicSmokeEvalPrompts) {
      expect(prompt.messages.single['content'], matches(r'[\u0600-\u06ff]'));
      expect(
        prompt.checks.any((check) => check.value == r'[\u0600-\u06ff]'),
        isTrue,
      );
    }
    expect(() => evalPromptsForSuite('unknown'), throwsArgumentError);
  });

  test('the global language smoke is fixed, bounded, and non-reasoning', () {
    expect(
      evalPromptsForSuite(globalLanguageSmokeEvalSuite),
      same(globalLanguageSmokeEvalPrompts),
    );
    expect(globalLanguageSmokeEvalPrompts, hasLength(9));
    expect(uniformEvalSeed(globalLanguageSmokeEvalPrompts), 7);
    expect(
      globalLanguageSmokeEvalPrompts.map((prompt) => prompt.id),
      containsAll([
        'spanish-arithmetic-17x23',
        'brazilian-portuguese-arithmetic-17x23',
        'japanese-arithmetic-17x23',
        'indonesian-arithmetic-17x23',
        'hindi-arithmetic-17x23',
        'french-arithmetic-17x23',
        'vietnamese-arithmetic-17x23',
        'turkish-arithmetic-17x23',
        'korean-arithmetic-17x23',
      ]),
    );
    for (final prompt in globalLanguageSmokeEvalPrompts) {
      expect(prompt.reasoningEnabled, isFalse, reason: prompt.id);
      expect(prompt.maxTokens, 64, reason: prompt.id);
      expect(prompt.seed, 7, reason: prompt.id);
      expect(
        prompt.checks.any((check) => check.value == r'\b391\b'),
        isTrue,
        reason: prompt.id,
      );
      expect(prompt.checks.where((check) => check.required), hasLength(2));
    }

    final promptsById = {
      for (final prompt in globalLanguageSmokeEvalPrompts) prompt.id: prompt,
    };
    const naturalVariants = {
      'hindi-arithmetic-17x23': 'परिणाम 391 है।',
      'vietnamese-arithmetic-17x23': '17 nhân với 23 bằng 391.',
      'turkish-arithmetic-17x23': 'Sonuç 391’dir.',
      'korean-arithmetic-17x23': '17 × 23 는 391 입니다.',
    };
    for (final MapEntry(key: id, value: answer) in naturalVariants.entries) {
      final checks = promptsById[id]!.checks;
      expect(checks.every((check) => check.passes(answer)), isTrue, reason: id);
      expect(
        checks[1].passes('17 × 23 = 391'),
        isFalse,
        reason: '$id must retain a native-language signal',
      );
    }
  });

  test('the Simplified Chinese feasibility suite is exact and bounded', () {
    expect(
      evalPromptsForSuite(simplifiedChineseFeasibilityEvalSuite),
      same(simplifiedChineseFeasibilityEvalPrompts),
    );
    expect(simplifiedChineseFeasibilityEvalPrompts, hasLength(1));
    expect(uniformEvalSeed(simplifiedChineseFeasibilityEvalPrompts), 7);

    final prompt = simplifiedChineseFeasibilityEvalPrompts.single;
    expect(prompt.id, 'simplified-chinese-arithmetic-17x23');
    expect(prompt.reasoningEnabled, isFalse);
    expect(prompt.maxTokens, 64);
    expect(prompt.seed, 7);
    expect(prompt.temperature, isNull);
    expect(prompt.topP, isNull);
    expect(prompt.messages, hasLength(1));
    expect(prompt.messages.single['role'], 'user');
    expect(prompt.messages.single['content'], contains('计算结果是'));
    expect(prompt.checks.where((check) => check.required), hasLength(2));
    expect(prompt.checks.map((check) => check.value), [r'\b391\b', '计算结果是']);
    expect(prompt.checks.every((check) => check.passes('计算结果是 391。')), isTrue);
    expect(
      prompt.checks.every((check) => check.passes('The result is 391.')),
      isFalse,
    );
  });
}
