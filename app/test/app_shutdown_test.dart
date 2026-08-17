import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/app.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';

import 'support/harness.dart';

/// #124: backing out of the app mid-answer tore the isolate down while
/// llama.cpp's worker was still calling the token trampoline, aborting the
/// process ~5 s later. The ordering is the whole fix, so that is what this
/// asserts: the engine is released *before* the exit is requested, not merely
/// at some point afterwards.
void main() {
  testWidgets('backing out of the root route releases the engine first', (
    tester,
  ) async {
    final container = buildContainer();
    addTearDown(container.dispose);
    final inference =
        container.read(inferenceRepositoryProvider) as FakeInferenceRepository;
    await container.read(modelControllerProvider.future);

    int? disposesWhenExitRequested;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') {
          disposesWhenExitRequested = inference.disposes;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: wrapApp(
          child: const ExitGuard(child: Center(child: Text('root'))),
        ),
      ),
    );

    // What the platform delivers for a system back press.
    await tester.binding.handlePopRoute();
    // The guard's teardown is asynchronous; give it bounded time to land
    // rather than assuming one settle covers it.
    for (var i = 0; i < 20 && disposesWhenExitRequested == null; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(
      disposesWhenExitRequested,
      1,
      reason: 'the app must not ask to exit before the engine is released',
    );
  });
}
