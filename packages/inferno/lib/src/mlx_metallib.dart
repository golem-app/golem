import 'dart:io';

/// Colocates MLX's shader library beside the hook-built dylib for CLI runs.
///
/// MLX resolves `current_binary_dir()/mlx.metallib` before falling back to
/// app-bundle lookups. Inside the app the staged `mlx-swift_Cmlx.bundle`
/// provides it, but `dart test` and the bench tools load the dylib from
/// `.dart_tool/lib/`, where nothing put one — so every CLI entry point has to
/// stage it or the MLX load fails to find its shaders.
///
/// Silent by default because the llama-only paths call it too and have no MLX
/// bundle to find; [warnOnMissing] is for the benches, where a missing shader
/// library is about to look like an inference failure.
void stageMlxMetallibForCliRun({bool warnOnMissing = false}) {
  final dylib = File('.dart_tool/lib/libinferno_mlx.dylib');
  final metallib = File(
    'build/apple-resources/macosx/mlx-swift_Cmlx.bundle/'
    'Contents/Resources/default.metallib',
  );
  if (dylib.existsSync() && metallib.existsSync()) {
    metallib.copySync('${dylib.parent.path}/mlx.metallib');
  } else if (warnOnMissing) {
    stderr.writeln(
      'warning: could not stage mlx.metallib '
      '(dylib: ${dylib.existsSync()}, metallib: ${metallib.existsSync()}); '
      'the MLX load may fail to resolve its shader library.',
    );
  }
}
