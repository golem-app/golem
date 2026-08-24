import 'dart:io';

/// Checks that every golden on disk is still one a run reaches, and that every
/// golden a run reaches exists.
///
/// Golden names are built by interpolation — `'goldens/chat-light${chromeSuffix()}.png'`
/// and the like — so no static scan of `app/test/` can list them. Running the
/// suite is the only oracle: `app/test/flutter_test_config.dart` records every
/// compared name into the directory named by `GOLEM_GOLDEN_MANIFEST`, one file
/// per test process.
///
/// A stale golden costs nothing to run, which is exactly why one can sit in the
/// tree for months after the test that recorded it is gone.
///
/// Takes no arguments on purpose. Its output authorizes deletions, and every
/// name a partial run failed to reach would be listed as an orphan — so this
/// runs the whole suite or it reports nothing.
///
/// Usage: `dart run tool/check_goldens.dart` from the repo root.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'check_goldens takes no arguments: a filtered run would report every '
      'golden it did not reach as deletable.',
    );
    exitCode = 64;
    return;
  }

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

  final manifests = Directory.systemTemp.createTempSync('golem-goldens');
  try {
    exitCode = await _check(root, goldens, manifests);
  } finally {
    manifests.deleteSync(recursive: true);
  }
}

Future<int> _check(
  Directory root,
  Directory goldens,
  Directory manifests,
) async {
  stdout.writeln('Running the app suite to record golden references...');
  final run = await Process.start(
    'flutter',
    ['test'],
    workingDirectory: '${root.path}/app',
    environment: {'GOLEM_GOLDEN_MANIFEST': manifests.path},
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
    return status;
  }

  final referenced = manifests
      .listSync()
      .whereType<File>()
      .expand((file) => file.readAsLinesSync())
      .where((line) => line.isNotEmpty)
      .map((line) => line.split('/').last)
      .toSet();
  final onDisk = goldens
      .listSync()
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .where((name) => name.endsWith('.png'))
      .toSet();

  // An empty set means the recorder never ran — a stripped environment, a
  // renamed flutter_test_config — not that every golden is dead.
  if (referenced.isEmpty) {
    stderr.writeln(
      '\nThe suite passed but recorded no goldens at all. The comparator in '
      'app/test/flutter_test_config.dart did not see GOLEM_GOLDEN_MANIFEST; '
      'nothing can be concluded about what is stale.',
    );
    return 1;
  }

  final orphans = onDisk.difference(referenced).toList()..sort();
  final missing = referenced.difference(onDisk).toList()..sort();

  stdout.writeln(
    '\n${referenced.length} goldens referenced, ${onDisk.length} on disk.',
  );
  if (orphans.isEmpty && missing.isEmpty) return 0;

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
  return 1;
}
