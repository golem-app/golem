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
  var _generateCalls = 0;

  @override
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
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
      final result = await _run(runtime, const [
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
      final result = await _run(runtime, const [
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
      final result = await _run(runtime, const [
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
    final result = await _run(runtime, const [
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
}
