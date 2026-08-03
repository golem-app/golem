import 'dart:io';

Future<void> main() async {
  final violations = <String>[];
  await for (final entity in Directory.current.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relative = entity.path.replaceFirst('${Directory.current.path}/', '');
    if (relative.startsWith('.dart_tool/') ||
        relative.contains('/build/') ||
        relative.contains('/.build/')) {
      continue;
    }
    final source = await entity.readAsString();
    if (!RegExp(
      r'''(?:import|export)\s+['"]package:inferno/''',
    ).hasMatch(source)) {
      continue;
    }
    // The broker's own test is allowed because the mock engine exists to
    // verify broker behavior without native inference; no other app code or
    // test may touch Inferno directly.
    final allowed =
        relative.startsWith('app/lib/broker/') ||
        relative == 'app/test/broker_test.dart' ||
        relative.startsWith('packages/inferno/test/') ||
        relative.startsWith('packages/inferno/tool/');
    if (!allowed) violations.add(relative);
  }
  if (violations.isEmpty) return;
  stderr.writeln(
    'Only app/lib/broker, its test, and Inferno test/tooling may '
    'import Inferno:',
  );
  for (final path in violations) {
    stderr.writeln('  $path');
  }
  exitCode = 1;
}
