// The bootstrap gate: the first frame waits for the real composition, so the
// shell is the first thing drawn (#159); a launch failure renders as a
// truthful, retryable pane — never the native launch screen forever — and Try
// again reruns the real composition (#66).
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/app.dart';
import 'package:golem_flutter/app/bootstrap.dart';
import 'package:golem_flutter/app/lab_app.dart';
import 'package:golem_flutter/app/launch_composition.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/services/artifact_downloader.dart';
import 'package:golem_flutter/core/services/device_storage.dart';

import 'support/harness.dart';

/// Lets the composed scope build its stores — explicit pumps, never
/// pumpAndSettle across the gate.
Future<void> pumpIntoShell(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory scratch() {
    final directory = Directory.systemTemp.createTempSync('golem-bootstrap-');
    addTearDown(() => directory.deleteSync(recursive: true));
    return directory;
  }

  test('launch fault injection is internal-identity only', () {
    expect(shouldInjectLaunchFailure(AppIdentity.dev, 1), isTrue);
    expect(shouldInjectLaunchFailure(AppIdentity.qa, 1), isTrue);
    expect(shouldInjectLaunchFailure(AppIdentity.lab, 1), isTrue);
    expect(shouldInjectLaunchFailure(AppIdentity.production, 1), isFalse);
    expect(shouldInjectLaunchFailure(AppIdentity.dev, 0), isFalse);
  });

  test('the lab keeps its documents under its own support container', () {
    // On an unsandboxed Mac the documents directory is the user's real
    // ~/Documents, shared by every flavor, so the lab's models and its
    // downloads both move under application support — and to the same place,
    // or a transfer would land where verification never looks (ADR 0021).
    final support = Directory('/support/app.golem.lab');
    final documents = Directory('/Users/jan/Documents');
    final lab = storageLayoutFor(
      AppIdentity.lab,
      support: support,
      documents: documents,
    );
    expect(lab.documents.path, '/support/app.golem.lab/Documents');
    expect(lab.downloadRoot, ArtifactDownloadRoot.applicationSupport);
    expect(lab.downloadSubdirectory, 'Documents');
    for (final identity in AppIdentity.values.where((i) => !i.isLab)) {
      final layout = storageLayoutFor(
        identity,
        support: support,
        documents: documents,
      );
      expect(layout.documents.path, documents.path, reason: identity.name);
      expect(layout.downloadRoot, ArtifactDownloadRoot.documents);
      expect(layout.downloadSubdirectory, isEmpty);
    }
  });

  testWidgets('a failed composition retries into the app', (tester) async {
    setViewport(tester);
    final directory = scratch();
    var calls = 0;
    Future<LaunchDependencies> compose(AppIdentity identity) async {
      calls++;
      if (calls == 1) throw Exception('first composition fails');
      return launchDependenciesWith(directory: directory);
    }

    await tester.pumpWidget(
      BootstrapApp(identity: AppIdentity.dev, compose: compose),
    );
    await tester.pump();
    // The cause is reported to diagnostics once, at the boundary.
    expect(tester.takeException(), isA<Exception>());
    expect(find.text('Golem could not finish starting.'), findsOneWidget);
    expect(find.byKey(const Key('launch-splash')), findsOneWidget);

    await tester.tap(find.byKey(const Key('splash-retry')));
    await tester.pump();
    await tester.pump();
    await pumpIntoShell(tester);

    expect(calls, 2);
    expect(find.byKey(const Key('launch-splash')), findsNothing);
    expect(find.byKey(const Key('first-run-welcome')), findsOneWidget);
  });

  testWidgets('a successful launch composes exactly once', (tester) async {
    setViewport(tester);
    final directory = scratch();
    var calls = 0;
    await tester.pumpWidget(
      BootstrapApp(
        identity: AppIdentity.dev,
        compose: (identity) async {
          calls++;
          return launchDependenciesWith(directory: directory);
        },
      ),
    );
    await tester.pump();
    await pumpIntoShell(tester);
    expect(calls, 1);
    expect(find.byKey(const Key('first-run-welcome')), findsOneWidget);
    // Host tests are a dev build: the consumer root, never the lab's.
    expect(kLabBuild, isFalse);
    expect(find.byType(GolemApp), findsOneWidget);
    expect(find.byType(LabApp), findsNothing);
  });

  testWidgets('the first frame waits for the composition', (tester) async {
    setViewport(tester);
    final directory = scratch();
    final gate = Completer<void>();
    await tester.pumpWidget(
      BootstrapApp(
        identity: AppIdentity.dev,
        compose: (identity) async {
          await gate.future;
          return launchDependenciesWith(directory: directory);
        },
      ),
    );
    // Nothing is sent to the engine while the real work runs: the native
    // launch screen stays up instead of a Flutter-drawn splash, and there is
    // no hold, bar, or spinner in front of the shell.
    expect(tester.binding.sendFramesToEngine, isFalse);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    // Nor is the pane built for a frame nobody sees: the deferred tree is
    // the launch screen's navy and nothing else.
    expect(find.byType(LaunchPane), findsNothing);
    expect(find.byKey(const Key('launch-splash')), findsOneWidget);
    gate.complete();
    await tester.pump();
    // Composed, but still deferred: the preferences store has not answered,
    // and the first frame must already be in the stored theme.
    expect(tester.binding.sendFramesToEngine, isFalse);
    await pumpIntoShell(tester);
    expect(tester.binding.sendFramesToEngine, isTrue);
    expect(find.byKey(const Key('launch-splash')), findsNothing);
    await tester.pump();
    expect(find.byKey(const Key('first-run-welcome')), findsOneWidget);
  });

  testWidgets('a failed composition releases the first frame', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(
      BootstrapApp(
        identity: AppIdentity.dev,
        compose: (identity) async => throw Exception('no launch'),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isA<Exception>());
    expect(tester.binding.sendFramesToEngine, isTrue);
    expect(find.byKey(const Key('launch-splash')), findsOneWidget);
  });

  testWidgets('a double-tap on Try again runs a single retry', (tester) async {
    setViewport(tester);
    var calls = 0;
    final gates = <Completer<void>>[];
    Future<LaunchDependencies> compose(AppIdentity identity) async {
      calls++;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      throw Exception('still failing');
    }

    await tester.pumpWidget(
      BootstrapApp(identity: AppIdentity.dev, compose: compose),
    );
    gates.single.complete();
    await tester.pump();
    expect(tester.takeException(), isA<Exception>());
    // The deferred tree was a bare box; the pane's app mounts its route on
    // the frame after the failure lands.
    await tester.pump();

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
        identity: AppIdentity.dev,
        compose: (identity) async =>
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
      BootstrapApp(
        identity: AppIdentity.dev,
        compose: (identity) async => throw StateError('bad dart-define'),
      ),
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
      composeLaunch(
        identity: AppIdentity.dev,
        requiredDeadline: const Duration(milliseconds: 100),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'composition keeps both storage roots out of platform backups',
    () async {
      // Nothing Golem stores leaves the phone (ADR 0016): application support
      // holds chats, attachments and preferences, documents holds the weights,
      // and the flag on each root covers everything beneath it.
      final root = Directory.systemTemp.createTempSync('golem-backup-');
      addTearDown(() => root.deleteSync(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      const storage = MethodChannel('app.golem/storage');
      final excluded = <String>[];
      messenger.setMockMethodCallHandler(
        paths,
        (call) async => '${root.path}/${call.method}',
      );
      messenger.setMockMethodCallHandler(storage, (call) async {
        if (call.method == 'excludeFromBackup') {
          excluded.add((call.arguments as Map)['path'] as String);
        }
        return null;
      });
      // Best effort and bounded: a channel that never answers the flag write
      // must not hold the launch past its own deadline.
      await expectLater(
        keepOutOfBackups(
          _HangingExclusion(),
          [root],
          deadline: const Duration(milliseconds: 20),
        ).timeout(const Duration(seconds: 1)),
        completes,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(paths, null);
        messenger.setMockMethodCallHandler(storage, null);
      });
      await composeLaunch(identity: AppIdentity.qa);
      expect(excluded, [
        '${root.path}/getApplicationSupportDirectory',
        '${root.path}/getApplicationDocumentsDirectory',
      ]);
    },
  );

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

final class _HangingExclusion implements BackupExclusion {
  @override
  Future<void> exclude(String path) => Completer<void>().future;
}
