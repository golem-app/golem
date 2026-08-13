// Host-side download throughput bench for spike #36.
//
// Spawns real `curl`/`wget` binaries in time-capped windows against the
// pinned Hugging Face artifacts so on-device numbers have a same-network
// baseline captured with the same grammar. Emits one parseable
// `DOWNLOAD_BENCH` line per sample plus a mean summary per client.
//
// The URL/size pins mirror packages/inferno/lib/src/model_manifest.dart,
// which is the source of truth; update both together on a re-pin.
//
// Usage (from the repo root):
//   dart run tool/bench_host_download.dart \
//     [--clients curl-single,curl-ranged:3,curl-ranged:6,wget-single] \
//     [--rounds 3] [--window 45] [--url <url> --bytes <n> | --full] [--out <dir>]
//
// Rounds interleave the client list round-robin so CDN drift lands on every
// client, not just the last one. Rates are decimal MB/s averaged over the
// whole window (curl's own %{speed_download} convention). Downloads go to
// /dev/null or a temp file that is deleted after each window; nothing is
// written outside --out.

import 'dart:async';
import 'dart:io';

const _smallUrl =
    'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/'
    'f6d5376be1edb4d416d56da11e5397a961aca8ae/Qwen3.5-2B-Q4_0.gguf';
const _smallBytes = 1214873856;

const _fullUrl =
    'https://huggingface.co/YoozLabs/Qwen3.5-4B-qat-GGUF/resolve/'
    '2d52e26bd96b49be5f8d37f1c85b27673adaa7da/Qwen3.5-4B-qat-Q4_0.gguf';
const _fullBytes = 2543899040;

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final outDir = Directory(
    options.outPath ?? Directory.systemTemp.createTempSync('golem-bench-').path,
  );
  outDir.createSync(recursive: true);

  final samples = <String, List<double>>{};
  for (var round = 0; round < options.rounds; round++) {
    for (final client in options.clients) {
      final rate = await _runClient(client, options, outDir, round);
      if (rate != null) samples.putIfAbsent(client, () => []).add(rate);
    }
  }

  stdout.writeln('---');
  samples.forEach((client, rates) {
    final mean = rates.reduce((a, b) => a + b) / rates.length;
    final joined = rates.map((r) => r.toStringAsFixed(2)).join(' ');
    stdout.writeln(
      'DOWNLOAD_BENCH_SUMMARY client=$client '
      'samples=${rates.length} rates_mbs="$joined" '
      'mean_mbs=${mean.toStringAsFixed(2)}',
    );
  });
  if (options.outPath == null) outDir.deleteSync(recursive: true);
}

Future<double?> _runClient(
  String client,
  _Options o,
  Directory outDir,
  int round,
) async {
  final ts = DateTime.now().toIso8601String();
  try {
    if (client == 'curl-single') {
      final r = await _curlWindow(o.url, null, o.window);
      _emit(
        client,
        round,
        ts,
        o,
        r.bytes,
        r.rate,
        'http=${r.httpCode} time_s=${r.seconds.toStringAsFixed(1)}',
      );
      return r.rate;
    }
    if (client.startsWith('curl-ranged')) {
      final connections = int.parse(
        client.split(':').elementAtOrNull(1) ?? '3',
      );
      final slice = o.bytes ~/ connections;
      final futures = <Future<_CurlResult>>[];
      for (var i = 0; i < connections; i++) {
        final start = i * slice;
        final end = i == connections - 1 ? o.bytes - 1 : (i + 1) * slice - 1;
        futures.add(_curlWindow(o.url, '$start-$end', o.window));
      }
      final results = await Future.wait(futures);
      var aggregate = 0.0;
      var totalBytes = 0;
      var wallSeconds = 0.0;
      for (final (i, r) in results.indexed) {
        aggregate += r.rate;
        totalBytes += r.bytes;
        if (r.seconds > wallSeconds) wallSeconds = r.seconds;
        _emit(
          '$client conn=$i',
          round,
          ts,
          o,
          r.bytes,
          r.rate,
          'http=${r.httpCode} time_s=${r.seconds.toStringAsFixed(1)}',
        );
      }
      // aggregate (the sum of per-slice averages) matches the prior round's
      // metric; wall_mbs is the honest figure when slices finish at
      // different times, since a finished slice's connection sits idle.
      final wall = wallSeconds > 0 ? totalBytes / wallSeconds / 1e6 : 0.0;
      _emit(
        client,
        round,
        ts,
        o,
        totalBytes,
        aggregate,
        'aggregate=true wall_mbs=${wall.toStringAsFixed(2)}',
      );
      return aggregate;
    }
    if (client == 'wget-single') {
      return await _wgetWindow(o, outDir, round, ts);
    }
    stderr.writeln('unknown client: $client');
    exitCode = 64;
  } on ProcessException catch (e) {
    stdout.writeln(
      'DOWNLOAD_BENCH client=$client round=$round skipped=true '
      'reason="${e.executable}: ${e.message}"',
    );
  }
  return null;
}

