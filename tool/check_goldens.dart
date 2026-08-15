import 'dart:io';

/// Checks that every golden on disk is still one a run reaches, and that every
/// golden a run reaches exists.
///
/// Golden names are built by interpolation — `'goldens/chat-light${chromeSuffix()}.png'`
/// and the like — so no static scan of `app/test/` can list them. Running the
/// suite is the only oracle: `app/test/flutter_test_config.dart` appends every
/// compared name to the file named by `GOLEM_GOLDEN_MANIFEST`.
///
/// A stale golden costs nothing to run, which is exactly why one can sit in the
/// tree for months after the test that recorded it is gone.
///
/// Usage: `dart run tool/check_goldens.dart` from the repo root.
Future<void> main(List<String> arguments) async {
  final root = Directory.current;
  if (!File('${root.path}/app/pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exitCode = 1;
    return;
  }

  final goldens = Directory('${root.path}/app/test/goldens');
  if (!goldens.existsSync()) {
    stderr.writeln('${goldens.path} is missing.');
    exitCode = 1;
    return;
  }

  final manifest = File(
    '${Directory.systemTemp.createTempSync('golem-goldens').path}/manifest.txt',
  )..createSync();

  stdout.writeln('Running the app suite to record golden references...');
  final run = await Process.start(
    'flutter',
    ['test', ...arguments],
    workingDirectory: '${root.path}/app',
    environment: {'GOLEM_GOLDEN_MANIFEST': manifest.path},
  );
  // The suite's own failures are the run's business, not this check's; its
  // output is forwarded so a red suite is visible rather than swallowed.
  await Future.wait([
    stdout.addStream(run.stdout),
    stderr.addStream(run.stderr),
  ]);
  final status = await run.exitCode;
  if (status != 0) {
    stderr.writeln(
      '\nThe suite failed, so the recorded set is incomplete and proves '
      'nothing about which goldens are stale. Fix the suite first.',
    );
    exitCode = status;
    return;
  }

  final referenced = manifest
      .readAsLinesSync()
      .where((line) => line.isNotEmpty)
      .map((line) => line.split('/').last)
      .toSet();
  final onDisk = goldens
      .listSync()
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .where((name) => name.endsWith('.png'))
      .toSet();

  final orphans = onDisk.difference(referenced).toList()..sort();
  final missing = referenced.difference(onDisk).toList()..sort();

  stdout.writeln(
    '\n${referenced.length} goldens referenced, ${onDisk.length} on disk.',
  );
  if (orphans.isEmpty && missing.isEmpty) return;

  if (orphans.isNotEmpty) {
    stderr.writeln('\nOn disk but never compared — delete these:');
    for (final name in orphans) {
      stderr.writeln('  app/test/goldens/$name');
    }
  }
  if (missing.isNotEmpty) {
    stderr.writeln('\nCompared but absent — regenerate with --update-goldens:');
    for (final name in missing) {
      stderr.writeln('  app/test/goldens/$name');
    }
  }
  exitCode = 1;
}
