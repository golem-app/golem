import 'dart:convert';
import 'dart:io';

/// Colocates MLX's shader library beside the hook-built dylib for CLI runs.
///
/// MLX resolves `current_binary_dir()/mlx.metallib` before falling back to
/// app-bundle lookups. Inside the app the staged `mlx-swift_Cmlx.bundle`
/// provides it, but `dart test` and the bench tools load the dylib from
/// wherever `.dart_tool/native_assets.yaml` points — the workspace root's
/// `.dart_tool/lib/` on a workspace SDK, where nothing put one — so every CLI
/// entry point has to stage it or the MLX load fails to find its shaders. The
/// mapping is read rather than assumed: a stale package-local copy of it once
/// shadowed a fresh build and kept an ABI-4 carrier in the loop (#57).
///
/// Silent by default because the llama-only paths call it too and have no MLX
/// bundle to find; [warnOnMissing] is for the benches, where a missing shader
/// library is about to look like an inference failure.
void stageMlxMetallibForCliRun({bool warnOnMissing = false}) {
  final dylib = _mappedMlxCarrier();
  final metallib = File(
    'build/apple-resources/macosx/mlx-swift_Cmlx.bundle/'
    'Contents/Resources/default.metallib',
  );
  if (dylib != null && dylib.existsSync() && metallib.existsSync()) {
    metallib.copySync('${dylib.parent.path}/mlx.metallib');
  } else if (warnOnMissing) {
    stderr.writeln(
      'warning: could not stage mlx.metallib '
      '(dylib: ${dylib?.path ?? 'unmapped'}, '
      'metallib: ${metallib.existsSync()}); '
      'the MLX load may fail to resolve its shader library.',
    );
  }
}

/// The carrier named by the nearest native-assets mapping, walking up from the
/// working directory the way the VM resolves the mapping itself.
File? _mappedMlxCarrier() {
  const carrier = 'package:inferno/inferno_mlx.dart';
  var directory = Directory.current;
  while (true) {
    final mapping = File('${directory.path}/.dart_tool/native_assets.yaml');
    if (mapping.existsSync()) {
      // JSON under a comment header, as dartdev writes it.
      final body = mapping
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      final assets =
          (jsonDecode(body) as Map<String, Object?>)['native-assets'];
      if (assets is! Map<String, Object?>) return null;
      for (final target in assets.values) {
        final entry = (target as Map<String, Object?>)[carrier];
        if (entry is List && entry.length == 2 && entry.first == 'absolute') {
          return File(entry.last as String);
        }
      }
      return null;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}
