import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/configured_inference_repository.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/features/eval/application/eval_runner.dart';
import 'package:golem_flutter/features/eval/data/eval_matrix.dart';
import 'package:golem_flutter/features/eval/data/eval_report.dart';
import 'package:golem_flutter/features/eval/domain/eval_spec.dart';

/// The model-evaluation harness: runs the fixed prompt set against every
/// requested artifact × engine combo on macOS and writes a machine- and
/// human-readable evidence report. One command covers both engines:
///
/// ```sh
/// flutter test integration_test/model_eval_test.dart -d macos --flavor qa \
///   --dart-define=GOLEM_EVAL_GGUF=/abs/path/model.gguf \
///   --dart-define=GOLEM_EVAL_MLX=/abs/path/mlx-model-dir
/// ```
///
/// Both defines accept comma-separated lists (quant comparison); either may
/// be omitted to evaluate one engine. `GOLEM_EVAL_OUT` overrides the report
/// directory (default: the system temp dir; paths are printed at the end).
/// `GOLEM_EVAL_TEMPLATE` selects the model template (default `gemma4`).
/// `GOLEM_EVAL_SUITE` selects `default`, the bounded `arabic-smoke`, or the
/// nine-prompt `global-language-smoke` suite.
///
/// This is a deliberate measurement instrument: it runs real models, takes
/// minutes, and must never be wired into CI. Mac results serve answer
/// quality and relative comparison only — never quote them as mobile
/// performance (`docs/notes/determinism-probe.md`).
const _gguf = String.fromEnvironment('GOLEM_EVAL_GGUF');
const _mlx = String.fromEnvironment('GOLEM_EVAL_MLX');
const _out = String.fromEnvironment('GOLEM_EVAL_OUT');
const _templateKey = String.fromEnvironment(
  'GOLEM_EVAL_TEMPLATE',
  defaultValue: 'gemma4',
);

/// Device mode (#63): comma-separated catalog keys resolved against the
/// app's own documents directory, so the eval runs on a phone against the
/// installed artifacts — no host paths involved:
///
/// ```sh
/// flutter test integration_test/model_eval_test.dart -d <device> \
///   --flavor qa --dart-define=GOLEM_EVAL_INSTALLED=gemma4-gguf
/// ```
const _installed = String.fromEnvironment('GOLEM_EVAL_INSTALLED');
const _suite = String.fromEnvironment(
  'GOLEM_EVAL_SUITE',
  defaultValue: defaultEvalSuite,
);

