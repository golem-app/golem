import 'dart:convert';
import 'dart:io';

import 'package:inferno/inferno.dart';

/// Confirms that every human-readable release/version constant in the
/// manifest names the tag whose commit is the pinned revision. The pin
/// tests keep the shims and lockfiles agreeing with the manifest; this
/// tool closes the remaining gap — the manifest agreeing with upstream.
///
/// Network-dependent by design: run it when bumping a pin, not in CI.
/// Usage: `dart run tool/verify_pins.dart`.
Future<void> main() async {
  const pins = [
    ('ggml-org/llama.cpp', llamaCppRelease, llamaCppRevision),
    ('ml-explore/mlx-swift-lm', mlxSwiftLmVersion, mlxSwiftLmRevision),
    ('ml-explore/mlx-swift', mlxSwiftVersion, mlxSwiftRevision),
  ];
  final client = HttpClient();
  var failures = 0;
  try {
    for (final (repository, tag, revision) in pins) {
      final resolved = await _tagCommit(client, repository, tag);
      if (resolved == null) {
        stderr.writeln('$repository: tag "$tag" was not found upstream.');
        failures++;
      } else if (resolved != revision) {
        stderr.writeln(
          '$repository: tag "$tag" points at $resolved, but the manifest '
          'pins $revision.',
        );
        failures++;
      } else {
        stdout.writeln('$repository: $tag == ${revision.substring(0, 12)} OK');
      }
    }
  } finally {
    client.close();
  }
  if (failures > 0) exitCode = 1;
}

Future<String?> _tagCommit(
  HttpClient client,
  String repository,
  String tag,
) async {
  for (final candidate in [tag, 'v$tag']) {
    final reference = await _json(
      client,
      'https://api.github.com/repos/$repository/git/ref/tags/$candidate',
    );
    if (reference == null) continue;
    final object = reference['object']! as Map<String, Object?>;
    final sha = object['sha']! as String;
    if (object['type'] != 'tag') return sha;
    // Annotated tags need one more hop to reach the commit they name.
    final annotated = await _json(
      client,
      'https://api.github.com/repos/$repository/git/tags/$sha',
    );
    if (annotated == null) return null;
    return (annotated['object']! as Map<String, Object?>)['sha']! as String;
  }
  return null;
}

Future<Map<String, Object?>?> _json(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('Accept', 'application/vnd.github+json');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != HttpStatus.ok) return null;
  return jsonDecode(body) as Map<String, Object?>;
}