class _CurlResult {
  const _CurlResult(this.httpCode, this.bytes, this.rate, this.seconds);
  final String httpCode;
  final int bytes;
  final double rate;
  final double seconds;
}

Future<_CurlResult> _curlWindow(String url, String? range, int window) async {
  final result = await Process.run('curl', [
    '-sL',
    '-o',
    '/dev/null',
    '--max-time',
    '$window',
    if (range != null) ...['-r', range],
    '-w',
    '%{http_code} %{size_download} %{speed_download} %{time_total}',
    url,
  ]);
  // Exit 28 is the expected --max-time cut; the write-out still reports.
  final parts = (result.stdout as String).trim().split(RegExp(r'\s+'));
  if (parts.length < 4) {
    throw ProcessException(
      'curl',
      ['<write-out>'],
      'unparseable write-out: "${result.stdout}" (exit ${result.exitCode})',
    );
  }
  return _CurlResult(
    parts[0],
    int.parse(parts[1]),
    double.parse(parts[2]) / 1e6,
    double.parse(parts[3]),
  );
}

Future<double?> _wgetWindow(
  _Options o,
  Directory outDir,
  int round,
  String ts,
) async {
  final file = File('${outDir.path}/wget-window.part');
  final process = await Process.start('wget', [
    '-q',
    '--tries=1',
    '-O',
    file.path,
    o.url,
  ]);
  final watch = Stopwatch()..start();
  final finished = await process.exitCode.timeout(
    Duration(seconds: o.window),
    onTimeout: () {
      process.kill();
      return -1;
    },
  );
  watch.stop();
  final bytes = file.existsSync() ? file.lengthSync() : 0;
  if (file.existsSync()) file.deleteSync();
  final seconds = watch.elapsedMilliseconds / 1000;
  if (bytes == 0 && finished != 0) {
    stdout.writeln(
      'DOWNLOAD_BENCH client=wget-single round=$round '
      'skipped=true reason="wget produced no bytes (exit $finished)"',
    );
    return null;
  }
  final rate = bytes / seconds / 1e6;
  _emit(
    'wget-single',
    round,
    ts,
    o,
    bytes,
    rate,
    'time_s=${seconds.toStringAsFixed(1)}',
  );
  return rate;
}

void _emit(
  String client,
  int round,
  String ts,
  _Options o,
  int bytes,
  double rateMbs,
  String extra,
) {
  stdout.writeln(
    'DOWNLOAD_BENCH client=$client round=$round '
    'window_s=${o.window} bytes=$bytes '
    'rate_mbs=${rateMbs.toStringAsFixed(2)} '
    'url_host=${Uri.parse(o.url).host} ts=$ts $extra',
  );
}

class _Options {
  _Options({
    required this.clients,
    required this.rounds,
    required this.window,
    required this.url,
    required this.bytes,
    required this.outPath,
  });

  final List<String> clients;
  final int rounds;
  final int window;
  final String url;
  final int bytes;
  final String? outPath;

  static _Options parse(List<String> args) {
    String? value(String flag) {
      final i = args.indexOf(flag);
      return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
    }

    final full = args.contains('--full');
    final url = value('--url') ?? (full ? _fullUrl : _smallUrl);
    final bytes =
        int.tryParse(value('--bytes') ?? '') ??
        (full ? _fullBytes : _smallBytes);
    return _Options(
      clients:
          (value('--clients') ??
                  'curl-single,curl-ranged:3,curl-ranged:6,wget-single')
              .split(','),
      rounds: int.parse(value('--rounds') ?? '3'),
      window: int.parse(value('--window') ?? '45'),
      url: url,
      bytes: bytes,
      outPath: value('--out'),
    );
  }
}
