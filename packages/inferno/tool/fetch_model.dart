import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:inferno/inferno.dart';

/// The fetchable pinned artifacts. `mlx`/`gguf` keep their historical
/// Gemma meaning; new models add a prefixed key.
const _artifacts = <String, InfernoModelArtifact>{
  'mlx': gemma4E2BMlx4Bit,
  'gguf': gemma4E2BGgufQ4,
  'qwen-mlx': qwen35Mlx4Bit,
  'qwen-gguf': qwen35GgufQ4,
  'gemma-mmproj': gemma4E2BMmprojCandidates,
};

/// Downloads a pinned model artifact for local benching and device
/// validation. Usage: `dart run tool/fetch_model.dart <key> [directory]`.
/// Weights never enter the repository; the default destination is the
/// gitignored `build/models/`.
Future<void> main(List<String> arguments) async {
  final artifact = arguments.isEmpty ? null : _artifacts[arguments.first];
  if (artifact == null) {
    stderr.writeln(
      'Usage: dart run tool/fetch_model.dart '
      '<${_artifacts.keys.join('|')}> [dir]',
    );
    exitCode = 64;
    return;
  }
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
    // A file may name its own repository — a projector is often published
    // apart from the weights it pairs with.
    final request = await HttpClient().getUrl(
      Uri.parse(
        'https://huggingface.co/${spec.repository ?? artifact.repository}'
        '/resolve/${spec.revision ?? artifact.revision}/${spec.path}',
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
