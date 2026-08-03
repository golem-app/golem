import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:test/test.dart';

void main() {
  test('the build hook supplies the pinned native ABI', () async {
    final inferno = Inferno.native();
    final probe = await inferno.probe();
    expect(probe.supports(InfernoEngineKind.llamaCpp), isTrue);
    final llama = probe.engines.firstWhere(
      (engine) => engine.engine == InfernoEngineKind.llamaCpp,
    );
    expect(llama.detail, contains(llamaCppRelease));
    // The MLX carrier is an Apple-only code asset; elsewhere the probe must
    // report llama.cpp alone rather than pretend MLX exists.
    expect(
      probe.supports(InfernoEngineKind.mlx),
      Platform.isMacOS || Platform.isIOS,
    );
    if (probe.supports(InfernoEngineKind.mlx)) {
      final mlx = probe.engines.firstWhere(
        (engine) => engine.engine == InfernoEngineKind.mlx,
      );
      expect(mlx.detail, contains(mlxSwiftLmVersion));
    }
  });
}
