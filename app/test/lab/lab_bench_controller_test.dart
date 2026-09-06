import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/app/launch_composition.dart';
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
final class _GatedModels implements ModelManagementRepository {
  final Completer<void> gate = Completer<void>();
  static const _inner = StaticModels(ModelState());

  @override
  Future<ModelState> load() async {
    await gate.future;
    return _inner.load();
  }

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
  Future<ModelState> delete(String artifactKey) => _inner.delete(artifactKey);
  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) =>
      _inner.addModel(entry);
}

ProviderContainer _container({
  FakeInferenceRepository? inference,
  ModelState model = const ModelState(),
  ModelManagementRepository? models,
  _Probes? probes,
}) {
  final container = ProviderContainer(
    overrides: [
      ...launchOverrides(
        launchDependenciesWith(
          inference: inference,
          model: model,
          models: models,
        ),
        lab: true,
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
    expect(await controller.send('   '), isFalse, reason: 'empty prompt');
    expect(await controller.send('Hello'), isTrue);
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
    expect(
      await controller.send('Again'),
      isFalse,
      reason: 'one run at a time',
    );
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
      expect(await controller.send('Read a CSV without pandas'), isTrue);
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
      expect(run.telemetry.peakFootprintBytes, run.telemetry.footprintBytes);
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
    await controller.send('Hello');
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
      container.read(labBenchControllerProvider).activeRun!.phase,
      LabRunPhase.cancelling,
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
      await controller.send('[fail] please');
      final failed = await _settle(container);
      expect(failed.phase, LabRunPhase.failed);
      expect(failed.failure, InferenceFailureKind.engine);
      expect(failed.answer, isNotEmpty);
      expect(failed.configuration.catalogKey, 'gemma4-mlx');
      expect(await controller.retry(), isTrue);
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
      await controller.send('One');
      await _settle(container);
      await controller.send('Two');
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

  test(
    'a send whose configuration changed before the store answered is refused',
    () async {
      final models = _GatedModels();
      final container = _container(
        inference: FakeInferenceRepository(eventDelay: Duration.zero),
        models: models,
      );
      final controller = container.read(labBenchControllerProvider.notifier);
      controller.arm('gemma4-gguf');
      final sending = controller.send('Hello');
      // The bench is not locked yet, so the Rig still takes a change.
      expect(controller.arm('qwen35-gguf'), isTrue);
      models.gate.complete();
      expect(await sending, isFalse);
      expect(container.read(labBenchControllerProvider).session.runCount, 0);
      // The next send runs what is armed now.
      expect(await controller.send('Hello'), isTrue);
      final run = await _settle(container);
      expect(run.configuration.catalogKey, 'qwen35-gguf');
    },
  );

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
}
