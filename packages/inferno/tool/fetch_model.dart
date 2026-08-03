import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:inferno/inferno.dart';

/// Downloads a pinned model artifact for local benching and device
/// validation. Usage: `dart run tool/fetch_model.dart <mlx|gguf> [directory]`.
/// Weights never enter the repository; the default destination is the
/// gitignored `build/models/`.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || !const {'mlx', 'gguf'}.contains(arguments.first)) {
    stderr.writeln('Usage: dart run tool/fetch_model.dart <mlx|gguf> [dir]');
    exitCode = 64;
    return;
  }
  final artifact = arguments.first == 'mlx'
      ? gemma4E2BMlx4Bit
      : gemma4E2BGgufQ4;
  final root = Directory(arguments.length > 1 ? arguments[1] : 'build/models');
  final destination = Directory(
    '${root.path}/${artifact.repository.split('/').last}',
  );
  await destination.create(recursive: true);

  for (final spec in artifact.files) {
    final file = File('${destination.path}/${spec.path}');
    if (await _matches(file, spec.sha256, spec.bytes)) {
      stderr.writeln('ok       ${spec.path}');
      continue;
    }
    stderr.writeln('fetching ${spec.path} (${spec.bytes} bytes)');
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.partial');
    final request = await HttpClient().getUrl(
      Uri.parse(
        'https://huggingface.co/${artifact.repository}/resolve/'
        '${artifact.revision}/${spec.path}',
      ),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('${spec.path} returned HTTP ${response.statusCode}.');
    }
    await response.pipe(temporary.openWrite());
    if (!await _matches(temporary, spec.sha256, spec.bytes)) {
      throw StateError('${spec.path} size or SHA-256 mismatch.');
    }
    await temporary.rename(file.path);
  }
  stdout.writeln(destination.absolute.path);
}

Future<bool> _matches(File file, String expectedHash, int expectedBytes) async {
  if (!await file.exists() || await file.length() != expectedBytes) {
    return false;
  }
  return (await sha256.bind(file.openRead()).first).toString() == expectedHash;
}
