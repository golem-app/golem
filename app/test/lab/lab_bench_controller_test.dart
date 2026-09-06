import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/lab_app.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/services/device_storage.dart';
import 'package:golem_flutter/features/lab/application/lab_bench_controller.dart';
import 'package:golem_flutter/features/lab/application/lab_providers.dart';
import 'package:golem_flutter/features/lab/domain/lab_run.dart';
import 'package:golem_flutter/features/lab/domain/lab_run_settings.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';

import '../support/harness.dart';

final class _Probes implements ProcessFootprintProbe, DeviceProvenanceProbe {
  int samples = 0;

  @override
  Future<int?> physicalFootprintBytes() async => 1000 + 100 * ++samples;

  @override
  Future<DeviceProvenance?> deviceProvenance() async =>
      const DeviceProvenance(model: 'MacBookPro18,3', chip: 'Apple M1 Pro');
}

/// A model store that answers when told, so a test can act between a send
/// and the store's reply.
/// A repository whose stream ignores Stop, or ends without its completion
/// event — the engines a bench must survive.
final class _StubbornRepository implements InferenceRepository {
  _StubbornRepository({required this.ignoresCancel, required this.truncates});

  final bool ignoresCancel;
  final bool truncates;
  final _inner = FakeInferenceRepository(
    eventDelay: const Duration(milliseconds: 10),
  );
  int cancels = 0;

  @override
  Stream<InferenceEvent> generate({
    required List<PromptMessage> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
    GenerationObservation? observe,
    int? seed,
  }) async* {
    await for (final event in _inner.generate(
      context: context,
      reasoningEnabled: reasoningEnabled,
      overrides: overrides,
      modelKey: modelKey,
      systemPrompt: systemPrompt,
      observe: observe,
      seed: seed,
    )) {
      // A torn-down engine: its numbers and its completion never arrive.
      if (truncates && (event is MetricsEvent || event is CompletedEvent)) {
        continue;
      }
      yield event;
    }
    if (ignoresCancel) {
      // Never ends: the engine wedged after Stop.
      await Completer<void>().future;
    }
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (!ignoresCancel) await _inner.cancel();
  }

  @override
  Future<void> prepare({String? modelKey}) =>
      _inner.prepare(modelKey: modelKey);
  @override
  Future<void> unload() => _inner.unload();
  @override
  void releaseEngine() => _inner.releaseEngine();
  @override
  ValueListenable<InferenceResidency> get residency => _inner.residency;
}

