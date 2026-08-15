import 'dart:io';

/// Maps what each test file covers that no other test file covers.
///
/// A suite can reach high coverage and still hold tests that add nothing: two
/// files pumping the same screen through the same providers execute the same
/// lines, and only one of them has to exist for the lines to stay covered.
/// Aggregate coverage cannot see that. Running the suite one file at a time
/// can: for test file F, `unique(F)` is the set of `lib` lines F executes and
/// every other file leaves at zero.
///
/// `unique(F) = 0` makes F a *candidate*, never a verdict — two tests can
/// execute identical lines and assert different things. The verdict comes from
/// breaking the behavior F claims and seeing whether anything else fails.
///
/// Usage, from the repo root:
///
///   dart run tool/test_coverage_map.dart [--out report.md] [test path ...]
///
/// With no paths it maps every `*_test.dart` under `app/test/`. Costs roughly
/// one full suite per file — about ten minutes for the whole set.
Future<void> main(List<String> arguments) async {
  final root = Directory.current;
  if (!File('${root.path}/app/pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exitCode = 1;
    return;
  }

  String? outPath;
  final requested = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--out') {
      outPath = arguments[++i];
    } else if (argument.startsWith('--out=')) {
      outPath = argument.substring('--out='.length);
    } else {
      requested.add(argument);
    }
  }

  final tests = requested.isNotEmpty
      ? requested.map(_relativeToApp).toList()
      : _testFiles('${root.path}/app/test');
  if (tests.isEmpty) {
    stderr.writeln('No test files found.');
    exitCode = 1;
    return;
  }
  tests.sort();

  final work = Directory.systemTemp.createTempSync('golem-coverage');
  final covered = <String, Set<String>>{};

  for (final (index, test) in tests.indexed) {
    final label = '[${index + 1}/${tests.length}] $test';
    final lcov = '${work.path}/${test.replaceAll('/', '_')}.info';
    final started = DateTime.now();
    final run = await Process.run('flutter', [
      'test',
      '--coverage',
      '--coverage-path',
      lcov,
      test,
    ], workingDirectory: '${root.path}/app');
    if (run.exitCode != 0) {
      stderr.writeln('$label FAILED\n${run.stdout}\n${run.stderr}');
      exitCode = run.exitCode;
      return;
    }
    covered[test] = _hitLines(File(lcov));
    final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
    stdout.writeln(
      '$label — ${covered[test]!.length} lines '
      '(${seconds.toStringAsFixed(1)}s)',
    );
  }

  final rows = <_Row>[];
  for (final test in tests) {
    final mine = covered[test]!;
    final others = <String>{};
    for (final entry in covered.entries) {
      if (entry.key != test) others.addAll(entry.value);
    }
    final unique = mine.difference(others);
    final overlaps =
        covered.entries
            .where((entry) => entry.key != test && mine.isNotEmpty)
            .map(
              (entry) => (
                entry.key,
                mine.intersection(entry.value).length / mine.length,
              ),
            )
            .where((overlap) => overlap.$2 > 0)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    rows.add(
      _Row(
        test: test,
        covered: mine.length,
        unique: unique.length,
        nearest: overlaps.take(3).toList(),
      ),
    );
  }
  rows.sort((a, b) {
    final byUnique = a.unique.compareTo(b.unique);
    return byUnique != 0 ? byUnique : a.covered.compareTo(b.covered);
  });

  final union = <String>{};
  for (final lines in covered.values) {
    union.addAll(lines);
  }

  final report = StringBuffer()
    ..writeln(
      '| test file | lines covered | uniquely covered | nearest overlap |',
    )
    ..writeln('| --- | ---: | ---: | --- |');
  for (final row in rows) {
    final nearest = row.nearest
        .map(
          (overlap) =>
              '${overlap.$1.replaceFirst('test/', '')} '
              '${(overlap.$2 * 100).round()}%',
        )
        .join(', ');
    report.writeln(
      '| ${row.test.replaceFirst('test/', '')} | ${row.covered} | '
      '${row.unique} | ${nearest.isEmpty ? '—' : nearest} |',
    );
  }
  report
    ..writeln()
    ..writeln(
      '${tests.length} test files, ${union.length} lib lines covered between '
      'them.',
    );

  final candidates = rows.where((row) => row.unique == 0).toList();
  report
    ..writeln()
    ..writeln(
      candidates.isEmpty
          ? 'Every test file covers at least one line no other file reaches.'
          : '${candidates.length} file(s) cover nothing uniquely — candidates, '
                'not verdicts:',
    );
  for (final row in candidates) {
    report.writeln(
      '- ${row.test} (${row.covered} lines, all covered elsewhere)',
    );
  }

  stdout
    ..writeln()
    ..write(report);
  if (outPath != null) {
    File(outPath).writeAsStringSync(report.toString());
    stdout.writeln('\nWritten to $outPath');
  }
}

class _Row {
  _Row({
    required this.test,
    required this.covered,
    required this.unique,
    required this.nearest,
  });

  final String test;
  final int covered;
  final int unique;
  final List<(String, double)> nearest;
}

String _relativeToApp(String path) {
  final normalized = path.startsWith('app/')
      ? path.substring('app/'.length)
      : path;
  return normalized;
}

List<String> _testFiles(String testRoot) => Directory(testRoot)
    .listSync(recursive: true)
    .whereType<File>()
    .map((file) => file.path)
    .where((path) => path.endsWith('_test.dart'))
    .map((path) => 'test/${path.split('/test/').last}')
    .toList();

/// Only executed lines matter: a `DA:` entry at zero says the file was loaded,
/// not that the test reached it.
Set<String> _hitLines(File lcov) {
  final lines = <String>{};
  var source = '';
  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      source = line.substring(3);
    } else if (line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      if (parts.length == 2 && (int.tryParse(parts[1]) ?? 0) > 0) {
        lines.add('$source:${parts[0]}');
      }
    }
  }
  return lines;
}
