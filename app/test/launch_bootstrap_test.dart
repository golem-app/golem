// The bootstrap gate: a launch failure renders as a truthful, retryable pane
// on the splash frame — never the native launch screen forever — and Try
// again reruns the real composition (#66).
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/bootstrap.dart';
import 'package:golem_flutter/app/launch_composition.dart';
import 'package:golem_flutter/core/domain/app_state.dart';

import 'support/harness.dart';

/// Pumps the gate theatre to completion with explicit durations — never
/// pumpAndSettle across the startup providers.
Future<void> pumpThroughTheatre(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory scratch() {
    final directory = Directory.systemTemp.createTempSync('golem-bootstrap-');
    addTearDown(() => directory.deleteSync(recursive: true));
    return directory;
  }

  testWidgets('a failed composition retries into the app', (tester) async {
    setViewport(tester);
    final directory = scratch();
    var calls = 0;
    Future<LaunchDependencies> compose() async {
      calls++;
      if (calls == 1) throw Exception('first composition fails');
      return launchDependenciesWith(directory: directory);
    }

    await tester.pumpWidget(BootstrapApp(compose: compose));
    await tester.pump();
    // The cause is reported to diagnostics once, at the boundary.
    expect(tester.takeException(), isA<Exception>());
    expect(find.text('Golem could not finish starting.'), findsOneWidget);
    expect(find.byKey(const Key('launch-splash')), findsOneWidget);

    await tester.tap(find.byKey(const Key('splash-retry')));
    await tester.pump();
    await tester.pump();
    await pumpThroughTheatre(tester);

    expect(calls, 2);
    expect(find.byKey(const Key('launch-splash')), findsNothing);
    expect(find.byKey(const Key('empty-chat')), findsOneWidget);
  });

  testWidgets('a successful launch composes exactly once', (tester) async {
    setViewport(tester);
    final directory = scratch();
    var calls = 0;
    await tester.pumpWidget(
      BootstrapApp(
        compose: () async {
          calls++;
          return launchDependenciesWith(directory: directory);
        },
      ),
    );
    await tester.pump();
    await pumpThroughTheatre(tester);
    expect(calls, 1);
    expect(find.byKey(const Key('empty-chat')), findsOneWidget);
  });

  testWidgets('a double-tap on Try again runs a single retry', (tester) async {
    setViewport(tester);
    var calls = 0;
    final gates = <Completer<void>>[];
    Future<LaunchDependencies> compose() async {
      calls++;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      throw Exception('still failing');
    }

    await tester.pumpWidget(BootstrapApp(compose: compose));
    gates.single.complete();
    await tester.pump();
    expect(tester.takeException(), isA<Exception>());

    // Two tap-ups can land before the rebuild removes the button; while the
    // first retry's composition is still in flight, the guard must collapse
    // the second tap into it.
    await tester.tap(find.byKey(const Key('splash-retry')));
    await tester.tap(
      find.byKey(const Key('splash-retry')),
      warnIfMissed: false,
    );
    expect(calls, 2);
    gates.last.complete();
    await tester.pump();
    expect(tester.takeException(), isA<Exception>());
    expect(calls, 2);
  });

  testWidgets('a timed out composition offers retry', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(
      BootstrapApp(
        compose: () async =>
            throw TimeoutException('launch', const Duration(seconds: 8)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isA<TimeoutException>());
    expect(
      find.text('Starting is taking longer than expected.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('splash-retry')), findsOneWidget);
  });

  testWidgets('an invalid configuration is terminal', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(
      BootstrapApp(compose: () async => throw StateError('bad dart-define')),
    );
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(
      find.text('This build of Golem is misconfigured and cannot start.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('splash-retry')), findsNothing);
  });

  test('the composition deadline bounds a hung directory lookup', () async {
    // The default binary messenger has no path_provider handler on the host,
    // so install one that never answers: the real composeLaunch must fail by
    // deadline, not hang the launch.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(
      channel,
      (call) => Completer<Object?>().future,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
      composeLaunch(requiredDeadline: const Duration(milliseconds: 100)),
      throwsA(isA<TimeoutException>()),
    );
  });

  group('classifyLaunchFailure', () {
    test('timeout is timedOut', () {
      expect(
        classifyLaunchFailure(TimeoutException('launch')).kind,
        LaunchFailureKind.timedOut,
      );
    });
    test('platform channel failures are storageUnavailable', () {
      expect(
        classifyLaunchFailure(MissingPluginException()).kind,
        LaunchFailureKind.storageUnavailable,
      );
      expect(
        classifyLaunchFailure(PlatformException(code: 'io')).kind,
        LaunchFailureKind.storageUnavailable,
      );
    });
    test('errors are invalidConfiguration and not retryable', () {
      final failure = classifyLaunchFailure(StateError('bad define'));
      expect(failure.kind, LaunchFailureKind.invalidConfiguration);
      expect(failure.retryable, isFalse);
    });
    test('anything else is unknown and retryable', () {
      final failure = classifyLaunchFailure(Exception('surprise'));
      expect(failure.kind, LaunchFailureKind.unknown);
      expect(failure.retryable, isTrue);
    });
  });
}
