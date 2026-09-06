import 'dart:ui' show Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/runtime.dart'
    show BrokerSamplingParameters;
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/lab/widgets/lab_controls.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/features/lab/application/lab_bench_controller.dart';
import 'package:golem_flutter/features/lab/domain/lab_run.dart';
import 'package:golem_flutter/features/lab/domain/lab_run_settings.dart';
import 'package:golem_flutter/features/lab/widgets/run_card.dart';
import 'package:golem_flutter/l10n/l10n.dart';

import '../support/harness.dart';

const _installed = ModelState(
  artifacts: {
    'gemma4-gguf': ArtifactStatus(phase: ArtifactPhase.installed),
    'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
    'qwen35-gguf': ArtifactStatus(phase: ArtifactPhase.installed),
    'qwen35-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
  },
);

/// The fake's whole observed stream, at a cadence the pumps below step
/// through deterministically.
FakeInferenceRepository _fake() =>
    FakeInferenceRepository(eventDelay: const Duration(milliseconds: 30));

Finder get _composer => find.byKey(const Key('lab-composer'));
Finder get _run => find.byKey(const Key('lab-run-button'));
Finder get _stop => find.byKey(const Key('lab-stop-button'));

/// Pumps until the active run reaches [phase] or the deadline passes.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration step = const Duration(milliseconds: 30),
  int maxSteps = 400,
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (done()) return;
    await tester.pump(step);
  }
  fail('the bench never reached the expected state');
}

/// Runs the fake stream to its end. `pumpAndSettle` alone returns between
/// two of the fake's delayed events, when no frame is pending.
Future<void> _finish(WidgetTester tester, ProviderContainer container) async {
  await _pumpUntil(
    tester,
    () =>
        container.read(labBenchControllerProvider).activeRun?.isTerminal ??
        true,
  );
  await tester.pumpAndSettle();
}

Future<void> _arm(
  WidgetTester tester,
  ProviderContainer container,
  String key,
) async {
  expect(container.read(labBenchControllerProvider.notifier).arm(key), isTrue);
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String prompt) async {
  await tester.enterText(_composer, prompt);
  await tester.pump();
  await tester.tap(_run);
  await tester.pump();
}

