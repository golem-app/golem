import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/lab/domain/lab_configuration.dart';
import 'package:golem_flutter/features/lab/domain/lab_run.dart';
import 'package:golem_flutter/features/lab/domain/lab_run_reducer.dart';
import 'package:golem_flutter/features/lab/domain/lab_run_settings.dart';
import 'package:golem_flutter/features/lab/domain/latency_series.dart';

LabRun _run({String id = 'run-1', LabRunPhase phase = LabRunPhase.loading}) =>
    LabRun(
      id: id,
      prompt: 'Hello',
      phase: phase,
      configuration: LabRunConfiguration(
        catalogKey: 'gemma4-gguf',
        displayName: 'Gemma 4 E2B',
        engine: ModelEngine.gguf,
        profileKey: 'gemma4',
        quantization: 'Q4_K_XL',
        revision: 'abc',
        sampling: const BrokerSamplingParameters(
          maxTokens: 512,
          temperature: 1,
          topP: 0.95,
          seed: null,
          stopSequences: [],
          stopTokenIds: [],
        ),
        settings: const LabRunSettings(),
        engineBuild: 'llama.cpp b1',
        artifact: const LabArtifactProvenance(
          fileCount: 2,
          totalBytes: 10,
          verified: true,
        ),
        device: null,
        startedAt: DateTime(2026, 9, 5),
      ),
    );

