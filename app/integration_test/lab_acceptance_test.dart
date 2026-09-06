import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/lab/application/lab_bench_controller.dart';
import 'package:golem_flutter/features/lab/application/lab_providers.dart';
import 'package:golem_flutter/features/lab/domain/lab_configuration.dart';
import 'package:golem_flutter/features/lab/domain/lab_run.dart';
import 'package:golem_flutter/features/lab/domain/lab_run_settings.dart';
import 'package:golem_flutter/features/lab/domain/latency_series.dart';
import 'package:golem_flutter/features/lab/lab_shell.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// Golem Model Lab's real-model acceptance (#58), on the lab build against
/// the four configurations the bench ships:
///
/// ```sh
/// flutter test integration_test/lab_acceptance_test.dart -d macos \
///   --flavor lab --dart-define=GOLEM_LAB_ACCEPTANCE=true
/// ```
///
/// Provision the artifacts first (hard links; `app/README.md`, "Golem Model
/// Lab"). Each configuration is verified offline through the lab's own
/// Download, then driven through the composer for two turns; the engines are
/// switched in both directions in one process; Stop on a long prompt keeps
/// the partial output; a context floor forces a failure and Retry runs the
/// prompt again; every run's numbers hold the version-2 timing relations;
/// and the instrumented stream is timed against the silent one on each
/// engine — a repeatable decode slowdown over five percent blocks acceptance.
///
/// Evidence lands on the host console as `GOLEM_LAB` lines beside the
/// broker's `INFERNO_METRICS`. CI never sets the define, so this self-skips.
const _enabled = bool.fromEnvironment('GOLEM_LAB_ACCEPTANCE');

/// Repeats per (engine, observed) cell of the overhead comparison.
const _overheadRepeats = int.fromEnvironment(
  'GOLEM_LAB_OVERHEAD_REPEATS',
  defaultValue: 3,
);

const _shortPrompt = 'Name the largest planet in the solar system.';
const _followUp = 'And the smallest?';
const _longPrompt =
    'Explain in about 400 words why the sky is blue, then why sunsets are '
    'red, then why the sea looks blue on a clear day.';
const _overheadPrompt = 'Explain in about 150 words why the sky is blue.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final metrics = <String>[];
  late void Function(String?, {int? wrapWidth}) host;
  // Set once the bench is up: what a timeout has to say about it.
  String Function() describeBench = () => 'bench not up';

  Future<void> pumpUntil(
    WidgetTester tester,
    String description,
    bool Function() predicate, {
    Duration timeout = const Duration(minutes: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    do {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for $description: ${describeBench()}');
      }
      await tester.pump(const Duration(milliseconds: 100));
    } while (!predicate());
  }

  testWidgets(
    'every lab configuration measures honestly, switches, stops and retries',
    // Set --dart-define=GOLEM_LAB_ACCEPTANCE=true on a --flavor lab build.
    skip: !_enabled,
    (tester) async {
      expect(AppIdentity.current.isLab, isTrue, reason: 'build --flavor lab');
      host = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.startsWith('INFERNO_METRICS')) {
          metrics.add(message);
        }
        host(message, wrapWidth: wrapWidth);
      };
      addTearDown(() => debugPrint = host);
      void say(String line) => host('GOLEM_LAB $line');

      await app.launch();
      await pumpUntil(
        tester,
        'the bench to appear',
        () => find.byType(LabShell).evaluate().isNotEmpty,
      );
      final providers = ProviderScope.containerOf(
        tester.element(find.byType(LabShell)),
      );
      final bench = providers.read(labBenchControllerProvider.notifier);
      final models = providers.read(modelControllerProvider.notifier);
      final configurations = providers.read(labConfigurationListProvider);
      expect(
        configurations.map((c) => c.key),
        containsAll(labConfigurationKeys),
      );
      say(
        'host=${Platform.operatingSystemVersion} '
        'configurations=${configurations.map((c) => c.key).join(',')}',
      );

      LabBenchState state() => providers.read(labBenchControllerProvider);
      describeBench = () {
        final s = state();
        return 'locked=${s.locked} armed=${s.armed?.key} '
            'runs=${[for (final c in s.session.conversations)
              for (final r in c.runs) '${r.id}:${r.phase.name}'].join(',')}';
      };

      // Provisioned bytes verified in place through the lab's own store,
      // offline: the path a user's Download takes, minus the network.
      for (final configuration in configurations) {
        await pumpUntil(
          tester,
          'the model store to read',
          () => providers.read(modelControllerProvider).hasValue,
        );
        final before = providers
            .read(modelControllerProvider)
            .requireValue
            .statusOf(configuration.key);
        if (before.phase != ArtifactPhase.installed) {
          unawaited(models.download(configuration.key));
          await pumpUntil(tester, '${configuration.key} to verify', () {
            final status = providers
                .read(modelControllerProvider)
                .requireValue
                .statusOf(configuration.key);
            if (status.phase == ArtifactPhase.downloading &&
                status.downloadedBytes > configuration.entry.totalBytes) {
              fail('${configuration.key}: the downloader fetched bytes');
            }
            return status.phase == ArtifactPhase.installed;
          }, timeout: const Duration(minutes: 5));
        }
        say('verified ${configuration.key} offline');
      }

      /// One turn through the composer, as a user sends it; returns the run.
      Future<LabRun> turn(String prompt) async {
        final runsBefore = state().session.runCount;
        await tester.tap(find.byKey(const Key('lab-composer')));
        await tester.enterText(find.byKey(const Key('lab-composer')), prompt);
        await tester.pump();
        await tester.tap(find.byKey(const Key('lab-run-button')));
        await pumpUntil(
          tester,
          'the run to start',
          () => state().session.runCount == runsBefore + 1,
          timeout: const Duration(seconds: 30),
        );
        await pumpUntil(tester, 'the run to end', () => !state().locked);
        await tester.pump(const Duration(milliseconds: 200));
        return state().session.active!.last!;
      }

      /// [cold] when this run loaded the model; a warm run on the resident
      /// model has no load phase and reports none.
      void expectHonestTiming(LabRun run, {required bool cold}) {
        final m = run.metrics!;
        expect(m.timingSemanticsVersion, 2, reason: run.id);
        expect(m.tokenCount, greaterThan(0), reason: run.id);
        expect(m.promptTokenCount, greaterThan(0), reason: run.id);
        expect(m.promptTokensPerSecond, greaterThan(0), reason: run.id);
        final ttft = m.timeToFirstTokenSeconds!;
        expect(ttft, greaterThan(0), reason: run.id);
        expect(ttft, lessThanOrEqualTo(m.elapsedSeconds), reason: run.id);
        expect(
          ttft,
          greaterThanOrEqualTo(
            m.promptTokenCount! / m.promptTokensPerSecond - 1e-3,
          ),
          reason: '${run.id}: prefill is inside the first-token window',
        );
        expect(
          m.decodeTokensPerSecond,
          closeTo(m.tokenCount / (m.elapsedSeconds - ttft), 1e-3),
          reason: '${run.id}: decode rate is recomputable',
        );
        // The instants the bench charted count every token the engine did.
        final telemetry = run.telemetry;
        expect(
          telemetry.loadDuration,
          cold ? isNotNull : isNull,
          reason: run.id,
        );
        expect(
          telemetry.observationKind,
          run.configuration.engine == ModelEngine.gguf
              ? ObservationKind.token
              : ObservationKind.chunk,
          reason: run.id,
        );
        if (run.configuration.engine == ModelEngine.gguf) {
          expect(telemetry.observationCount, m.tokenCount, reason: run.id);
          expect(telemetry.promptTotal, m.promptTokenCount, reason: run.id);
          expect(telemetry.promptCompleted, telemetry.promptTotal);
        } else {
          expect(telemetry.observationCount, greaterThan(0), reason: run.id);
        }
        // A cold load ends at 1 on both engines — llama.cpp's own fraction
        // climbs there, MLX reports none and the loaded phase says so; a
        // warm run has no load phase at all.
        expect(telemetry.loadFraction, cold ? 1 : isNull, reason: run.id);
        expect(telemetry.peakFootprintBytes, greaterThan(0), reason: run.id);
        expect(run.configuration.artifact.verified, isTrue, reason: run.id);
        expect(run.configuration.device?.chip, isNotNull, reason: run.id);
      }

      String report(LabRun run) {
        final m = run.metrics!;
        final series = LatencySeries.from(run.telemetry.instantsMs);
        return 'run=${run.id} key=${run.configuration.catalogKey} '
            'engine=${run.configuration.engine.name} phase=${run.phase.name} '
            'load_s=${run.telemetry.loadDuration == null ? 'warm' : (run.telemetry.loadDuration!.inMilliseconds / 1000).toStringAsFixed(2)} '
            'prompt_tok=${m.promptTokenCount} '
            'prompt_tps=${m.promptTokensPerSecond.toStringAsFixed(1)} '
            'ttft_s=${m.timeToFirstTokenSeconds!.toStringAsFixed(3)} '
            'tokens=${m.tokenCount} '
            'decode_tps=${m.decodeTokensPerSecond.toStringAsFixed(1)} '
            'elapsed_s=${m.elapsedSeconds.toStringAsFixed(2)} '
            'observations=${run.telemetry.observationCount}/'
            '${run.telemetry.observationKind?.name} '
            'median_gap_ms=${series.medianMs?.toStringAsFixed(1)} '
            'stalls=${series.stallCount} '
            'peak_gib=${((m.peakPhysicalFootprintBytes ?? 0) / (1 << 30)).toStringAsFixed(2)} '
            'batch=${m.promptBatchSize}';
      }

      // Two turns on every configuration, in an order that switches the
      // engine both ways (gguf → mlx → gguf → mlx) inside one process.
      final order = ['gemma4-gguf', 'gemma4-mlx', 'qwen35-gguf', 'qwen35-mlx'];
      for (final key in order) {
        expect(bench.arm(key), isTrue, reason: key);
        await tester.pump();
        final first = await turn(_shortPrompt);
        expect(first.phase, LabRunPhase.completed, reason: key);
        expect(first.answer.toLowerCase(), contains('jupiter'), reason: key);
        expectHonestTiming(first, cold: true);
        say(report(first));
        final second = await turn(_followUp);
        expect(second.phase, LabRunPhase.completed, reason: key);
        expectHonestTiming(second, cold: false);
        say(report(second));
        // The second turn carried the first: the context grew.
        expect(
          second.metrics!.promptTokenCount!,
          greaterThan(first.metrics!.promptTokenCount!),
          reason: '$key: a follow-up prefills the conversation',
        );
        expect(
          providers.read(residentModelKeyProvider),
          key,
          reason: 'the bench armed what is resident',
        );
      }

      // Stop on a long prompt: partial output kept, run terminated once,
      // and Retry sends the same prompt again as a new run beside it.
      expect(bench.arm('gemma4-gguf'), isTrue);
      await tester.pump();
      final runsBefore = state().session.runCount;
      await tester.enterText(
        find.byKey(const Key('lab-composer')),
        _longPrompt,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('lab-run-button')));
      await pumpUntil(
        tester,
        'the long run to produce output',
        () =>
            state().session.runCount == runsBefore + 1 &&
            (state().activeRun?.answer.length ?? 0) > 40,
        timeout: const Duration(minutes: 3),
      );
      await tester.tap(find.byKey(const Key('lab-stop-button')));
      await pumpUntil(
        tester,
        'the cancelled run to end',
        () => !state().locked,
      );
      await tester.pump(const Duration(milliseconds: 200));
      final cancelled = state().session.active!.last!;
      expect(cancelled.phase, LabRunPhase.cancelled);
      expect(cancelled.answer, isNotEmpty, reason: 'partial output kept');
      expect(cancelled.metrics, isNotNull, reason: 'metrics still arrive');
      say(
        'cancelled run=${cancelled.id} tokens=${cancelled.metrics!.tokenCount} '
        'answer_chars=${cancelled.answer.length}',
      );
      expect(await bench.retry(), isTrue);
      await pumpUntil(tester, 'the retried run to end', () => !state().locked);
      await tester.pump(const Duration(milliseconds: 200));
      final retried = state().session.active!.last!;
      expect(retried.id, isNot(cancelled.id));
      expect(retried.prompt, cancelled.prompt);
      expect(retried.phase, LabRunPhase.completed);
      expectHonestTiming(retried, cold: false);
      say('retried ${report(retried)}');

      // A forced failure: reasoning on under a one-token budget spends the
      // whole budget on the thinking opener, so the broker refuses the run
      // as exhausted before an answer — the same failure chat shows. The
      // run keeps its own snapshot, and Retry under the same contract fails
      // the same way, as a second run beside the first.
      expect(
        bench.updateSettings(
          const LabRunSettings(maxTokens: 1, reasoningEnabled: true),
        ),
        isEmpty,
      );
      await tester.pump();
      final failed = await turn(_shortPrompt);
      say(
        'forced-failure run=${failed.id} phase=${failed.phase.name} '
        'failure=${failed.failure?.name} max_tokens='
        '${failed.configuration.sampling.maxTokens}',
      );
      expect(failed.phase, LabRunPhase.failed);
      expect(failed.failure, InferenceFailureKind.budgetExhaustedBeforeAnswer);
      expect(failed.configuration.sampling.maxTokens, 1);
      expect(find.byKey(const Key('lab-failed-notice')), findsOneWidget);
      expect(await bench.retry(), isTrue);
      await pumpUntil(
        tester,
        'the retried failure to end',
        () => !state().locked,
      );
      await tester.pump(const Duration(milliseconds: 200));
      final conversation = state().session.active!;
      expect(conversation.runs.map((r) => r.phase), [
        LabRunPhase.failed,
        LabRunPhase.failed,
      ]);
      expect(
        conversation.context,
        isEmpty,
        reason: 'failed turns feed nothing',
      );
      expect(bench.updateSettings(const LabRunSettings()), isEmpty);
      await tester.pump();

      // Instrumentation overhead: the same prompt, observed and silent,
      // per engine, straight through the repository so both cells run the
      // identical request. Seeded, so the two cells decode the same tokens.
      final repository = providers.read(inferenceRepositoryProvider);
      for (final key in ['gemma4-gguf', 'gemma4-mlx']) {
        final observed = <double>[];
        final silent = <double>[];
        Future<void> cell(bool observe) async {
          InferenceMetrics? result;
          await for (final event in repository.generate(
            context: [PromptMessage.text('user', _overheadPrompt)],
            reasoningEnabled: false,
            overrides: const SamplingOverrides(),
            modelKey: key,
            observe: observe ? GenerationObservation.everything : null,
            seed: 7,
          )) {
            if (event is MetricsEvent) result = event.metrics;
          }
          (observe ? observed : silent).add(result!.decodeTokensPerSecond);
        }

        // A warm-up so the load is not in either cell, then alternate.
        await cell(false);
        for (var i = 0; i < _overheadRepeats; i++) {
          await cell(true);
          await cell(false);
        }
        double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
        final slowdown = 1 - mean(observed) / mean(silent);
        say(
          'overhead key=$key repeats=$_overheadRepeats '
          'silent_tps=${silent.map((x) => x.toStringAsFixed(1)).join('/')} '
          'observed_tps=${observed.map((x) => x.toStringAsFixed(1)).join('/')} '
          'decode_slowdown=${(slowdown * 100).toStringAsFixed(1)}%',
        );
        expect(
          slowdown,
          lessThan(0.05),
          reason: '$key: observing must not slow decode by 5% or more',
        );
      }

      say(
        'done runs=${state().session.runCount} '
        'conversations=${state().session.conversations.length} '
        'metrics_lines=${metrics.length}',
      );
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
