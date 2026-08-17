import 'dart:convert';
import 'dart:io';

/// Fails when the SDK actually running diverges from the pin, or when the
/// committed files that name it stop agreeing.
///
/// `.fvmrc` is the single source of truth: fvm materialises it locally and
/// `subosito/flutter-action` reads the same file in CI. Nothing else may name
/// a version — a second literal is how local and CI drifted apart in the
/// first place (#128). Run from the repository root.
Future<void> main() async {
  final problems = <String>[];

  final pin = _pinnedVersion();
  if (pin == null) {
    stderr.writeln('.fvmrc is missing or names no "flutter" version.');
    exitCode = 1;
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

  final floor = _pubspecFloor();
  if (floor != pin) {
    problems.add(
      "app/pubspec.yaml declares flutter '>=$floor', .fvmrc pins $pin.",
    );
  }

  problems.addAll(_workflowProblems());

  if (problems.isEmpty) return;
  stderr.writeln('Toolchain pin (.fvmrc: $pin) is not held:');
  for (final problem in problems) {
    stderr.writeln('  $problem');
  }
  exitCode = 1;
}

String? _pinnedVersion() {
  final file = File('.fvmrc');
  if (!file.existsSync()) return null;
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) return null;
  final version = decoded['flutter'];
  return version is String && version.isNotEmpty ? version : null;
}

/// Read from the SDK this process was launched by, not from `flutter
/// --version` — shelling out would answer for whatever is first on PATH,
/// which is the thing being checked. `resolvedExecutable` is
/// `<sdk>/bin/cache/dart-sdk/bin/dart`.
String? _runningVersion() {
  final dartBin = File(Platform.resolvedExecutable).parent;
  final cache = dartBin.parent.parent;
  final stamp = File('${cache.path}/flutter.version.json');
  if (!stamp.existsSync()) return null;
  final decoded = jsonDecode(stamp.readAsStringSync());
  return decoded is Map ? decoded['frameworkVersion'] as String? : null;
}

String? _pubspecFloor() {
  final match = RegExp(
    r"""^\s+flutter:\s*['"]?>=([\d.]+)""",
    multiLine: true,
  ).firstMatch(File('app/pubspec.yaml').readAsStringSync());
  return match?.group(1);
}

List<String> _workflowProblems() {
  final file = File('.github/workflows/ci.yml');
  if (!file.existsSync()) return ['.github/workflows/ci.yml is missing.'];
  final source = file.readAsStringSync();
  final problems = <String>[];
  final literal = RegExp(r'^\s*flutter-version:', multiLine: true);
  if (literal.hasMatch(source)) {
    problems.add(
      'ci.yml names a literal flutter-version; it must read '
      'flutter-version-file: .fvmrc so the pin lives in one place.',
    );
  }
  final jobs = RegExp('subosito/flutter-action').allMatches(source).length;
  final reads = RegExp(
    r'^\s*flutter-version-file:\s*\.fvmrc\s*$',
    multiLine: true,
  ).allMatches(source).length;
  if (reads != jobs) {
    problems.add('$jobs job(s) set up Flutter but $reads read .fvmrc.');
  }
  return problems;
}
