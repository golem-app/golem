// Proves a store build carries none of Golem Model Lab (ADR 0021).
//
// The lab lives behind `kLabBuild`, a compile-time constant, so every other
// flavor's AOT snapshot must be free of `lib/features/lab/` and the lab root.
// Rather than trust the tree-shaker's promise, this reads what the compiler
// kept: the retained-object profile `flutter build … --release --analyze-size
// --code-size-directory=<dir>` writes as `snapshot.<arch>.json` (a V8 heap
// snapshot: every Library and Script the snapshot retains is a node named by
// its URI).
//
//   flutter build macos --release --flavor production --analyze-size \
//     --code-size-directory=build/size-macos
//   dart run tool/check_lab_exclusion.dart app/build/size-macos [more dirs…]
//
// Exit 1 names every lab library found; exit 2 means a directory held no
// usable profile, which is a misconfigured run rather than a clean one.
import 'dart:convert';
import 'dart:io';

const _labMarkers = ['/features/lab/', '/app/lab_app.dart'];

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln('usage: dart run tool/check_lab_exclusion.dart <dir>…');
    exitCode = 2;
    return;
  }
  var failed = false;
  for (final directory in arguments) {
    final profiles = Directory(directory).listSync().whereType<File>().where((
      file,
    ) {
      final name = file.uri.pathSegments.last;
      return name.startsWith('snapshot.') && name.endsWith('.json');
    }).toList();
    if (profiles.isEmpty) {
      stderr.writeln(
        '$directory: no snapshot.*.json — not a size-analysis run',
      );
      exitCode = 2;
      return;
    }
    for (final profile in profiles) {
      final libraries = _retainedGolemLibraries(profile);
      if (libraries.isEmpty) {
        stderr.writeln('${profile.path}: no golem_flutter library retained');
        exitCode = 2;
        return;
      }
      final lab = libraries
          .where((uri) => _labMarkers.any(uri.contains))
          .toList();
      if (lab.isEmpty) {
        stdout.writeln(
          '${profile.path}: ${libraries.length} golem_flutter libraries '
          'retained, none from the lab',
        );
        continue;
      }
      failed = true;
      stdout.writeln(
        '${profile.path}: the lab leaked into a store build '
        '(${lab.length} of ${libraries.length} golem_flutter libraries):',
      );
      for (final uri in lab) {
        stdout.writeln('  $uri');
      }
    }
  }
  if (failed) exitCode = 1;
}

/// Every distinct `package:golem_flutter/…` URI a Library or Script node in
/// the profile carries.
Set<String> _retainedGolemLibraries(File profile) {
  final root = jsonDecode(profile.readAsStringSync()) as Map<String, Object?>;
  final snapshot = root['snapshot'] as Map<String, Object?>;
  final meta = snapshot['meta'] as Map<String, Object?>;
  final fields = (meta['node_fields'] as List<Object?>).cast<String>();
  final types = ((meta['node_types'] as List<Object?>).first as List<Object?>)
      .cast<String>();
  final nodes = (root['nodes'] as List<Object?>).cast<int>();
  final strings = (root['strings'] as List<Object?>).cast<String>();
  final typeIndex = fields.indexOf('type');
  final nameIndex = fields.indexOf('name');
  final width = fields.length;
  final libraries = <String>{};
  for (var offset = 0; offset < nodes.length; offset += width) {
    final type = types[nodes[offset + typeIndex]];
    if (type != 'Library' && type != 'Script') continue;
    final name = strings[nodes[offset + nameIndex]];
    if (name.startsWith('package:golem_flutter/')) libraries.add(name);
  }
  return libraries;
}
