import 'dart:io';

import 'package:golem_flutter/broker/model_runtime_config.dart';
import 'package:golem_flutter/broker/runtime.dart';

import '../application/eval_runner.dart';

List<String> _segments(String path) => path
    .split(Platform.pathSeparator)
    .where((segment) => segment.isNotEmpty)
    .toList();

/// Builds the evaluation matrix from the comma-separated path defines.
/// Degenerate entries — empty, `/`, bare separators (e.g. an unset shell
/// variable expanding to `$MODELS/` → `/`) — are dropped so they fall into
/// the driver's deliberate skip instead of throwing during test collection.
List<EvalCombo> evalMatrixFromDefines({
  required String ggufDefine,
  required String mlxDefine,
}) {
  List<String> paths(String define) => define
      .split(',')
      .map((path) => path.trim())
      .where((path) => _segments(path).isNotEmpty)
      .toList();

  return _disambiguated([
    for (final path in paths(ggufDefine))
      EvalCombo(
        label: _segments(path).last,
        path: path,
        engine: BrokerEngine.llamaCpp,
      ),
    for (final path in paths(mlxDefine))
      EvalCombo(
        label: _segments(path).last,
        path: path,
        engine: BrokerEngine.mlx,
      ),
  ]);
}

/// Resolves comma-separated catalog keys against the app's own documents
/// directory, so a device run evaluates the artifacts actually installed
/// there. Each combo carries its own profile: a Qwen artifact rendered and
/// stopped with the Gemma template would produce numbers that describe
/// nothing, and the pin guard cannot catch it (installed combos are named
/// by catalog key, not by pinned filename). Unknown or `custom-*` keys
/// throw out of [resolveModelRuntimeConfig] — loudly, at collection.
List<EvalCombo> installedEvalCombos({
  required String installedDefine,
  required String documentsDirectory,
}) => [
  for (final key in installedDefine.split(','))
    if (key.trim().isNotEmpty) _installedCombo(key.trim(), documentsDirectory),
];

EvalCombo _installedCombo(String key, String documentsDirectory) {
  final config = resolveModelRuntimeConfig(key);
  return EvalCombo(
    label: config.catalogKey,
    path: config.modelPath.replaceFirst('documents:', '$documentsDirectory/'),
    engine: config.engine,
    profileKey: config.profile.key,
  );
}

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
        profileKey: combo.profileKey,
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
