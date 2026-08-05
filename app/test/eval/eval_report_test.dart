import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/runtime.dart';

import '../../integration_test/eval/eval_report.dart';
import '../../integration_test/eval/eval_runner.dart';

const _combo = EvalCombo(
  label: 'model.gguf',
  path: '/private/somewhere/model.gguf',
  engine: BrokerEngine.llamaCpp,
);

EvalRunReport _fixtureReport() => EvalRunReport(
  createdAt: DateTime.utc(2026, 8, 5, 12),
  host: 'macOS test-host',
  results: [
    EvalComboResult(
      combo: _combo,
      loadSeconds: 2.5,
      promptResults: const [
        EvalPromptResult(
          promptId: 'p-pass',
          answer: 'Jupiter.',
          stopReason: 'stopToken',
          rawTextHash: 'd710455907eadf55',
          rawTextLength: 8,
          metrics: BrokerRuntimeMetrics(
            decodeTokensPerSecond: 48.2,
            promptTokensPerSecond: 120,
            generatedTokenCount: 14,
            elapsedSeconds: 0.4,
            promptTokenCount: 18,
            timeToFirstTokenSeconds: 0.119,
            peakPhysicalFootprintBytes: 483183820,
          ),
          checkResults: [
            EvalCheckResult(
              description: 'contains(Jupiter)',
              required: true,
              passed: true,
            ),
          ],
        ),
        EvalPromptResult(promptId: 'p-error', error: 'engine exploded'),
      ],
    ),
  ],
  artifacts: {
    _combo.label: const EvalArtifactRecord(
      label: 'model.gguf',
      path: '/private/somewhere/model.gguf',
      sizeBytes: 2620370976,
      pinnedRepository: 'unsloth/gemma-4-E2B-it-qat-GGUF',
      pinnedRevision: '66a399f68ddd113b06dff02fca9523e55465d11d',
    ),
  },
);

void main() {
  test('the JSON evidence is complete and paths are opt-in', () {
    final report = _fixtureReport();
    final withPaths = report.toJson(includePaths: true);
    final withoutPaths = report.toJson(includePaths: false);

    final artifact = (withPaths['artifacts']! as List).single as Map;
    expect(artifact['path'], '/private/somewhere/model.gguf');
    final scrubbed = (withoutPaths['artifacts']! as List).single as Map;
    expect(scrubbed.containsKey('path'), isFalse);

    expect(withPaths['enginePins'], containsPair('llamaCppRelease', 'b10241'));
    final result = (withPaths['results']! as List).single as Map;
    expect(result['passed'], isFalse);
    final prompts = result['prompts']! as List;
    final passRow = prompts.first as Map;
    expect(passRow['fnv1a64'], 'd710455907eadf55');
    expect(
      (passRow['metrics']! as Map)['peakPhysicalFootprintBytes'],
      483183820,
    );
    final errorRow = prompts.last as Map;
    expect(errorRow['error'], 'engine exploded');
    expect(errorRow['passed'], isFalse);
  });

  test('the Markdown evidence is committable: labels only, no paths', () {
    final markdown = _fixtureReport().renderMarkdown();
    expect(markdown, contains('# Golem model evaluation — 2026-08-05'));
    expect(markdown, contains('## model.gguf · llamaCpp'));
    expect(markdown, contains('llama.cpp b10241'));
    expect(markdown, contains('unsloth/gemma-4-E2B-it-qat-GGUF @ 66a399f6'));
    expect(markdown, contains('`d710455907eadf55`'));
    expect(markdown, contains('never quote them as mobile performance'));
    expect(markdown, contains('> engine exploded'));
    expect(markdown, isNot(contains('/private/somewhere')));
  });

  test('describeArtifact matches pinned artifacts by basename', () async {
    final directory = await Directory.systemTemp.createTemp('golem-eval-test');
    addTearDown(() => directory.delete(recursive: true));
    final gguf = File('${directory.path}/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf')
      ..writeAsBytesSync([1, 2, 3]);
    final mlxDir = Directory('${directory.path}/gemma-4-e2b-it-4bit')
      ..createSync();
    File('${mlxDir.path}/config.json').writeAsBytesSync([1, 2, 3, 4]);

    final ggufRecord = describeArtifact(
      EvalCombo(
        label: 'gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
        path: gguf.path,
        engine: BrokerEngine.llamaCpp,
      ),
    );
    expect(ggufRecord.pinnedRepository, 'unsloth/gemma-4-E2B-it-qat-GGUF');
    expect(ggufRecord.sizeBytes, 3);

    final mlxRecord = describeArtifact(
      EvalCombo(
        label: 'gemma-4-e2b-it-4bit',
        path: mlxDir.path,
        engine: BrokerEngine.mlx,
      ),
    );
    expect(mlxRecord.pinnedRepository, 'mlx-community/gemma-4-e2b-it-4bit');
    expect(mlxRecord.sizeBytes, 4);

    final unknown = describeArtifact(
      EvalCombo(
        label: 'mystery.gguf',
        path: '${directory.path}/missing.gguf',
        engine: BrokerEngine.llamaCpp,
      ),
    );
    expect(unknown.pinnedRepository, isNull);
    expect(unknown.sizeBytes, isNull);
  });
}
