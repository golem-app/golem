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

  test('the device probe answers without constructing a runtime', () async {
    // What the app asks before deciding to fetch weights. It must agree with
    // the instance probe engine for engine: they read the same native payload.
    final device = await Inferno.probeDevice();
    final instance = await Inferno.native().probe();
    expect(device.operatingSystem, instance.operatingSystem);
    expect(
      device.engines.map((engine) => (engine.engine, engine.available)),
      instance.engines.map((engine) => (engine.engine, engine.available)),
    );
    // llama.cpp reports unavailable only on an arm64 Linux/Android CPU without
    // FEAT_DotProd, which the shipped kernels require and no machine here has
    // ever lacked; every other target compiles at its toolchain baseline and
    // passes. The refusal itself stays covered by the load-time guard.
    expect(device.supports(InfernoEngineKind.llamaCpp), isTrue);
  });
}
