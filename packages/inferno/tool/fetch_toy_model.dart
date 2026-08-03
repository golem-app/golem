import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:inferno/inferno.dart';

Future<void> main(List<String> arguments) async {
  final destination = Directory(
    arguments.isEmpty ? 'build/native-fixtures' : arguments.single,
  );
  await destination.create(recursive: true);
  final artifact = infernoToyGguf;
  final spec = artifact.files.single;
  final model = File('${destination.path}/${spec.path}');
  if (!await _matches(model, spec.sha256, spec.bytes)) {
    final temporary = File('${model.path}.partial');
    final request = await HttpClient().getUrl(
      Uri.parse(
        'https://huggingface.co/${artifact.repository}/resolve/'
        '${artifact.revision}/${spec.path}',
      ),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Toy GGUF returned HTTP ${response.statusCode}.');
    }
    await response.pipe(temporary.openWrite());
    if (!await _matches(temporary, spec.sha256, spec.bytes)) {
      throw StateError('Toy GGUF size or SHA-256 mismatch.');
    }
    await temporary.rename(model.path);
  }

  final header = await model
      .openRead(0, 64)
      .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
  await File(
    '${destination.path}/corrupt.gguf',
  ).writeAsBytes(List<int>.filled(64, 0x41), flush: true);
  await File(
    '${destination.path}/truncated.gguf',
  ).writeAsBytes(header.take(16).toList(), flush: true);
  final incompatible = [...header];
  incompatible[4] = 99;
  incompatible[5] = 0;
  incompatible[6] = 0;
  incompatible[7] = 0;
  await File(
    '${destination.path}/incompatible.gguf',
  ).writeAsBytes(incompatible, flush: true);
  stdout.writeln(model.absolute.path);
}

Future<bool> _matches(File file, String expectedHash, int expectedBytes) async {
  if (!await file.exists() || await file.length() != expectedBytes) {
    return false;
  }
  return (await sha256.bind(file.openRead()).first).toString() == expectedHash;
}