Future<List<EvalCombo>> _installedCombos() async {
  if (_installed.isEmpty) return const [];
  return installedEvalCombos(
    installedDefine: _installed,
    documentsDirectory: (await getApplicationDocumentsDirectory()).path,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final prompts = evalPromptsForSuite(_suite);

  final defineCombos = evalMatrixFromDefines(
    ggufDefine: _gguf,
    mlxDefine: _mlx,
  );
  // Self-skips when no artifact is requested, so a plain integration-test
  // run (and CI, which never sets the defines) cannot start a model run.
  if (defineCombos.isEmpty && _installed.isEmpty) {
    test(
      'model evaluation',
      () {},
      skip:
          'Set GOLEM_EVAL_GGUF/GOLEM_EVAL_MLX (absolute paths) or '
          'GOLEM_EVAL_INSTALLED (catalog keys) to run the evaluation '
          'harness.',
    );
    return;
  }
  final results = <EvalComboResult>[];
  late final List<EvalCombo> combos;

  setUpAll(() async {
    combos = [...defineCombos, ...await _installedCombos()];
  });

  final installedKeys = _installed
      .split(',')
      .where((key) => key.trim().isNotEmpty)
      .map((key) => key.trim())
      .toList();
  for (
    var index = 0;
    index < defineCombos.length + installedKeys.length;
    index++
  ) {
    final describe = index < defineCombos.length
        ? '${defineCombos[index].label} on ${defineCombos[index].engine.name}'
        : 'installed ${installedKeys[index - defineCombos.length]}';
    test('evaluates $describe', () async {
      final combo = combos[index];
      // A catalog install knows its own family, so it runs under its own
      // profile; a bare path define does not, so it takes the run's
      // template.
      final profileKey = combo.profileKey ?? _templateKey;
      final profile = modelProfiles[profileKey];
      expect(
        profile,
        isNotNull,
        reason:
            'Unknown GOLEM_EVAL_TEMPLATE "$_templateKey"; '
            'known: ${modelProfiles.keys.join(', ')}',
      );
      // A pin-cited artifact evaluated under another family's profile
      // would produce numbers that describe nothing — refuse to record
      // them. Unpinned artifacts cannot be family-checked and pass.
      final pinnedFamily = profileKeyForPinnedRepository(
        describeArtifact(combo).pinnedRepository,
      );
      if (pinnedFamily != null) {
        expect(
          pinnedFamily,
          profileKey,
          reason:
              '${combo.label} is a pinned $pinnedFamily artifact but '
              'it would run under the "$profileKey" profile',
        );
      }
      // The combo runs through the app's own repository (#42): same
      // template, sampling enforcement, parser, and stop policy that
      // ship. The adapter is constructed here only so its native
      // listener can be disposed once the combo is finished.
      final adapter = InfernoRuntimeAdapter.native();
      final repository = selectInferenceRepository(
        identity: AppIdentity.current,
        backend: switch (combo.engine) {
          BrokerEngine.llamaCpp => 'llama',
          BrokerEngine.mlx => 'mlx',
        },
        modelPath: combo.path,
        modelProfile: profileKey,
        fakeStreamDelay: Duration.zero,
        documentsDirectory: '',
        createRuntime: () => adapter,
        samplingSeed: uniformEvalSeed(prompts),
        diagnosticSink: debugPrint,
      );
      EvalComboResult result;
      try {
        result = await runEvalCombo(
          repository: repository,
          combo: combo,
          prompts: prompts,
          onProgress: debugPrint,
        );
      } finally {
        await adapter.dispose();
      }
      // Record before asserting so a failing combo still lands in the
      // report — failures are exactly the evidence worth keeping.
      results.add(result);
      // Greppable per-prompt evidence for device runs, where the file
      // report lands inside the app sandbox: one line per prompt plus a
      // summary, same key=value grammar as INFERNO_METRICS.
      for (final row in result.promptResults) {
        debugPrint(
          'EVAL_RESULT combo=${combo.label}'
          ' profile=$profileKey'
          ' id=${row.promptId}'
          ' pass=${row.passed}'
          ' stopReason=${row.stopReason}'
          ' decodeTokensPerSecond=${row.metrics?.decodeTokensPerSecond.toStringAsFixed(2)}'
          ' promptTokenCount=${row.metrics?.promptTokenCount}'
          ' peakPhysicalFootprintBytes=${row.metrics?.peakPhysicalFootprintBytes}'
          ' fnv1a64=${row.rawTextHash}',
        );
      }
      debugPrint(
        'EVAL_SUMMARY combo=${combo.label}'
        ' profile=$profileKey'
        ' total=${result.promptResults.length}'
        ' passed=${result.promptResults.where((row) => row.passed).length}'
        ' loadSeconds=${result.loadSeconds.toStringAsFixed(2)}',
      );
      expect(
        result.failures,
        isEmpty,
        reason: 'Required checks failed:\n${result.failures.join('\n')}',
      );
    }, timeout: const Timeout(Duration(minutes: 20)));
  }

  tearDownAll(() {
    if (results.isEmpty) return;
    final now = DateTime.now();
    final stamp = now.toIso8601String().substring(0, 19).replaceAll(':', '-');
    final outRoot = _out.isEmpty
        ? '${Directory.systemTemp.path}/golem-eval'
        : _out;
    final runDirectory = Directory('$outRoot/$stamp')
      ..createSync(recursive: true);
    final report = EvalRunReport(
      // UTC in the evidence; the local stamp only names the run directory.
      createdAt: now.toUtc(),
      host: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      suite: _suite,
      profile: modelProfiles[_templateKey]!,
      results: results,
      artifacts: {
        for (final combo in combos)
          if (results.any((result) => result.combo.label == combo.label))
            combo.label: describeArtifact(combo),
      },
    );
    File(
      '${runDirectory.path}/report.json',
    ).writeAsStringSync(report.toJsonString());
    File(
      '${runDirectory.path}/report.md',
    ).writeAsStringSync(report.renderMarkdown());
    debugPrint('GOLEM_EVAL_REPORT json=${runDirectory.path}/report.json');
    debugPrint('GOLEM_EVAL_REPORT md=${runDirectory.path}/report.md');
  });
}