void main() {
  group('configurations', () {
    test('the initial catalog is four keys derived from the pinned list', () {
      final configurations = labConfigurations(modelCatalog);
      expect(configurations.map((c) => c.key), [
        'gemma4-mlx',
        'gemma4-gguf',
        'qwen35-mlx',
        'qwen35-gguf',
      ]);
      final families = labModelFamiliesOf(configurations);
      expect(families.map((f) => f.displayName), [
        'Gemma 4 E2B',
        'Qwen 3.5 4B',
      ]);
      expect(families.first.on(ModelEngine.mlx)?.key, 'gemma4-mlx');
      expect(families.first.on(ModelEngine.gguf)?.key, 'gemma4-gguf');
      // Count follows the catalog, never a constant: dropping an entry drops
      // its row.
      expect(
        labConfigurations(
          modelCatalog.where((e) => e.key != 'qwen35-mlx').toList(),
        ).length,
        3,
      );
    });
  });

  group('settings', () {
    final defaults = const Gemma4Profile().sampling(reasoningEnabled: false);

    test('defaults are valid and null means the profile default', () {
      const settings = LabRunSettings();
      expect(
        settings.validate(defaults: defaults, contextCeiling: 8192),
        isEmpty,
      );
      expect(settings.toOverrides().isEmpty, isTrue);
    });

    test('the budget must leave the prompt reserve under the context', () {
      final problems = const LabRunSettings(
        contextLength: 1024,
        maxTokens: 600,
      ).validate(defaults: defaults, contextCeiling: 8192);
      expect(problems, [LabSettingsProblem.maxTokensAboveBudget]);
      expect(
        const LabRunSettings(
          contextLength: 1024,
          maxTokens: 512,
        ).validate(defaults: defaults, contextCeiling: 8192),
        isEmpty,
      );
    });

    test('every bound is named', () {
      expect(
        const LabRunSettings(
          contextLength: 16384,
          temperature: 3,
          topP: 0,
          topK: -1,
          seed: -1,
        ).validate(defaults: defaults, contextCeiling: 8192),
        containsAll([
          LabSettingsProblem.contextAboveCeiling,
          LabSettingsProblem.temperatureOutOfRange,
          LabSettingsProblem.topPOutOfRange,
          LabSettingsProblem.topKNegative,
          LabSettingsProblem.seedNegative,
        ]),
      );
      expect(
        const LabRunSettings(
          contextLength: 256,
          maxTokens: 0,
        ).validate(defaults: defaults, contextCeiling: 8192),
        containsAll([
          LabSettingsProblem.contextBelowFloor,
          LabSettingsProblem.maxTokensBelowOne,
        ]),
      );
    });
  });

  group('reducer', () {
    test('phases move forward through the engine\'s events, once', () {
      var run = _run();
      run = reduceLabRun(run, const RunPhaseEvent(InferencePhase.loading));
      expect(run.phase, LabRunPhase.loading);
      run = reduceLabRun(run, const LoadProgressEvent(0.4));
      expect(run.telemetry.loadFraction, 0.4);
      run = reduceLabRun(
        run,
        const RunPhaseEvent(
          InferencePhase.loaded,
          loadDuration: Duration(seconds: 2),
        ),
      );
      expect(run.telemetry.loadFraction, 1);
      expect(run.telemetry.loadDuration, const Duration(seconds: 2));
      run = reduceLabRun(
        run,
        const RunPhaseEvent(InferencePhase.promptProcessing),
      );
      expect(run.phase, LabRunPhase.promptProcessing);
      run = reduceLabRun(
        run,
        const PromptProgressEvent(completed: 3, total: 9),
      );
      expect(run.telemetry.promptCompleted, 3);
      expect(run.telemetry.promptTotal, 9);
      run = reduceLabRun(run, const AnswerDelta('Hi'));
      expect(run.phase, LabRunPhase.generating);
      // A phase event cannot move a run backwards.
      run = reduceLabRun(
        run,
        const RunPhaseEvent(InferencePhase.promptProcessing),
      );
      expect(run.phase, LabRunPhase.generating);
      run = reduceLabRun(
        run,
        const CompletedEvent(stopReason: InferenceStopReason.endOfSequence),
        now: DateTime(2026, 9, 5, 12),
      );
      expect(run.phase, LabRunPhase.completed);
      expect(run.endedAt, DateTime(2026, 9, 5, 12));
      // Terminal is terminal: a late event changes nothing.
      final late = reduceLabRun(run, const AnswerDelta('!'));
      expect(late.answer, 'Hi');
      expect(late.phase, LabRunPhase.completed);
    });

    test('reasoning, resets, and metrics fold into the run', () {
      var run = _run(phase: LabRunPhase.generating);
      run = reduceLabRun(run, const ReasoningDelta('think '));
      run = reduceLabRun(run, const AnswerDelta('prem'));
      run = reduceLabRun(run, const AnswerResetEvent());
      run = reduceLabRun(run, const AnswerDelta('answer'));
      expect(run.reasoning, 'think ');
      expect(run.answer, 'answer');
      const metrics = InferenceMetrics(
        promptTokensPerSecond: 100,
        decodeTokensPerSecond: 20,
        tokenCount: 7,
        elapsedSeconds: 1,
      );
      run = reduceLabRun(run, const MetricsEvent(metrics));
      expect(run.metrics, metrics);
      expect(run.outputTokens, 7);
    });

    test('instants stay bounded while the count keeps the truth', () {
      const capacity = LabTelemetry.instantCapacity;
      const batches = capacity ~/ 16 + 8;
      var run = _run(phase: LabRunPhase.generating);
      for (var batch = 0; batch < batches; batch++) {
        run = reduceLabRun(
          run,
          TokenTimingEvent(
            kind: ObservationKind.token,
            firstIndex: batch * 16,
            timesMs: [for (var i = 0; i < 16; i++) (batch * 16 + i) * 50.0],
          ),
        );
      }
      const total = batches * 16;
      expect(run.telemetry.observationCount, total);
      expect(run.telemetry.instantsMs, hasLength(capacity));
      expect(run.telemetry.instantsMs.first, (total - capacity) * 50.0);
      expect(run.telemetry.firstInstantMs, 0);
      expect(run.telemetry.observationKind, ObservationKind.token);
      expect(run.telemetry.series.gapsMs, hasLength(capacity - 1));
      // A batch larger than the ring — reachable from the fake and the eval
      // paths — is bounded too, keeping its own newest instants.
      final huge = const LabTelemetry().withInstants(ObservationKind.token, [
        for (var i = 0; i < capacity + 10; i++) i * 1.0,
      ]);
      expect(huge.instantsMs, hasLength(capacity));
      expect(huge.instantsMs.first, 10);
      expect(huge.observationCount, capacity + 10);
    });

    test('Stop makes the run cancelling until the engine ends it', () {
      var run = _run(phase: LabRunPhase.generating);
      run = reduceLabRun(run, const AnswerDelta('partial'));
      run = requestCancel(run);
      expect(run.cancelling, isTrue);
      expect(run.phase, LabRunPhase.generating, reason: 'the phase it reached');
      // Output that lands while cancelling is still kept; the phase holds.
      run = reduceLabRun(run, const AnswerDelta(' more'));
      expect(run.cancelling, isTrue);
      expect(run.answer, 'partial more');
      run = reduceLabRun(run, const CompletedEvent());
      expect(run.phase, LabRunPhase.cancelled);
      expect(run.cancelling, isFalse);
      expect(run.answer, 'partial more', reason: 'partial output survives');
      expect(requestCancel(run).phase, LabRunPhase.cancelled);
    });

    test('an error after Stop is the cancellation, not a failure', () {
      // Both engines abort a cancelled load with an error rather than a
      // completion; the run the user stopped must not read as a red failure.
      var run = requestCancel(_run());
      run = failRun(run, InferenceFailureKind.engine);
      expect(run.phase, LabRunPhase.cancelled);
      expect(run.stopReason, InferenceStopReason.cancelled);
      expect(run.failure, isNull);
    });

    test('the engine\'s acceptance stamps the instants\' zero', () {
      final accepted = DateTime(2026, 9, 6, 12);
      var run = reduceLabRun(
        _run(),
        const RunPhaseEvent(InferencePhase.promptProcessing),
        now: accepted,
      );
      expect(run.acceptedAt, accepted);
      run = reduceLabRun(
        run,
        const RunPhaseEvent(InferencePhase.promptProcessing),
        now: accepted.add(const Duration(seconds: 1)),
      );
      expect(run.acceptedAt, accepted, reason: 'stamped once');
    });

    test('a failure keeps the partial output and the snapshot', () {
      var run = _run(phase: LabRunPhase.generating);
      run = reduceLabRun(run, const AnswerDelta('so far'));
      run = failRun(run, InferenceFailureKind.outOfMemory);
      expect(run.phase, LabRunPhase.failed);
      expect(run.failure, InferenceFailureKind.outOfMemory);
      expect(run.answer, 'so far');
      expect(run.configuration.catalogKey, 'gemma4-gguf');
      expect(
        failRun(run, InferenceFailureKind.engine).failure,
        InferenceFailureKind.outOfMemory,
      );
    });

    test('the process footprint keeps the last reading', () {
      var telemetry = const LabTelemetry();
      telemetry = telemetry.withFootprint(300);
      telemetry = telemetry.withFootprint(200);
      telemetry = telemetry.withFootprint(null);
      expect(telemetry.footprintBytes, 200);
    });
  });

  group('session', () {
    test(
      'a conversation carries finished turns as context, never reasoning',
      () {
        final done = _run(id: 'a', phase: LabRunPhase.generating);
        final finished = reduceLabRun(
          reduceLabRun(
            reduceLabRun(done, const ReasoningDelta('hidden')),
            const AnswerDelta('Paris'),
          ),
          const CompletedEvent(),
        );
        final live = _run(id: 'b', phase: LabRunPhase.generating);
        final conversation = const LabConversation(
          id: 'c',
          runs: [],
        ).withRun(finished).withRun(live);
        expect(conversation.context.map((m) => m.text), ['Hello', 'Paris']);
        // Replacing a run by id keeps the order.
        final replaced = conversation.withRun(
          reduceLabRun(live, const CompletedEvent()),
        );
        expect(replaced.runs.map((r) => r.id), ['a', 'b']);
        expect(replaced.runs.last.phase, LabRunPhase.completed);
      },
    );

    test('a new conversation archives the previous one', () {
      var session = const LabSession().startConversation('one');
      session = session.withActive(session.active!.withRun(_run()));
      session = session.startConversation('two');
      expect(session.conversations.map((c) => c.id), ['one', 'two']);
      expect(session.active!.runs, isEmpty);
      expect(session.runCount, 1);
    });
  });

  group('latency series', () {
    test('gaps, median, and stalls over twice the median', () {
      final series = LatencySeries.from([0, 50, 100, 150, 400, 450, 500]);
      expect(series.gapsMs, [50, 50, 50, 250, 50, 50]);
      expect(series.medianMs, 50);
      expect(series.stallIndexes, {3});
      expect(series.stallCount, 1);
    });

    test('fewer than two instants have nothing to say', () {
      expect(LatencySeries.from(const []).medianMs, isNull);
      expect(LatencySeries.from(const [12]).gapsMs, isEmpty);
    });

    test('an even count medians the middle pair', () {
      expect(LatencySeries.from([0, 10, 30, 60]).medianMs, 20);
    });

    test('a zero median flags no stalls', () {
      // Coarse or batched stamps: half the gaps are 0, so "twice the median"
      // would have been every non-zero gap.
      final series = LatencySeries.from([0, 0, 0, 0, 12]);
      expect(series.medianMs, 0);
      expect(series.stallIndexes, isEmpty);
    });

    test('the live decode rate is measured over the run\'s own window', () {
      // Ten tokens 50 ms apart from 300 ms: twenty per second at the tenth.
      final instants = [for (var i = 0; i < 10; i++) 300.0 + i * 50];
      expect(liveDecodeRate(instants, 750), closeTo(20, 1e-9));
      // The clock moved on and nothing arrived: the idle tail is in the
      // interval, so the rate sinks rather than freezing at the last burst.
      expect(liveDecodeRate(instants, 2200), closeTo(9 / 1.9, 1e-9));
      // Every instant left the window: nothing to report.
      expect(liveDecodeRate(instants, 3000), isNull);
      expect(liveDecodeRate(instants, 300), isNull, reason: 'one instant');
    });
  });

  group('phase order', () {
    test('is explicit, and cancelling admits no phase after it', () {
      expect(
        LabRunPhase.loading.reaches(LabRunPhase.promptProcessing),
        isFalse,
      );
      expect(LabRunPhase.generating.reaches(LabRunPhase.loading), isTrue);
      expect(LabRunPhase.completed.reaches(LabRunPhase.generating), isTrue);
      var run = reduceLabRun(_run(), const AnswerDelta('Hi'));
      run = requestCancel(run);
      // A repository that re-announces a load mid-stream cannot pull a
      // cancelling run back to loading.
      run = reduceLabRun(run, const RunPhaseEvent(InferencePhase.loading));
      expect(run.phase, LabRunPhase.generating);
      // Nor does Stop during a load claim phases the engine never reached.
      final stopped = requestCancel(_run());
      expect(stopped.phase.reaches(LabRunPhase.promptProcessing), isFalse);
    });

    test('a load fraction only ever climbs', () {
      var run = reduceLabRun(_run(), const LoadProgressEvent(0.8));
      run = reduceLabRun(run, const LoadProgressEvent(0.6));
      expect(run.telemetry.loadFraction, 0.8);
      run = reduceLabRun(
        run,
        const RunPhaseEvent(InferencePhase.loaded, loadDuration: Duration.zero),
      );
      run = reduceLabRun(run, const LoadProgressEvent(0.9));
      expect(run.telemetry.loadFraction, 1);
    });

    test('output tokens are never a chunk count', () {
      var run = reduceLabRun(
        _run(),
        const TokenTimingEvent(
          kind: ObservationKind.chunk,
          firstIndex: 0,
          timesMs: [300, 340, 380],
        ),
      );
      expect(run.telemetry.observationCount, 3);
      expect(run.outputTokens, isNull, reason: 'chunks are not tokens');
      run = reduceLabRun(
        _run(),
        const TokenTimingEvent(
          kind: ObservationKind.token,
          firstIndex: 0,
          timesMs: [300, 340, 380],
        ),
      );
      expect(run.outputTokens, 3);
    });
  });

  group('families', () {
    test('two families on one profile keep their own ids', () {
      const keys = {
        'qwen35-2b-gguf',
        'qwen35-2b-mlx',
        'qwen35-gguf',
        'qwen35-mlx',
      };
      final families = labModelFamiliesOf([
        for (final entry in modelCatalog)
          if (keys.contains(entry.key)) LabConfiguration(entry),
      ]);
      expect(
        families.map((f) => f.id),
        unorderedEquals(['qwen35-2b', 'qwen35']),
      );
      expect(families.map((f) => f.configurations.first.profileKey).toSet(), {
        'qwen35',
      });
    });
  });
}
