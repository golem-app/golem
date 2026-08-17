import 'dart:convert';
import 'dart:io';

/// Fails when the SDK actually running diverges from the pin, or when the
/// committed files that name it stop agreeing.
///
/// `.fvmrc` is the single source of truth: fvm materialises it locally and
/// `subosito/flutter-action` reads the same file in CI. Nothing else may name
/// a version — a second literal is how local and CI drifted apart in the
/// first place (#128).
///
/// This is the only implementation; `app/test/toolchain_pin_test.dart` runs
/// it rather than restating its rules, so the two guards cannot disagree.
/// Run from the repository root.
void main() {
  final problems = <String>[];

  final pin = _pinnedVersion(problems);
  if (pin == null) {
    _report('unreadable', problems);
    return;
  }

  final running = _runningVersion();
  if (running == null) {
    problems.add(
      'Could not read the running Flutter version. Run this through the '
      'pinned SDK: `fvm dart run tool/check_toolchain.dart`.',
    );
  } else if (running != pin) {
    problems.add(
      'Running Flutter $running, pinned $pin. Run `fvm install`, then drive '
      'every command through `fvm flutter` / `fvm dart`.',
    );
  }

  problems.addAll(_constraintProblems(pin));
  problems.addAll(_workflowProblems());
  problems.addAll(_trackingProblems());

  _report(pin, problems);
}

void _report(String pin, List<String> problems) {
  if (problems.isEmpty) return;
  stderr.writeln('Toolchain pin (.fvmrc: $pin) is not held:');
  for (final problem in problems) {
    stderr.writeln('  $problem');
  }
  exitCode = 1;
}

String? _pinnedVersion(List<String> problems) {
  final file = File('.fvmrc');
  if (!file.existsSync()) {
    problems.add('.fvmrc is missing.');
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    problems.add('.fvmrc is not valid JSON: ${error.message}');
    return null;
  }
  if (decoded is! Map) {
    problems.add('.fvmrc is not a JSON object.');
    return null;
  }
  final version = decoded['flutter'];
  if (version is! String || version.isEmpty) {
    problems.add('.fvmrc names no "flutter" version.');
    return null;
  }
  return version;
}

/// Read from the SDK this process was launched by, not from `flutter
/// --version` — shelling out would answer for whatever is first on PATH,
/// which is the thing being checked. `resolvedExecutable` is
/// `<sdk>/bin/cache/dart-sdk/bin/dart`.
String? _runningVersion() {
  final dartBin = File(Platform.resolvedExecutable).parent;
  final stamp = File('${dartBin.parent.parent.path}/flutter.version.json');
  if (!stamp.existsSync()) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(stamp.readAsStringSync());
  } on FormatException {
    return null;
  }
  return decoded is Map ? decoded['frameworkVersion'] as String? : null;
}

/// The constraint must be bounded above. Pub enforces only the lower bound,
/// and the drift here runs newer, so a bare `>=` would resolve on any later
/// SDK and never fire.
List<String> _constraintProblems(String pin) {
  const path = 'app/pubspec.yaml';
  final match = flutterConstraint.firstMatch(File(path).readAsStringSync());
  if (match == null) {
    return [
      '$path declares no bounded flutter constraint; expected '
          "'>=$pin <${_nextMinor(pin)}'.",
    ];
  }
  if (match.group(1) != pin) {
    return ["$path floors flutter at ${match.group(1)}, .fvmrc pins $pin."];
  }
  return const [];
}

String _nextMinor(String version) {
  final parts = version.split('.');
  return '${parts[0]}.${int.parse(parts[1]) + 1}.0';
}

List<String> _workflowProblems() {
  final dir = Directory('.github/workflows');
  if (!dir.existsSync()) return ['.github/workflows is missing.'];
  final workflows = dir
      .listSync()
      .whereType<File>()
      .where(
        (file) => file.path.endsWith('.yml') || file.path.endsWith('.yaml'),
      )
      .toList();
  if (workflows.isEmpty) return ['.github/workflows holds no workflow.'];

  final problems = <String>[];
  for (final workflow in workflows) {
    final name = workflow.uri.pathSegments.last;
    final source = workflow.readAsStringSync();
    if (RegExp(r'^\s*flutter-version:', multiLine: true).hasMatch(source)) {
      problems.add(
        '$name names a literal flutter-version; it must read '
        'flutter-version-file: .fvmrc so the pin lives in one place.',
      );
    }
    final jobs = RegExp(
      r'^\s*-?\s*uses:\s*subosito/flutter-action',
      multiLine: true,
    ).allMatches(source).length;
    final reads = RegExp(
      r'^\s*flutter-version-file:\s*\.fvmrc\s*$',
      multiLine: true,
    ).allMatches(source).length;
    if (reads != jobs) {
      problems.add(
        '$name: $jobs step(s) set up Flutter but $reads read .fvmrc.',
      );
    }
  }
  return problems;
}

/// The pin is committed; the SDK it names is not. Asserted against the index
/// rather than .gitignore's text, which a forced add would sail past.
List<String> _trackingProblems() {
  final result = Process.runSync('git', ['ls-files', '.fvm']);
  if (result.exitCode != 0) return const [];
  final tracked = (result.stdout as String).trim();
  if (tracked.isEmpty) return const [];
  return ['.fvm/ is tracked by git: ${tracked.split('\n').join(', ')}'];
}

final flutterConstraint = RegExp(
  r"""^\s+flutter:\s*['"]?>=([\d.]+)\s+<[\d.]+['"]?\s*$""",
  multiLine: true,
);
