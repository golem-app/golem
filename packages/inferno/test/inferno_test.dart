import 'dart:async';
import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:inferno/testing.dart';
import 'package:test/test.dart';

import 'timing_invariants.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('inferno-test-');
  });

  tearDown(() => temporary.delete(recursive: true));

  test('load options round-trip to the backend with engine defaults', () async {
    final model = File('${temporary.path}/toy.gguf');
    await model.writeAsBytes([0x47, 0x47, 0x55, 0x46]);
    final backend = MockInfernoBackend();
    final inferno = Inferno.withBackend(backend);

    await inferno.load(engine: InfernoEngineKind.mock, modelPath: model.path);
    // These defaults are the ABI-2 contract, check_tensors matching upstream.
    expect(backend.lastLoadOptions?.checkTensors, isFalse);
    expect(backend.lastLoadOptions?.kvCacheType, InfernoKvCacheType.f16);
    expect(backend.lastLoadOptions?.threadCount, isNull);
    expect(backend.lastLoadOptions?.gpuLayers, isNull);
    expect(backend.lastLoadOptions?.swaFull, isFalse);
    await inferno.unload();

    await inferno.load(
      engine: InfernoEngineKind.mock,
      modelPath: model.path,
      options: const InfernoLoadOptions(
        checkTensors: true,
        kvCacheType: InfernoKvCacheType.q8_0,
        threadCount: 6,
        gpuLayers: 0,
        swaFull: true,
      ),
    );
    expect(backend.lastLoadOptions?.checkTensors, isTrue);
    expect(backend.lastLoadOptions?.kvCacheType, InfernoKvCacheType.q8_0);
    expect(backend.lastLoadOptions?.threadCount, 6);
    expect(backend.lastLoadOptions?.gpuLayers, 0);
    expect(backend.lastLoadOptions?.swaFull, isTrue);
    // The JSON shape is the ABI contract both shims parse.
    expect(backend.lastLoadOptions?.toJson(), {
      'checkTensors': true,
      'kvCacheType': 'q8_0',
      'threadCount': 6,
      'gpuLayers': 0,
      'swaFull': true,
      'projectorPath': null,
    });
  });

  test(
    'observation is opt-in, and absent from the load payload when off',
    () async {
      final model = File('${temporary.path}/toy.gguf');
      await model.writeAsBytes([0x47, 0x47, 0x55, 0x46]);
      final backend = MockInfernoBackend(deltas: const ['a', 'b', 'c']);
      final inferno = Inferno.withBackend(backend);

      // Off: no progress, no observation events, and the ABI-5 payload byte
      // for byte — a caller that never asks cannot tell ABI 6 from ABI 5.
      final fractions = <double>[];
      await inferno.load(
        engine: InfernoEngineKind.mock,
        modelPath: model.path,
        onProgress: fractions.add,
      );
      expect(fractions, isEmpty);
      expect(
        backend.lastLoadOptions?.toJson().containsKey('reportProgress'),
        isFalse,
      );
      final quiet = await inferno
          .generate(const InfernoGenerationRequest(prompt: 'rendered'))
          .toList();
      expect(quiet.whereType<InfernoProgressEvent>(), isEmpty);
      expect(quiet.whereType<InfernoTokenTimingEvent>(), isEmpty);
      await inferno.unload();

      // On: the load's fraction reaches its sink, the prompt progresses to its
      // total, and every token carries an instant.
      await inferno.load(
        engine: InfernoEngineKind.mock,
        modelPath: model.path,
        options: const InfernoLoadOptions(reportProgress: true),
        onProgress: fractions.add,
      );
      expect(fractions, [0.5, 1.0]);
      expect(backend.lastLoadOptions?.toJson()['reportProgress'], isTrue);
      final observed = await inferno
          .generate(
            const InfernoGenerationRequest(
              prompt: 'rendered',
              observe: InfernoObservation(
                promptProgress: true,
                tokenTiming: true,
              ),
            ),
          )
          .toList();
      final progress = observed.whereType<InfernoProgressEvent>().toList();
      expect(progress.map((e) => e.phase).toSet(), {
        InfernoProgressPhase.prompt,
      });
      expect(progress.last.completed, progress.last.total);
      expect(progress.last.total, 'rendered'.length);
      final metrics = observed.whereType<InfernoMetricsEvent>().single.metrics;
      expectContiguousObservations(
        observed.whereType<InfernoTokenTimingEvent>(),
        kind: InfernoObservationKind.token,
        count: metrics.generatedTokenCount,
        elapsedSeconds: metrics.elapsedSeconds,
      );
      expect(observed.last, isA<InfernoGenerationCompleted>());
      await inferno.unload();
    },
  );

  test('probe, load, stream metrics, and unload form one lifecycle', () async {
    final model = File('${temporary.path}/toy.gguf');
    await model.writeAsBytes([0x47, 0x47, 0x55, 0x46]);
    final backend = MockInfernoBackend(deltas: const ['hello', ' world']);
    final inferno = Inferno.withBackend(backend);

    expect((await inferno.probe()).supports(InfernoEngineKind.mock), isTrue);
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: model.path,
    );
    final events = await inferno
        .generate(
          const InfernoGenerationRequest(
            prompt: '<bos><|turn>user\nHello<turn|>\n<|turn>model\n',
            sampling: InfernoSamplingParameters(
              maxTokens: 16,
              temperature: 0.2,
              topP: 0.9,
              topK: 40,
              contextLength: 4096,
              seed: 7,
              stopSequences: ['<turn|>'],
              stopTokenIds: [1, 106],
            ),
          ),
        )
        .toList();

    expect(events.whereType<InfernoTextDelta>().map((event) => event.text), [
      'hello',
      ' world',
    ]);
    final metrics = events.whereType<InfernoMetricsEvent>().single.metrics;
    expect(
      metrics.timingSemanticsVersion,
      InfernoMetrics.currentTimingSemanticsVersion,
    );
    expect(metrics.timeToFirstTokenSeconds, isNotNull);
    expect(
      metrics.timeToFirstTokenSeconds,
      lessThanOrEqualTo(metrics.elapsedSeconds),
    );
    expect(events.last, isA<InfernoGenerationCompleted>());
    expect(backend.lastRequest!.sampling.stopTokenIds, [1, 106]);
    expect(backend.lastRequest!.sampling.topK, 40);
    expect(backend.lastRequest!.sampling.contextLength, 4096);
    await inferno.unload();
  });

  test('explicit cancellation crosses the backend boundary', () async {
    final model = File('${temporary.path}/toy.gguf');
    await model.writeAsBytes([0x47, 0x47, 0x55, 0x46]);
    final inferno = Inferno.withBackend(
      MockInfernoBackend(
        deltas: const ['one', 'two', 'three'],
        delay: const Duration(milliseconds: 5),
      ),
    );
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: model.path,
    );

    final events = <InfernoGenerationEvent>[];
    final done = Completer<void>();
    inferno.generate(const InfernoGenerationRequest(prompt: 'rendered')).listen(
      (event) {
        events.add(event);
        if (event is InfernoTextDelta) unawaited(inferno.cancel());
      },
      onDone: done.complete,
    );
    await done.future;

    expect(
      (events.last as InfernoGenerationCompleted).reason,
      InfernoStopReason.cancelled,
    );
  });

  test(
    'stream cancellation cancels native work and permits another run',
    () async {
      final model = File('${temporary.path}/toy.gguf');
      await model.writeAsBytes([0x47, 0x47, 0x55, 0x46]);
      final inferno = Inferno.withBackend(
        MockInfernoBackend(
          deltas: const ['one', 'two'],
          delay: const Duration(milliseconds: 5),
        ),
      );
      await inferno.load(
        engine: InfernoEngineKind.llamaCpp,
        modelPath: model.path,
      );
      late StreamSubscription<InfernoGenerationEvent> subscription;
      subscription = inferno
          .generate(const InfernoGenerationRequest(prompt: 'first'))
          .listen((_) => unawaited(subscription.cancel()));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final second = await inferno
          .generate(const InfernoGenerationRequest(prompt: 'second'))
          .toList();
      expect(second.last, isA<InfernoGenerationCompleted>());
    },
  );

  test('missing and wrongly-shaped paths are catchable Dart errors', () async {
    final inferno = Inferno.withBackend(MockInfernoBackend());
    await expectLater(
      inferno.load(
        engine: InfernoEngineKind.llamaCpp,
        modelPath: '${temporary.path}/missing.gguf',
      ),
      throwsA(
        isA<InfernoException>().having(
          (error) => error.code,
          'code',
          InfernoErrorCode.invalidModelPath,
        ),
      ),
    );
    await expectLater(
      inferno.load(
        engine: InfernoEngineKind.mlx,
        modelPath: '${temporary.path}/missing-directory',
      ),
      throwsA(isA<InfernoException>()),
    );
  });

  test('overlapping load and generation operations are rejected', () async {
    final model = File('${temporary.path}/toy.gguf');
    await model.writeAsBytes([0x47, 0x47, 0x55, 0x46]);
    final inferno = Inferno.withBackend(
      MockInfernoBackend(delay: const Duration(milliseconds: 5)),
    );
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: model.path,
    );
    final subscription = inferno
        .generate(const InfernoGenerationRequest(prompt: 'first'))
        .listen((_) {});
    expect(
      () => inferno.generate(const InfernoGenerationRequest(prompt: 'overlap')),
      throwsA(isA<InfernoException>()),
    );
    await subscription.cancel();
  });

  test('listening after an unload errors instead of wedging', () async {
    final model = File('${temporary.path}/toy.gguf');
    await model.writeAsBytes([0x47, 0x47, 0x55, 0x46]);
    final inferno = Inferno.withBackend(MockInfernoBackend());
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: model.path,
    );
    // The stream is lazy: obtained while loaded, listened to after unload.
    final stream = inferno.generate(
      const InfernoGenerationRequest(prompt: 'late listener'),
    );
    await inferno.unload();
    await expectLater(
      stream,
      emitsError(
        isA<InfernoException>().having(
          (error) => error.code,
          'code',
          InfernoErrorCode.invalidState,
        ),
      ),
    );
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: model.path,
    );
    final events = await inferno
        .generate(const InfernoGenerationRequest(prompt: 'recovered'))
        .toList();
    expect(events.last, isA<InfernoGenerationCompleted>());
    await inferno.unload();
  });

  group('metrics payload parsing', () {
    const payload = <String, Object?>{
      'decodeTokensPerSecond': 31.5,
      'promptTokensPerSecond': 812.0,
      'generatedTokenCount': 12,
      'elapsedSeconds': 0.61,
      'promptTokenCount': 20,
      'timeToFirstTokenSeconds': 0.24,
      'peakPhysicalFootprintBytes': 483183820,
      'timingSemanticsVersion': 2,
    };

    Matcher refuses(String key) => throwsA(
      isA<InfernoException>()
          .having((error) => error.code, 'code', InfernoErrorCode.internal)
          .having((error) => error.message, 'message', contains(key)),
    );

    test('a version-2 payload parses, optional fields survive absence', () {
      final metrics = InfernoMetrics.fromPayload(payload);
      expect(metrics.decodeTokensPerSecond, 31.5);
      expect(metrics.promptTokensPerSecond, 812.0);
      expect(metrics.generatedTokenCount, 12);
      expect(metrics.elapsedSeconds, 0.61);
      expect(metrics.promptTokenCount, 20);
      expect(metrics.timeToFirstTokenSeconds, 0.24);
      expect(metrics.peakPhysicalFootprintBytes, 483183820);
      expect(metrics.timingSemanticsVersion, 2);

      // The empty-output shape: nothing generated, so no first token.
      final empty = InfernoMetrics.fromPayload(
        {
          ...payload,
          'decodeTokensPerSecond': 0,
          'generatedTokenCount': 0,
          'timeToFirstTokenSeconds': null,
          'peakPhysicalFootprintBytes': null,
        }..remove('promptTokenCount'),
      );
      expect(empty.generatedTokenCount, 0);
      expect(empty.decodeTokensPerSecond, 0);
      expect(empty.promptTokenCount, isNull);
      expect(empty.timeToFirstTokenSeconds, isNull);
      expect(empty.peakPhysicalFootprintBytes, isNull);

      // A version this package has never heard of is a label, not a gate:
      // the ABI check already decided the shim may speak.
      expect(
        InfernoMetrics.fromPayload({
          ...payload,
          'timingSemanticsVersion': 3,
        }).timingSemanticsVersion,
        3,
      );
    });

    test('an unlabelled or malformed payload is refused, typed', () {
      final unversioned = Map.of(payload)..remove('timingSemanticsVersion');
      expect(
        () => InfernoMetrics.fromPayload(unversioned),
        refuses('timingSemanticsVersion'),
      );
      for (final bad in const <Object?>['2', 0, 2.0]) {
        expect(
          () => InfernoMetrics.fromPayload({
            ...payload,
            'timingSemanticsVersion': bad,
          }),
          refuses('timingSemanticsVersion'),
          reason: '$bad',
        );
      }
      final noElapsed = Map.of(payload)..remove('elapsedSeconds');
      expect(
        () => InfernoMetrics.fromPayload(noElapsed),
        refuses('elapsedSeconds'),
      );
      expect(
        () => InfernoMetrics.fromPayload({...payload, 'promptTokenCount': 'x'}),
        refuses('promptTokenCount'),
      );
    });
  });

  test('model and native inputs stay immutably pinned', () {
    expect(gemma4E2BMlx4Bit.revision, hasLength(40));
    expect(gemma4E2BMlx4Bit.files, hasLength(8));
    expect(
      gemma4E2BGgufQ4.files
          .singleWhere((file) => file.role == InfernoFileRole.weights)
          .bytes,
      2620370976,
    );
    expect(qwen35TwoBMlx4Bit.files, hasLength(10));
    expect(
      qwen35TwoBGgufQ4.files
          .singleWhere((file) => file.role == InfernoFileRole.weights)
          .bytes,
      1214873856,
    );
    expect(
      qwen35TwoBGgufQ4.files
          .singleWhere((file) => file.role == InfernoFileRole.projector)
          .bytes,
      364664384,
    );
    expect(infernoToyGguf.files.single.bytes, lessThan(3000000));
    for (final artifact in [
      gemma4E2BMlx4Bit,
      gemma4E2BGgufQ4,
      qwen35TwoBMlx4Bit,
      qwen35TwoBGgufQ4,
      qwen35TwoBMmprojCandidates,
      qwen35Mlx4Bit,
      qwen35GgufQ4,
      qwen35MmprojCandidates,
      infernoToyGguf,
    ]) {
      for (final file in artifact.files) {
        expect(file.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    }
    expect(llamaCppRevision, hasLength(40));
    expect(mlxSwiftLmRevision, hasLength(40));
    expect(mlxSwiftRevision, hasLength(40));
  });
}