ProviderContainer _container({
  InferenceRepository? inference,
  ModelState model = const ModelState(),
  ModelManagementRepository? models,
  _Probes? probes,
}) {
  final container = ProviderContainer(
    overrides: [
      ...labLaunchOverrides(
        launchDependenciesWith(
          inference: inference,
          model: model,
          models: models,
        ),
      ),
      labProbesProvider.overrideWithValue(
        LabProbes(
          footprint: probes ?? _Probes(),
          provenance: probes ?? _Probes(),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<LabRun> _settle(ProviderContainer container) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final run = container.read(labBenchControllerProvider).activeRun;
    if (run != null && run.isTerminal) return run;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('the run never settled');
}

void main() {
  test('arming, settings and conversations are refused while locked', () async {
    final container = _container(
      inference: FakeInferenceRepository(
        eventDelay: const Duration(milliseconds: 30),
      ),
    );
    final controller = container.read(labBenchControllerProvider.notifier);
    expect(controller.arm('nope'), isFalse);
    expect(controller.arm('gemma4-gguf'), isTrue);
    expect(controller.send('   '), isFalse, reason: 'empty prompt');
    expect(controller.send('Hello'), isTrue);
    expect(container.read(labBenchControllerProvider).locked, isTrue);
    // The chat bridge answers for the bench: a model command asking whether
    // a generation is in flight is told yes.
    expect(
      container.read(chatSessionBridgeProvider).generationActive(),
      isTrue,
    );
    expect(controller.arm('qwen35-gguf'), isFalse);
    expect(
      controller.updateSettings(const LabRunSettings(maxTokens: 64)),
      isNotEmpty,
    );
    expect(controller.newConversation(), isFalse);
    expect(controller.send('Again'), isFalse, reason: 'one run at a time');
    final run = await _settle(container);
    expect(run.phase, LabRunPhase.completed);
    expect(
      container.read(chatSessionBridgeProvider).generationActive(),
      isFalse,
    );
  });

  test(
    'a run snapshots its configuration and folds every observation',
    () async {
      final probes = _Probes();
      final container = _container(
        inference: FakeInferenceRepository(
          eventDelay: const Duration(milliseconds: 60),
        ),
        model: const ModelState(
          artifacts: {
            'gemma4-gguf': ArtifactStatus(phase: ArtifactPhase.installed),
          },
        ),
        probes: probes,
      );
      // Provenance resolves asynchronously; give it the frame it needs.
      await container.read(labDeviceProvenanceProvider.future);
      final controller = container.read(labBenchControllerProvider.notifier);
      controller.arm('gemma4-gguf');
      controller.updateSettings(
        const LabRunSettings(maxTokens: 256, seed: 7, reasoningEnabled: true),
      );
      final publishes = <LabRunPhase>[];
      container.listen(labBenchControllerProvider, (_, next) {
        final phase = next.activeRun?.phase;
        if (phase != null) publishes.add(phase);
      });
      // The Rig watches the store from the first frame; a unit test warms
      // it the same way, or the snapshot honestly reads unverified.
      await container.read(modelControllerProvider.future);
      expect(controller.send('Read a CSV without pandas'), isTrue);
      final run = await _settle(container);

      expect(run.phase, LabRunPhase.completed);
      expect(run.configuration.catalogKey, 'gemma4-gguf');
      expect(run.configuration.engine, ModelEngine.gguf);
      expect(run.configuration.engineBuild, startsWith('llama.cpp b'));
      expect(run.configuration.sampling.maxTokens, 256);
      expect(run.configuration.sampling.seed, 7);
      expect(
        run.configuration.sampling.temperature,
        1.0,
        reason: 'profile default',
      );
      expect(run.configuration.artifact.verified, isTrue);
      expect(run.configuration.artifact.fileCount, greaterThan(0));
      expect(run.configuration.device?.chip, 'Apple M1 Pro');
      // Every phase was published in order, and the fake's observation
      // reached the telemetry.
      expect(
        publishes.toSet(),
        containsAll([
          LabRunPhase.loading,
          LabRunPhase.promptProcessing,
          LabRunPhase.generating,
          LabRunPhase.completed,
        ]),
      );
      expect(run.telemetry.loadFraction, 1);
      expect(run.telemetry.loadDuration, isNotNull);
      expect(run.telemetry.promptTotal, greaterThan(0));
      expect(run.telemetry.promptCompleted, run.telemetry.promptTotal);
      expect(run.telemetry.observationKind, ObservationKind.token);
      expect(run.telemetry.observationCount, run.metrics!.tokenCount);
      expect(run.telemetry.footprintBytes, greaterThan(1000));
      expect(run.reasoning, isNotEmpty);
      expect(run.answer, isNotEmpty);
      expect(run.metrics!.timeToFirstTokenSeconds, 0.31);
      // Coalesced: far fewer publishes than the events the fake emitted.
      expect(publishes.length, lessThan(30));
    },
  );

  test('Stop keeps the partial output and terminates the run once', () async {
    final inference = FakeInferenceRepository(
      eventDelay: const Duration(milliseconds: 40),
    );
    final container = _container(inference: inference);
    final controller = container.read(labBenchControllerProvider.notifier);
    controller.arm('qwen35-gguf');
    controller.send('Hello');
    // Let the run reach its answer before stopping.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (container
            .read(labBenchControllerProvider)
            .activeRun!
            .answer
            .isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    controller.stop();
    expect(
      container.read(labBenchControllerProvider).activeRun!.cancelling,
      isTrue,
    );
    expect(inference.cancels, 1);
    final run = await _settle(container);
    expect(run.phase, LabRunPhase.cancelled);
    expect(run.answer, isNotEmpty, reason: 'partial output kept');
    expect(run.endedAt, isNotNull);
    // A second Stop on a finished run is nothing.
    controller.stop();
    expect(inference.cancels, 1);
    expect(container.read(labBenchControllerProvider).locked, isFalse);
  });

  test(
    'a failure keeps the snapshot and retry sends the prompt again',
    () async {
      final container = _container(
        inference: FakeInferenceRepository(eventDelay: Duration.zero),
      );
      final controller = container.read(labBenchControllerProvider.notifier);
      controller.arm('gemma4-mlx');
      controller.send('[fail] please');
      final failed = await _settle(container);
      expect(failed.phase, LabRunPhase.failed);
      expect(failed.failure, InferenceFailureKind.engine);
      expect(failed.answer, isNotEmpty);
      expect(failed.configuration.catalogKey, 'gemma4-mlx');
      expect(controller.retry(), isTrue);
      final retried = await _settle(container);
      expect(retried.id, isNot(failed.id));
      expect(retried.prompt, failed.prompt);
      final conversation = container
          .read(labBenchControllerProvider)
          .session
          .active!;
      expect(conversation.runs.map((r) => r.id), [failed.id, retried.id]);
      // A failed turn never feeds the next prompt.
      expect(conversation.context, isEmpty);
    },
  );

  test(
    'a model or settings change starts a new conversation only once it has runs',
    () async {
      final container = _container(
        inference: FakeInferenceRepository(eventDelay: Duration.zero),
      );
      final controller = container.read(labBenchControllerProvider.notifier);
      controller.arm('gemma4-gguf');
      controller.updateSettings(const LabRunSettings(maxTokens: 128));
      expect(
        container.read(labBenchControllerProvider).session.conversations,
        isEmpty,
      );
      controller.send('One');
      await _settle(container);
      controller.send('Two');
      await _settle(container);
      final first = container.read(labBenchControllerProvider).session.active!;
      expect(first.runs, hasLength(2));
      expect(first.context.map((m) => m.text).first, 'One');

      controller.arm('gemma4-mlx');
      var session = container.read(labBenchControllerProvider).session;
      expect(session.conversations, hasLength(2));
      expect(session.active!.runs, isEmpty);
      // Another change under an empty conversation does not stack empties.
      controller.updateSettings(const LabRunSettings(maxTokens: 64));
      session = container.read(labBenchControllerProvider).session;
      expect(session.conversations, hasLength(2));
      // An explicit new conversation is likewise a no-op when empty.
      expect(controller.newConversation(), isTrue);
      expect(
        container.read(labBenchControllerProvider).session.conversations,
        hasLength(2),
      );
      expect(container.read(labBenchControllerProvider).session.runCount, 2);
    },
  );

  test('Retry after Stop runs the prompt again to completion', () async {
    final container = _container(
      inference: FakeInferenceRepository(
        eventDelay: const Duration(milliseconds: 20),
      ),
    );
    final controller = container.read(labBenchControllerProvider.notifier);
    controller.arm('gemma4-gguf');
    controller.send('Hello');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (container
            .read(labBenchControllerProvider)
            .activeRun!
            .answer
            .isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    controller.stop();
    final cancelled = await _settle(container);
    expect(cancelled.phase, LabRunPhase.cancelled);
    expect(controller.retry(), isTrue);
    final retried = await _settle(container);
    expect(retried.id, isNot(cancelled.id));
    expect(retried.phase, LabRunPhase.completed);
    expect(container.read(labBenchControllerProvider).locked, isFalse);
  });

  test('a locked bench refuses settings with its own reason', () async {
    final container = _container(
      inference: FakeInferenceRepository(
        eventDelay: const Duration(milliseconds: 30),
      ),
    );
    final controller = container.read(labBenchControllerProvider.notifier);
    controller.arm('gemma4-gguf');
    controller.send('Hello');
    expect(controller.updateSettings(const LabRunSettings(maxTokens: 64)), [
      LabSettingsProblem.benchLocked,
    ]);
    await _settle(container);
  });

  test('a stream that ends without completing reads as cancelled', () async {
    final container = _container(
      inference: _StubbornRepository(ignoresCancel: false, truncates: true),
    );
    final controller = container.read(labBenchControllerProvider.notifier);
    controller.arm('gemma4-gguf');
    controller.send('Hello');
    final run = await _settle(container);
    // Torn down under it: not a measurement, its partial answer kept and
    // fed to nothing, and Retry on offer.
    expect(run.phase, LabRunPhase.cancelled);
    expect(run.answer, isNotEmpty);
    expect(run.metrics, isNull);
    expect(
      container.read(labBenchControllerProvider).session.active!.context,
      isEmpty,
    );
    expect(controller.retry(), isTrue);
    await _settle(container);
  });

  test('disposing the bench mid-run cancels the engine', () async {
    final repository = _StubbornRepository(
      ignoresCancel: false,
      truncates: false,
    );
    final container = _container(inference: repository);
    final controller = container.read(labBenchControllerProvider.notifier);
    controller.arm('gemma4-gguf');
    controller.send('Hello');
    expect(container.read(labBenchControllerProvider).locked, isTrue);
    container.dispose();
    expect(repository.cancels, 1, reason: 'native decode must not outlive it');
  });

  test(
    'invalid settings are refused with their problems and nothing applies',
    () {
      final container = _container();
      final controller = container.read(labBenchControllerProvider.notifier);
      controller.arm('gemma4-gguf');
      final problems = controller.updateSettings(
        const LabRunSettings(contextLength: 1024, maxTokens: 1024),
      );
      expect(problems, [LabSettingsProblem.maxTokensAboveBudget]);
      expect(
        container.read(labBenchControllerProvider).settings,
        const LabRunSettings(),
      );
    },
  );

  testWidgets('Stop ends a run the engine will not end, after the deadline', (
    tester,
  ) async {
    final repository = _StubbornRepository(
      ignoresCancel: true,
      truncates: true,
    );
    final container = _container(inference: repository);
    final controller = container.read(labBenchControllerProvider.notifier);
    controller.arm('gemma4-gguf');
    controller.send('Hello');
    LabBenchState bench() => container.read(labBenchControllerProvider);
    // Let the answer arrive, then Stop: the engine ignores it.
    for (
      var i = 0;
      i < 100 && (bench().activeRun?.answer.isEmpty ?? true);
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    controller.stop();
    expect(bench().activeRun!.cancelling, isTrue);
    expect(repository.cancels, 1);
    await tester.pump(labStopDeadline - const Duration(seconds: 1));
    expect(bench().locked, isTrue, reason: 'the engine still has a chance');
    await tester.pump(const Duration(seconds: 2));
    expect(bench().activeRun!.phase, LabRunPhase.cancelled);
    expect(bench().locked, isFalse, reason: 'the bench is usable again');
    expect(bench().activeRun!.answer, isNotEmpty);
  });
}
