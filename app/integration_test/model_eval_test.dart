import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:integration_test/integration_test.dart';

import 'eval/eval_report.dart';
import 'eval/eval_runner.dart';
import 'eval/eval_spec.dart';
import 'eval/eval_templates.dart';

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

List<String> _paths(String define) => define
    .split(',')
    .map((path) => path.trim())
    .where((path) => path.isNotEmpty)
    .toList();

List<String> _segments(String path) => path
    .split(Platform.pathSeparator)
    .where((segment) => segment.isNotEmpty)
    .toList();

String _basename(String path) => _segments(path).last;

/// Quant comparisons may point at same-named artifacts in different
/// directories; identical labels would silently merge their report rows, so
/// colliding labels are prefixed with their parent directory (and numbered
/// as a last resort).
List<EvalCombo> _disambiguated(List<EvalCombo> combos) {
  final counts = <String, int>{};
  for (final combo in combos) {
    counts.update(combo.label, (count) => count + 1, ifAbsent: () => 1);
  }
  final used = <String>{};
  return [
    for (final combo in combos)
      EvalCombo(
        label: _uniqueLabel(combo, counts, used),
        path: combo.path,
        engine: combo.engine,
      ),
  ];
}

String _uniqueLabel(
  EvalCombo combo,
  Map<String, int> counts,
  Set<String> used,
) {
  var label = combo.label;
  if (counts[combo.label]! > 1) {
    final segments = _segments(combo.path);
    if (segments.length > 1) {
      label = '${segments[segments.length - 2]}/${combo.label}';
    }
  }
  var candidate = label;
  var suffix = 2;
  while (!used.add(candidate)) {
    candidate = '$label#${suffix++}';
  }
  return candidate;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final combos = _disambiguated([
    for (final path in _paths(_gguf))
      EvalCombo(
        label: _basename(path),
        path: path,
        engine: BrokerEngine.llamaCpp,
      ),
    for (final path in _paths(_mlx))
      EvalCombo(label: _basename(path), path: path, engine: BrokerEngine.mlx),
  ]);
  // Self-skips when no artifact is requested, so a plain integration-test
  // run (and CI, which never sets the defines) cannot start a model run.
  if (combos.isEmpty) {
    test(
      'model evaluation',
      () {},
      skip:
          'Set GOLEM_EVAL_GGUF (files) and/or GOLEM_EVAL_MLX (directories) '
          'to comma-separated absolute paths to run the evaluation harness.',
    );
    return;
  }
  final results = <EvalComboResult>[];

  for (final combo in combos) {
    test(
      'evaluates ${combo.label} on ${combo.engine.name}',
      () async {
        final template = evalTemplates[_templateKey];
        expect(
          template,
          isNotNull,
          reason:
              'Unknown GOLEM_EVAL_TEMPLATE "$_templateKey"; '
              'known: ${evalTemplates.keys.join(', ')}',
        );
        final adapter = InfernoRuntimeAdapter.native();
        EvalComboResult result;
        try {
          result = await runEvalCombo(
            runtime: adapter,
            combo: combo,
            template: template!,
            prompts: defaultEvalPrompts,
            onProgress: debugPrint,
          );
        } finally {
          await adapter.dispose();
        }
        // Record before asserting so a failing combo still lands in the
        // report — failures are exactly the evidence worth keeping.
        results.add(result);
        expect(
          result.failures,
          isEmpty,
          reason: 'Required checks failed:\n${result.failures.join('\n')}',
        );
      },
      timeout: const Timeout(Duration(minutes: 20)),
    );
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
