import 'dart:async';
import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:inferno/testing.dart';
import 'package:test/test.dart';

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
    // Defaults are the ABI-2 contract: check_tensors off (upstream
    // default), f16 KV, engine-default threads and GPU layers, SWA
    // window-sized.
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
    });
  });

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
    expect(events.whereType<InfernoMetricsEvent>(), hasLength(1));
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
    // The stream is lazy: obtain it while loaded, listen only after the
    // model is gone.
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
    // The runtime is still usable afterwards.
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

  test('model and native inputs stay immutably pinned', () {
    expect(gemma4E2BMlx4Bit.revision, hasLength(40));
    expect(gemma4E2BMlx4Bit.files, hasLength(7));
    expect(gemma4E2BGgufQ4.files.single.bytes, 2620370976);
    expect(infernoToyGguf.files.single.bytes, lessThan(3000000));
    for (final artifact in [
      gemma4E2BMlx4Bit,
      gemma4E2BGgufQ4,
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