Future<void> _pressMeta(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('empty bench ${brightness.name} golden', (tester) async {
      await pumpLabShell(tester, brightness: brightness, model: _installed);
      expect(find.byKey(const Key('lab-empty')), findsOneWidget);
      expect(find.byKey(const Key('lab-rig-locked')), findsNothing);
      // Nothing armed: Run and the settings are offered but inert — a draft
      // with no profile to validate against could commit anything.
      expect(pressedHandler(tester, _run), isNull);
      expect(
        pressedHandler(tester, find.byKey(const Key('lab-settings-button'))),
        isNull,
      );
      await expectLater(
        find.byKey(const Key('lab-shell')),
        matchesGoldenFile(
          '../goldens/lab-empty-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: macChrome);
  }

  testWidgets('the smallest window still lays the bench out', (tester) async {
    final container = await pumpLabShell(
      tester,
      size: labMinViewport,
      model: _installed,
    );
    await _arm(tester, container, 'qwen35-gguf');
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('lab-shell')),
      matchesGoldenFile('../goldens/lab-empty-min${chromeSuffix()}.png'),
    );
  }, variant: macChrome);

  testWidgets('arming from the library fills the Rig and unlocks Run', (
    tester,
  ) async {
    final container = await pumpLabShell(tester, model: _installed);
    expect(find.text('Choose model'), findsOneWidget);
    // The library row arms the family on its first engine; the engine
    // chooser moves it.
    await tester.tap(find.byKey(const Key('lab-library-gemma4')));
    await tester.pumpAndSettle();
    expect(
      container.read(labBenchControllerProvider).armed?.displayName,
      'Gemma 4 E2B',
    );
    await tester.tap(find.byKey(const Key('lab-engine-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-engine-gguf')));
    await tester.pumpAndSettle();
    final bench = container.read(labBenchControllerProvider);
    expect(bench.armed?.key, 'gemma4-gguf');
    expect(find.text('Gemma 4 E2B'), findsWidgets);
    expect(
      tester
          .getSemantics(find.byKey(const Key('lab-library-gemma4')))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(find.byKey(const Key('lab-artifact-delete')), findsOneWidget);
    expect(find.byKey(const Key('lab-contract-chip')), findsOneWidget);
    // Run needs text too.
    expect(pressedHandler(tester, _run), isNull);
    await tester.enterText(_composer, 'Hello');
    await tester.pump();
    expect(pressedHandler(tester, _run), isNotNull);
  }, variant: macChrome);

  testWidgets('Delete asks the consent Models and Storage ask', (tester) async {
    final models = _RecordingModels(_installed);
    final container = await pumpLabShell(
      tester,
      model: _installed,
      models: models,
      inference: _fake(),
    );
    await _arm(tester, container, 'gemma4-gguf');
    final delete = find.byKey(const Key('lab-artifact-delete'));
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-delete-dialog')), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(models.deleted, isEmpty, reason: 'Keep deletes nothing');
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-model-delete')));
    await tester.pumpAndSettle();
    expect(models.deleted, ['gemma4-gguf']);
  }, variant: macChrome);

  testWidgets('the artifact chip offers the transfer the store allows', (
    tester,
  ) async {
    for (final (phase, key) in const [
      (ArtifactPhase.paused, 'lab-artifact-resume'),
      (ArtifactPhase.failed, 'lab-artifact-retry'),
      (ArtifactPhase.downloading, 'lab-artifact-pause'),
      (ArtifactPhase.notDownloaded, 'lab-artifact-download'),
    ]) {
      final container = await pumpLabShell(
        tester,
        model: ModelState(
          artifacts: {'gemma4-gguf': ArtifactStatus(phase: phase)},
        ),
      );
      await _arm(tester, container, 'gemma4-gguf');
      expect(find.byKey(Key(key)), findsOneWidget, reason: phase.name);
    }
    // Download asks first, like the phone: the consent sheet, never a
    // transfer on arming or on a click.
    await tester.tap(find.byKey(const Key('lab-artifact-download')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-download-consent')), findsOneWidget);
    await tester.tap(find.byKey(const Key('model-download-not-now')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab-artifact-download')), findsOneWidget);
  }, variant: macChrome);

  for (final brightness in Brightness.values) {
    testWidgets('a run in flight, ${brightness.name} golden', (tester) async {
      DateTime? pinned;
      final container = await pumpLabShell(
        tester,
        brightness: brightness,
        model: _installed,
        inference: _fake(),
        clock: () => pinned ?? DateTime.now(),
      );
      await _arm(tester, container, 'gemma4-gguf');
      await _send(tester, 'Name the largest planet in the solar system.');
      LabRun run() => container.read(labBenchControllerProvider).activeRun!;
      // Loading: the Rig is locked, Stop replaces Run, the field is
      // read-only and still focused, the sidebar's chooser rows are inert.
      pinned = run().configuration.startedAt.add(
        const Duration(milliseconds: 1200),
      );
      await tester.pump();
      expect(run().phase, LabRunPhase.loading);
      expect(find.byKey(const Key('lab-rig-locked')), findsOneWidget);
      expect(_stop, findsOneWidget);
      expect(tester.widget<CupertinoTextField>(_composer).readOnly, isTrue);
      expect(
        tester.widget<CupertinoTextField>(_composer).focusNode!.hasFocus,
        isTrue,
      );
      expect(
        pressedHandler(tester, find.byKey(const Key('lab-new-conversation'))),
        isNull,
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('lab-library-qwen35')))
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      expect(find.byKey(const Key('lab-phase-load')), findsOneWidget);
      if (brightness == Brightness.light) {
        await expectLater(
          find.byKey(const Key('lab-shell')),
          matchesGoldenFile('../goldens/lab-loading${chromeSuffix()}.png'),
        );
      }

      // Generating: tokens arrive, the chart draws, the footer says live.
      await _pumpUntil(
        tester,
        () =>
            run().phase == LabRunPhase.generating &&
            run().telemetry.instantsMs.length >= 12,
      );
      pinned = run().configuration.startedAt.add(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byKey(const Key('lab-phase-generate')), findsOneWidget);
      expect(find.byKey(const Key('lab-sparkline')), findsOneWidget);
      expect(find.textContaining('Live'), findsOneWidget);
      await expectLater(
        find.byKey(const Key('lab-shell')),
        matchesGoldenFile(
          '../goldens/lab-streaming-${brightness.name}${chromeSuffix()}.png',
        ),
      );

      // Done: every phase has its number, and the footer names the run.
      await _finish(tester, container);
      final finished = run();
      expect(finished.phase, LabRunPhase.completed);
      expect(finished.metrics?.timeToFirstTokenSeconds, 0.31);
      expect(find.byKey(const Key('lab-result-chip')), findsOneWidget);
      expect(find.byKey(const Key('lab-rig-locked')), findsNothing);
      expect(find.textContaining('0.31'), findsWidgets);
      expect(find.textContaining('run-1'), findsOneWidget);
      expect(tester.widget<CupertinoTextField>(_composer).readOnly, isFalse);
      expect(
        tester.widget<CupertinoTextField>(_composer).focusNode!.hasFocus,
        isTrue,
        reason: 'the field keeps focus across a run',
      );
      await expectLater(
        find.byKey(const Key('lab-shell')),
        matchesGoldenFile(
          '../goldens/lab-completed-${brightness.name}${chromeSuffix()}.png',
        ),
      );
    }, variant: macChrome);
  }

  testWidgets('the transcript follows a run only while it is at the end', (
    tester,
  ) async {
    // The small window, and a slow stream: the card outgrows the viewport
    // while there are still parts to come.
    final container = await pumpLabShell(
      tester,
      size: labMinViewport,
      model: _installed,
      inference: FakeInferenceRepository(
        eventDelay: const Duration(milliseconds: 300),
      ),
    );
    await _arm(tester, container, 'gemma4-gguf');
    await _send(tester, 'Explain in about 150 words why the sky is blue.');
    LabRun run() => container.read(labBenchControllerProvider).activeRun!;
    final scroll = tester
        .widget<ListView>(find.byKey(const Key('lab-transcript')))
        .controller!;
    // Until the card outgrows the viewport, there is nothing to follow.
    await _pumpUntil(
      tester,
      () => scroll.hasClients && scroll.position.maxScrollExtent > 100,
    );
    // One frame to lay the grown card out, one for the follow's jump.
    await tester.pump();
    await tester.pump();
    expect(
      scroll.position.pixels,
      scroll.position.maxScrollExtent,
      reason: 'a fresh run is followed to its end',
    );
    // The reader drags back up mid-run; the next publishes must not yank
    // the view down again, nor the terminal one.
    // From the gutter, clear of the card's own gestures.
    final list = tester.getRect(find.byKey(const Key('lab-transcript')));
    await tester.dragFrom(
      Offset(list.left + 12, list.center.dy),
      const Offset(0, 400),
    );
    // Let the bounce settle before reading where the reader left the view.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final held = scroll.position.pixels;
    expect(held, greaterThanOrEqualTo(0));
    expect(held, lessThan(scroll.position.maxScrollExtent - 50));
    final lengthBefore = run().answer.length;
    await _pumpUntil(tester, () => run().answer.length > lengthBefore + 20);
    await tester.pump();
    await tester.pump();
    expect(scroll.position.pixels, held);
    await _finish(tester, container);
    expect(scroll.position.pixels, held, reason: 'nor the terminal publish');
  }, variant: macChrome);

  testWidgets('Stop keeps the partial output and Retry runs it again', (
    tester,
  ) async {
    final container = await pumpLabShell(
      tester,
      model: _installed,
      inference: _fake(),
    );
    await _arm(tester, container, 'qwen35-mlx');
    await _send(tester, 'Explain in about 150 words why the sky is blue.');
    LabRun run() => container.read(labBenchControllerProvider).activeRun!;
    await _pumpUntil(tester, () => run().answer.isNotEmpty);
    await tester.tap(_stop);
    await tester.pump();
    expect(run().cancelling, isTrue);
    await _pumpUntil(tester, () => run().isTerminal);
    await tester.pumpAndSettle();
    expect(run().phase, LabRunPhase.cancelled);
    expect(run().answer, isNotEmpty);
    expect(find.byKey(const Key('lab-cancelled-chip')), findsOneWidget);
    expect(find.textContaining('run-1'), findsOneWidget);
    await expectLater(
      find.byKey(const Key('lab-shell')),
      matchesGoldenFile('../goldens/lab-cancelled${chromeSuffix()}.png'),
    );

    await tester.ensureVisible(find.byKey(const Key('lab-retry')));
    await tester.tap(find.byKey(const Key('lab-retry')));
    await _finish(tester, container);
    final conversation = container
        .read(labBenchControllerProvider)
        .session
        .active!;
    expect(conversation.runs.map((r) => r.phase), [
      LabRunPhase.cancelled,
      LabRunPhase.completed,
    ]);
    expect(conversation.runs.last.prompt, conversation.runs.first.prompt);
    // Only the latest turn offers Retry, and a completed one does not.
    expect(find.byKey(const Key('lab-retry')), findsNothing);
  }, variant: macChrome);

  testWidgets('a failed run keeps its snapshot and offers Retry', (
    tester,
  ) async {
    final container = await pumpLabShell(
      tester,
      model: _installed,
      inference: FakeInferenceRepository(eventDelay: Duration.zero),
    );
    await _arm(tester, container, 'gemma4-mlx');
    await _send(tester, '[fail] please');
    await _finish(tester, container);
    final run = container.read(labBenchControllerProvider).activeRun!;
    expect(run.phase, LabRunPhase.failed);
    expect(find.byKey(const Key('lab-failed-notice')), findsOneWidget);
    expect(find.byKey(const Key('lab-retry')), findsOneWidget);
    expect(find.textContaining('run-1'), findsOneWidget);
    // The Rig is free again under the same configuration.
    expect(find.byKey(const Key('lab-rig-locked')), findsNothing);
    await expectLater(
      find.byKey(const Key('lab-shell')),
      matchesGoldenFile('../goldens/lab-failed${chromeSuffix()}.png'),
    );
  }, variant: macChrome);

  testWidgets(
    'a second turn joins the conversation; a change starts a new one',
    (tester) async {
      final container = await pumpLabShell(
        tester,
        model: _installed,
        inference: FakeInferenceRepository(eventDelay: Duration.zero),
      );
      await _arm(tester, container, 'gemma4-gguf');
      await _send(tester, 'One');
      await _finish(tester, container);
      await _send(tester, 'Two');
      await _finish(tester, container);
      // The transcript builds lazily and follows the run, so the header is
      // reached by scrolling back up.
      await tester.scrollUntilVisible(
        find.textContaining('2 TURNS'),
        -200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('lab-transcript')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('2 TURNS'), findsOneWidget);
      // Lazily built: the cards on screen are at most the runs recorded.
      expect(find.byType(RunCard), findsAtLeastNWidgets(1));
      expect(container.read(labBenchControllerProvider).session.runCount, 2);
      // Switching the engine closes the conversation; its cards stay.
      await tester.tap(find.byKey(const Key('lab-engine-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lab-engine-mlx')));
      await tester.pumpAndSettle();
      final session = container.read(labBenchControllerProvider).session;
      expect(session.conversations, hasLength(2));
      expect(session.active!.runs, isEmpty);
      expect(session.runCount, 2, reason: 'the cards stay');
      expect(find.byType(RunCard), findsAtLeastNWidgets(1));
      expect(find.text('MLX'), findsWidgets);
    },
    variant: macChrome,
  );

  testWidgets('the settings sheet refuses a bad draft and applies a good one', (
    tester,
  ) async {
    final container = await pumpLabShell(tester, model: _installed);
    await _arm(tester, container, 'gemma4-gguf');
    await tester.tap(find.byKey(const Key('lab-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab-settings-sheet')), findsOneWidget);
    await expectLater(
      find.byKey(const Key('lab-settings-sheet')),
      matchesGoldenFile('../goldens/lab-settings${chromeSuffix()}.png'),
    );
    // Context down to the floor and the budget above it: refused, with the
    // reason, and nothing applied.
    final contextMinus = find.byKey(const Key('lab-setting-context-minus'));
    for (var i = 0; i < 12; i++) {
      await tester.tap(contextMinus);
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('lab-setting-max-tokens-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lab-settings-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab-settings-sheet')), findsOneWidget);
    expect(find.textContaining('512'), findsWidgets);
    expect(
      container.read(labBenchControllerProvider).settings.contextLength,
      isNull,
    );
    // Back to the default on both, a seed, and it applies as one change.
    await tester.tap(find.byKey(const Key('lab-setting-context-reset')));
    await tester.tap(find.byKey(const Key('lab-setting-max-tokens-reset')));
    await tester.enterText(find.byKey(const Key('lab-setting-seed')), '7');
    await tester.pump();
    await tester.tap(find.byKey(const Key('lab-settings-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lab-settings-sheet')), findsNothing);
    final settings = container.read(labBenchControllerProvider).settings;
    expect(settings.seed, 7);
    expect(settings.contextLength, isNull);
    expect(find.textContaining('seed 7'), findsOneWidget);

    // A committed override is not a default: reopen, commit +128 on the
    // budget, reopen again and Reset shows the profile's 2048, not 2176.
    await tester.tap(find.byKey(const Key('lab-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lab-setting-max-tokens-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lab-settings-apply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('max 2176'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lab-settings-button')));
    await tester.pumpAndSettle();
    expect(find.text('2176'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lab-setting-max-tokens-reset')));
    await tester.pump();
    expect(find.text('2048'), findsOneWidget);
    expect(find.text('2176'), findsNothing);
    await tester.tap(find.byKey(const Key('lab-settings-cancel')));
    await tester.pumpAndSettle();

    // Pinning follows the draft's mode: Qwen pins its sampling in reasoning
    // mode, and the sheet says so the moment the toggle flips.
    expect(
      container
          .read(labBenchControllerProvider.notifier)
          .updateSettings(const LabRunSettings()),
      isEmpty,
    );
    await _arm(tester, container, 'qwen35-gguf');
    await tester.tap(find.byKey(const Key('lab-settings-button')));
    await tester.pumpAndSettle();
    expect(find.text('pinned'), findsNothing);
    expect(find.text('4096'), findsNothing);
    // A user value under the direct mode, then the toggle: the pinned row
    // shows the profile's value, which is what will be sent, not the draft's.
    await tester.tap(find.byKey(const Key('lab-setting-temperature-plus')));
    await tester.pump();
    expect(find.text('0.8'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lab-setting-reasoning')));
    await tester.pumpAndSettle();
    expect(find.text('pinned'), findsNWidgets(3));
    expect(find.text('1.0'), findsOneWidget, reason: 'the profile\'s pin');
    expect(find.text('0.8'), findsNothing);
    expect(find.text('4096'), findsOneWidget, reason: 'the reasoning budget');
    expect(
      pressedHandler(
        tester,
        find.byKey(const Key('lab-setting-temperature-plus')),
      ),
      isNull,
    );
  }, variant: macChrome);

  testWidgets('⌘↩ runs, Escape stops, ⌘N starts a conversation', (
    tester,
  ) async {
    final container = await pumpLabShell(
      tester,
      model: _installed,
      inference: _fake(),
    );
    await _arm(tester, container, 'gemma4-gguf');
    await tester.tap(_composer);
    await tester.enterText(_composer, 'Who wrote the play Hamlet?');
    await tester.pump();
    await _pressMeta(tester, LogicalKeyboardKey.enter);
    LabBenchState bench() => container.read(labBenchControllerProvider);
    expect(bench().locked, isTrue);
    expect(_stop, findsOneWidget);
    // ⌘N is refused while a run is in flight.
    await _pressMeta(tester, LogicalKeyboardKey.keyN);
    expect(bench().session.conversations, hasLength(1));
    await _pumpUntil(tester, () => bench().activeRun!.answer.isNotEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(bench().activeRun!.cancelling, isTrue);
    await _finish(tester, container);
    expect(bench().activeRun!.phase, LabRunPhase.cancelled);
    await _pressMeta(tester, LogicalKeyboardKey.keyN);
    expect(bench().session.conversations, hasLength(2));
    expect(
      tester.widget<CupertinoTextField>(_composer).focusNode!.hasFocus,
      isTrue,
    );
    // The persistent band keeps the newest run across the new conversation.
    expect(
      find.descendant(
        of: find.byKey(const Key('lab-footer')),
        matching: find.textContaining('run-1'),
      ),
      findsOneWidget,
    );
    // A tray prompt is a keyboard target too: Tab reaches it, Space picks.
    const tray = Key('lab-tray-factual-capital');
    bool trayFocused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<LabFocusable>()
            ?.key ==
        tray;
    for (var i = 0; i < 40 && !trayFocused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(trayFocused(), isTrue, reason: 'Tab reaches the tray prompt');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    final composer = tester.widget<CupertinoTextField>(_composer).controller!;
    expect(composer.text, contains('capital of France'));
    expect(
      composer.selection.baseOffset,
      composer.text.length,
      reason: 'the caret follows the picked prompt',
    );
  }, variant: macChrome);

  testWidgets('run edges are announced once; chips stay quiet', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await pumpLabShell(
      tester,
      model: _installed,
      inference: _fake(),
    );
    await _arm(tester, container, 'gemma4-gguf');
    tester.takeAnnouncements();
    await _send(tester, 'Hello');
    await tester.pump(const Duration(milliseconds: 100));
    var announced = tester.takeAnnouncements().map((e) => e.message).toList();
    expect(announced, ['Run started']);
    await _finish(tester, container);
    announced = tester.takeAnnouncements().map((e) => e.message).toList();
    expect(announced, ['Run finished']);
    for (final key in const [
      'lab-phase-load',
      'lab-phase-read',
      'lab-phase-generate',
      'lab-result-chip',
    ]) {
      expect(
        tester.getSemantics(find.byKey(Key(key))).flagsCollection.isLiveRegion,
        isFalse,
        reason: key,
      );
    }
    // The sparkline reads as a sentence, not as pixels.
    expect(
      tester.getSemantics(find.byKey(const Key('lab-sparkline'))).label,
      contains('median'),
    );
    expect(
      tester.getSemantics(_composer),
      isSemantics(isTextField: true, isEnabled: true, isReadOnly: false),
    );
    handle.dispose();
  }, variant: macChrome);

  testWidgets('reduced motion swaps the indeterminate load for a mark', (
    tester,
  ) async {
    final run = LabRun(
      id: 'run-x',
      prompt: 'Hello',
      configuration: LabRunConfiguration(
        catalogKey: 'gemma4-mlx',
        displayName: 'Gemma 4 E2B',
        engine: ModelEngine.mlx,
        profileKey: 'gemma4',
        quantization: '4bit',
        revision: 'abc',
        sampling: const BrokerSamplingParameters(
          temperature: 1,
          topP: 0.95,
          topK: 64,
          maxTokens: 1024,
          contextLength: 4096,
          seed: null,
          stopSequences: [],
          stopTokenIds: [],
        ),
        settings: const LabRunSettings(),
        engineBuild: 'mlx-swift 0.31.6',
        artifact: const LabArtifactProvenance(
          fileCount: 4,
          totalBytes: 3000000000,
          verified: true,
        ),
        device: null,
        startedAt: DateTime(2026, 9, 5, 12),
      ),
    );
    for (final reduced in [false, true]) {
      setViewport(tester, size: labViewport);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(disableAnimations: reduced),
          child: wrapApp(
            child: CupertinoPageScaffold(
              child: Center(
                child: SizedBox(
                  width: 700,
                  child: RunCard(run: run, now: DateTime(2026, 9, 5, 12, 0, 2)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byType(CupertinoActivityIndicator),
        reduced ? findsNothing : findsOneWidget,
        reason: 'reduced motion $reduced',
      );
      expect(find.textContaining('2.0'), findsWidgets);
    }
  }, variant: macChrome);

  testWidgets('pointer targets, labels and contrast in every state', (
    tester,
  ) async {
    Future<void> sweep(String state, {bool contrast = true}) async {
      await expectLater(
        tester,
        meetsGuideline(tapTargetGuideline),
        reason: state,
      );
      await expectLater(
        tester,
        meetsGuideline(labeledTapTargetGuideline),
        reason: state,
      );
      if (contrast) {
        await expectLater(
          tester,
          meetsGuideline(textContrastGuideline),
          reason: state,
        );
      }
    }

    for (final brightness in Brightness.values) {
      final container = await pumpLabShell(
        tester,
        brightness: brightness,
        model: _installed,
        inference: _fake(),
      );
      await sweep('empty ${brightness.name}');
      await _arm(tester, container, 'gemma4-gguf');
      await sweep('armed ${brightness.name}');
      await _send(tester, 'Hello');
      LabRun run() => container.read(labBenchControllerProvider).activeRun!;
      await _pumpUntil(tester, () => run().answer.isNotEmpty);
      await sweep('streaming ${brightness.name}');
      await _finish(tester, container);
      await sweep('completed ${brightness.name}');
      await tester.tap(find.byKey(const Key('lab-settings-button')));
      await tester.pumpAndSettle();
      await sweep('settings ${brightness.name}');
      await tester.tap(find.byKey(const Key('lab-settings-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lab-tray-all')));
      await tester.pumpAndSettle();
      await sweep('tray ${brightness.name}');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('lab-tray-sheet')),
          matching: find.byKey(const Key('lab-tray-factual-author')),
        ),
      );
      await tester.pumpAndSettle();
      await _send(tester, '[fail] now');
      await _finish(tester, container);
      await sweep('failed ${brightness.name}');
    }
    // Nothing installed: the caution chip and Download.
    final bare = await pumpLabShell(tester);
    await _arm(tester, bare, 'gemma4-gguf');
    await sweep('missing artifact');
  }, variant: macChrome);

  testWidgets('every bench state survives a 1.6x text scale', (tester) async {
    final container = await pumpLabShell(
      tester,
      size: labMinViewport,
      textScale: 1.6,
      model: _installed,
      inference: FakeInferenceRepository(eventDelay: Duration.zero),
    );
    expect(tester.takeException(), isNull, reason: 'empty');
    await _arm(tester, container, 'qwen35-gguf');
    expect(tester.takeException(), isNull, reason: 'armed');
    await _send(tester, 'Hello');
    await _finish(tester, container);
    expect(
      container.read(labBenchControllerProvider).activeRun!.phase,
      LabRunPhase.completed,
    );
    expect(tester.takeException(), isNull, reason: 'completed');
    await tester.tap(find.byKey(const Key('lab-settings-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'settings');
  }, variant: macChrome);

  testWidgets('every catalog lays the bench out at the smallest window', (
    tester,
  ) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final container = await pumpLabShell(
        tester,
        size: labMinViewport,
        locale: locale,
        model: _installed,
        inference: FakeInferenceRepository(eventDelay: Duration.zero),
      );
      expect(tester.takeException(), isNull, reason: '$locale empty');
      await _arm(tester, container, 'gemma4-gguf');
      await _send(tester, 'Hello');
      await _finish(tester, container);
      expect(tester.takeException(), isNull, reason: '$locale completed');
      expect(find.byKey(const Key('lab-result-chip')), findsOneWidget);
    }
  }, variant: macChrome);
}

/// Static state that remembers what was deleted, since the bench's Delete
/// is only provable by what reaches the store.
final class _RecordingModels implements ModelManagementRepository {
  _RecordingModels(ModelState state) : _inner = StaticModels(state);
  final StaticModels _inner;
  final deleted = <String>[];

  @override
  Future<ModelState> load() => _inner.load();
  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    RuntimeFailureKind? failure,
  }) => _inner.recordRuntime(phase, failure: failure);
  @override
  Stream<ModelState> download(String artifactKey) =>
      _inner.download(artifactKey);
  @override
  Future<ModelState> pause(String artifactKey) => _inner.pause(artifactKey);
  @override
  Future<ModelState> cancel(String artifactKey) => _inner.cancel(artifactKey);
  @override
  Future<ModelState> delete(String artifactKey) {
    deleted.add(artifactKey);
    return _inner.delete(artifactKey);
  }

  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) =>
      _inner.addModel(entry);
}
