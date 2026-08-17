import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/app.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/features/chat/widgets/attach_sheet.dart';

import 'support/harness.dart';

/// #124: the process aborted with "Callback invoked after it has been
/// deleted" when the isolate died while llama.cpp's worker was still calling
/// the token trampoline.
///
/// `detached` is the only teardown signal Dart receives — predictive back,
/// default-on at targetSdk 36, finishes the activity without running Dart at
/// all — and the framework does not await lifecycle handlers. So the
/// release has to be *synchronous*; anything else races the isolate's own
/// destruction. These tests pin that, and that it stays reversible.
void main() {
  Future<(FakeInferenceRepository, ProviderContainer)> pumpApp(
    WidgetTester tester,
  ) async {
    final container = buildContainer();
    addTearDown(container.dispose);
    final inference =
        container.read(inferenceRepositoryProvider) as FakeInferenceRepository;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const GolemApp(
          identity: AppIdentity.qa,
          picker: AttachmentPicker(),
        ),
      ),
    );
    // Enough for the splash hold and the startup controller's timer; not
    // pumpAndSettle, which never returns while the gate animates.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    return (inference, container);
  }

  testWidgets('detached releases the engine without awaiting anything', (
    tester,
  ) async {
    final (inference, _) = await pumpApp(tester);
    expect(inference.releases, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);

    // Asserted before any pump: a release that needed the event loop to turn
    // would be exactly the race this exists to close.
    expect(inference.releases, 1);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the release is reversible, because detached may return', (
    tester,
  ) async {
    final (inference, _) = await pumpApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    expect(inference.releases, 1);

    // Flutter permits detached -> resumed. Closing the native callback
    // listener here would leave the returning app unable to load at all.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final prepared = inference.prepare(modelKey: 'gemma4-mlx');
    await tester.pump(const Duration(milliseconds: 1));
    await prepared;
    expect(inference.residency.value.loaded, isTrue);
    await tester.pump(const Duration(seconds: 2));
  });
}
