import 'dart:io';

/// The recorded feature-import direction (#129), decided in
/// `docs/decisions/0015-feature-layering.md`.
///
/// Layers run bottom to top. A feature may import strictly downward and never
/// sideways, so no pair of features can form a cycle and no third feature can
/// be reached through one. `core/` may not reach into `features/` at all, and
/// only the composition root — `app/lib/app/` and `main.dart` — may name every
/// feature at once.
///
/// Adding a feature means adding it here, which is the point: the direction is
/// decided in review rather than discovered later from the import graph.
const _layers = <List<String>>[
  // Static copy and registries; imports no feature.
  ['legal'],
  // Persisted app-wide preferences and per-model generation settings.
  ['preferences'],
  // Catalog, downloads, activation, storage accounting, and the model UI
  // shared by chat, onboarding and Settings.
  ['models'],
  // Conversations, generation, and the chat surfaces.
  ['chat'],
  // Screens and flows that compose everything below. Siblings: an import
  // between any two of these is as much a violation as an upward one.
  ['settings', 'onboarding', 'benchmark', 'eval'],
];

const _libRoot = 'app/lib';

/// Line-anchored, so an import path quoted in prose — which the ADRs and the
/// doc comments are full of — is not read as a directive. Each match is then
/// scanned for *every* quoted string up to its semicolon, so a conditional
/// `if (dart.library.io) 'other.dart'` clause cannot slip a target past the
/// direction; `check_inferno_imports.dart` guards its boundary the same way.
final _directive = RegExp(
  r'''^\s*(?:import|export)\s[^;]*;''',
  multiLine: true,
);

final _quoted = RegExp(r'''['"]([^'"]+)['"]''');

int? _rankOf(String feature) {
  for (var index = 0; index < _layers.length; index++) {
    if (_layers[index].contains(feature)) return index;
  }
  return null;
}

/// The feature a `app/lib/...`-relative path belongs to, or null outside
/// `features/`.
String? _featureOf(String path) {
  if (!path.startsWith('features/')) return null;
  final segments = path.split('/');
  return segments.length < 2 ? null : segments[1];
}

Future<void> main() async {
  final root = Directory.current.path;
  final lib = Directory('$root/$_libRoot');
  if (!lib.existsSync()) {
    stderr.writeln('Run this from the repository root: $_libRoot not found.');
    exitCode = 1;
    return;
  }

  final violations = <String>[];
  final unknown = <String>{};

  await for (final entity in lib.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Relative to app/lib, so `features/chat/...` and `app/app.dart` read the
    // way the layer table is written.
    final relative = entity.path.replaceFirst('$root/$_libRoot/', '');
    // The composition root is allowed to name every feature; it is the one
    // place that wires them together (app/lib/app/launch_composition.dart).
    if (relative == 'main.dart' || relative.startsWith('app/')) continue;
    final source = await entity.readAsString();
    final from = _featureOf(relative);
    final fromRank = from == null ? null : _rankOf(from);
    if (from != null && fromRank == null) unknown.add(from);

    for (final directive in _directive.allMatches(source)) {
      for (final quoted in _quoted.allMatches(directive.group(0)!)) {
        final target = _targetOf(quoted.group(1)!, relative);
        if (target == null) continue;
        final to = _featureOf(target);

        if (from == null) {
          // core, l10n, broker: everything a feature reads, so an edge the
          // other way is a cycle with all of them at once.
          if (to != null) {
            violations.add(
              '$relative -> $target '
              '(only features and the composition root may import a feature)',
            );
          }
          continue;
        }
        if (target == 'main.dart' || target.startsWith('app/')) {
          violations.add(
            '$relative -> $target '
            '(a feature may not import the composition root)',
          );
          continue;
        }
        if (to == null || to == from || fromRank == null) continue;

        final toRank = _rankOf(to);
        if (toRank == null) {
          unknown.add(to);
          continue;
        }
        if (toRank < fromRank) continue;
        violations.add(
          '$relative -> $target ($from may not import $to: '
          '${toRank == fromRank ? "same layer" : "$to is above $from"})',
        );
      }
    }
  }

  if (unknown.isNotEmpty) {
    stderr.writeln(
      'Features missing from the direction in tool/check_feature_imports.dart:',
    );
    for (final feature in unknown.toList()..sort()) {
      stderr.writeln('  $feature');
    }
    exitCode = 1;
  }
  if (violations.isNotEmpty) {
    stderr.writeln(
      'Feature imports must run downward through the recorded direction '
      '(docs/decisions/0015-feature-layering.md):',
    );
    for (final violation in violations..sort()) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
  }
}

/// The `app/lib`-relative path [uri] names, or null when it leaves the app.
String? _targetOf(String uri, String from) {
  if (uri.startsWith('package:golem_flutter/')) {
    return uri.substring('package:golem_flutter/'.length);
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  return _normalize('${_dirname(from)}/$uri');
}

String _dirname(String path) {
  final index = path.lastIndexOf('/');
  return index == -1 ? '' : path.substring(0, index);
}

/// `..` and `.` resolution without `dart:io`'s absolute-path normalization,
/// so the result stays relative to `app/lib`.
String _normalize(String path) {
  final out = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(segment);
  }
  return out.join('/');
}
