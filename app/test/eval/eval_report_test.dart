import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_profile.dart';
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
  profile: const Gemma4Profile(),
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
      sizeBytes: 2620370976,
      pinnedRepository: 'unsloth/gemma-4-E2B-it-qat-GGUF',
      pinnedRevision: '66a399f68ddd113b06dff02fca9523e55465d11d',
    ),
  },
);

void main() {
  test('the JSON evidence is complete and never carries paths', () {
    final report = _fixtureReport();
    final json = report.toJson();

    final artifact = (json['artifacts']! as List).single as Map;
    expect(artifact['label'], 'model.gguf');
    expect(artifact.containsKey('path'), isFalse);
    expect('$json', isNot(contains('/private/somewhere')));

    // The profile is an experimental variable; the evidence must carry it.
    final profile = json['profile']! as Map;
    expect(profile['key'], 'gemma4');
    expect(profile['stopTokenIds'], [1, 106]);
    expect(
      (profile['sampling']! as Map)['direct'],
      containsPair('temperature', 1),
    );

    expect(json['enginePins'], containsPair('llamaCppRelease', 'b10241'));
    final result = (json['results']! as List).single as Map;
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
    expect(markdown, contains('- Profile: `gemma4`'));
    expect(markdown, contains('llama.cpp b10241'));
    expect(markdown, contains('unsloth/gemma-4-E2B-it-qat-GGUF @ 66a399f6'));
    expect(markdown, contains('`d710455907eadf55`'));
    expect(markdown, contains('never quote them as mobile performance'));
    expect(markdown, contains('> engine exploded'));
    expect(markdown, isNot(contains('/private/somewhere')));
  });

  test('pinned repositories map to their profile family', () {
    expect(
      profileKeyForPinnedRepository('YoozLabs/Qwen3.5-4B-qat-GGUF'),
      'qwen35',
    );
    expect(
      profileKeyForPinnedRepository('YoozLabs/Qwen3.5-4B-qat-lean-4bit-mlx'),
      'qwen35',
    );
    expect(
      profileKeyForPinnedRepository('unsloth/gemma-4-E2B-it-qat-GGUF'),
      'gemma4',
    );
    expect(
      profileKeyForPinnedRepository('mlx-community/gemma-4-e2b-it-4bit'),
      'gemma4',
    );
    // Unpinned artifacts cannot be family-checked.
    expect(profileKeyForPinnedRepository(null), isNull);
    expect(profileKeyForPinnedRepository('someone/custom-quant'), isNull);
  });

  test('a pin citation requires both the name and the pinned size', () {
    final ggufBytes = gemma4E2BGgufQ4.files.single.bytes;
    expect(
      matchPinnedArtifact(
        label: 'gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
        sizeBytes: ggufBytes,
        engine: BrokerEngine.llamaCpp,
      )?.repository,
      'unsloth/gemma-4-E2B-it-qat-GGUF',
    );
    // A requantized or patched file wearing the pinned filename must not be
    // cited as the pin.
    expect(
      matchPinnedArtifact(
        label: 'gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
        sizeBytes: ggufBytes - 1,
        engine: BrokerEngine.llamaCpp,
      ),
      isNull,
    );
    // Nor may a GGUF-named directory match through the MLX rule.
    expect(
      matchPinnedArtifact(
        label: 'gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
        sizeBytes: ggufBytes,
        engine: BrokerEngine.mlx,
      ),
      isNull,
    );

    final mlxSizes = {
      for (final file in gemma4E2BMlx4Bit.files) file.path: file.bytes,
    };
    expect(
      matchPinnedArtifact(
        label: 'gemma-4-e2b-it-4bit',
        fileSizes: mlxSizes,
        engine: BrokerEngine.mlx,
      )?.repository,
      'mlx-community/gemma-4-e2b-it-4bit',
    );
    // Stray extras (a .DS_Store) must not drop the citation…
    expect(
      matchPinnedArtifact(
        label: 'gemma-4-e2b-it-4bit',
        fileSizes: {...mlxSizes, '.DS_Store': 6148},
        engine: BrokerEngine.mlx,
      ),
      isNotNull,
    );
    // …but a wrong-sized or missing pinned file must.
    expect(
      matchPinnedArtifact(
        label: 'gemma-4-e2b-it-4bit',
        fileSizes: {...mlxSizes, 'model.safetensors': 1},
        engine: BrokerEngine.mlx,
      ),
      isNull,
    );
    expect(
      matchPinnedArtifact(
        label: 'gemma-4-e2b-it-4bit',
        fileSizes: {...mlxSizes}..remove('tokenizer.json'),
        engine: BrokerEngine.mlx,
      ),
      isNull,
    );
  });

  test('describeArtifact stats disk and degrades unverifiable pins', () async {
    final directory = await Directory.systemTemp.createTemp('golem-eval-test');
    addTearDown(() => directory.delete(recursive: true));
    // Pinned filename, wrong size: cited as unverified, never as the pin.
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
    expect(ggufRecord.sizeBytes, 3);
    expect(ggufRecord.pinnedRepository, isNull);
    expect(ggufRecord.pinSummary, 'no pin match (name+size)');

    final mlxRecord = describeArtifact(
      EvalCombo(
        label: 'gemma-4-e2b-it-4bit',
        path: mlxDir.path,
        engine: BrokerEngine.mlx,
      ),
    );
    expect(mlxRecord.sizeBytes, 4);
    expect(mlxRecord.pinnedRepository, isNull);

    final missing = describeArtifact(
      EvalCombo(
        label: 'mystery.gguf',
        path: '${directory.path}/missing.gguf',
        engine: BrokerEngine.llamaCpp,
      ),
    );
    expect(missing.pinnedRepository, isNull);
    expect(missing.sizeBytes, isNull);
  });
}
