import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golem_flutter/app/app.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/widgets/attach_sheet.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/l10n/generated/app_localizations.dart';

import 'package:golem_flutter/features/chat/chat_screen.dart';

import 'support/harness.dart';

/// #124: backing out of the app mid-answer tore the isolate down while
/// llama.cpp's worker was still calling the token trampoline, aborting the
/// process ~5 s later.
///
/// Driven through the real router, because the guard's placement is half the
/// fix: it must cover the shell (the first-run gate loads the engine while
/// withholding its child) without swallowing ordinary back navigation.
void main() {
  Future<(GoRouter, FakeInferenceRepository, List<String>)> pumpApp(
    WidgetTester tester, {
    bool modelInstalled = true,
  }) async {
    // An installed model plus history, so the first-run gate admits the shell
    // and the router has a route to pop.
    final container = buildContainer(
      history: modelInstalled ? seedHistory() : null,
      model: modelInstalled
          ? const ModelState(
              simulated: true,
              artifacts: {
                'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
              },
            )
          : const ModelState(simulated: true),
    );
    addTearDown(container.dispose);
    final inference =
        container.read(inferenceRepositoryProvider) as FakeInferenceRepository;
    await container.read(modelControllerProvider.future);

    final events = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') {
          events.add('exit:disposes=${inference.disposes}');
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

    final router = createAppRouter(
      identity: AppIdentity.qa,
      picker: const AttachmentPicker(),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (router, inference, events);
  }

  Future<void> systemBack(WidgetTester tester, List<String> events) async {
    await tester.binding.handlePopRoute();
    // The teardown is asynchronous; give it bounded time rather than
    // assuming one settle covers it.
    for (var i = 0; i < 20 && events.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('backing out of the app releases the engine first', (
    tester,
  ) async {
    final (_, _, events) = await pumpApp(tester);
    await systemBack(tester, events);

    // The count is captured at the moment the exit is requested, so this
    // fails both when teardown is missing and when it merely runs afterwards.
    expect(events, ['exit:disposes=1']);
  });

  testWidgets('backing out of a pushed route pops without tearing down', (
    tester,
  ) async {
    final (router, inference, events) = await pumpApp(tester);
    router.push('/settings');
    await tester.pumpAndSettle();

    await systemBack(tester, events);

    expect(events, isEmpty, reason: 'this back stays inside the app');
    expect(inference.disposes, 0, reason: 'the engine must survive');
    expect(router.state.uri.toString(), '/');

    // The route's own pop — what an iOS back-swipe completes into. The shell
    // guard must not gate it either.
    router.push('/settings');
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/');
    expect(events, isEmpty);
    expect(inference.disposes, 0);
    // And the app is still usable afterwards: back again now exits.
    await systemBack(tester, events);
    expect(events, ['exit:disposes=1']);
  });

  testWidgets('the guard covers first run, which loads before it admits', (
    tester,
  ) async {
    // The gate withholds its child while it validates a sideload — a window
    // that loads the engine. A guard mounted on the root route's child would
    // not exist here at all (#124).
    await pumpApp(tester, modelInstalled: false);

    expect(find.byType(ChatScreen), findsNothing, reason: 'gate is blocking');
    expect(find.byType(ExitGuard), findsOneWidget);
  });
}
