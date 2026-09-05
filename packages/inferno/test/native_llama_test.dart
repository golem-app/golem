import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:inferno/inferno.dart';
import 'package:test/test.dart';

import 'timing_invariants.dart';

void main() {
  final modelPath = Platform.environment['INFERNO_TOY_GGUF'];
  final skipReason = modelPath == null
      ? 'Set INFERNO_TOY_GGUF using tool/fetch_toy_model.dart.'
      : false;
  final gemmaPath = Platform.environment['INFERNO_GEMMA_GGUF'];

  test('disposing mid-generation ends the stream once and stays quiet', () async {
    // #124: the app tore the isolate down while the engine's worker thread was
    // still calling the token trampoline, which aborts the process with
    // "Callback invoked after it has been deleted". dispose() must join that
    // worker before the callback port closes — mock backends cannot show this,
    // so this suite is where it belongs.
    final inferno = Inferno.native();
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: modelPath!,
    );

    // One flag, not a list: cancelOnError defaults to false, so an
    // error-terminated stream delivers onError *and* onDone. Counting both
    // would read as "a late event arrived after dispose" — the abort
    // signature — when the stream simply ended the other way.
    var terminated = 0;
    final firstDelta = Completer<void>();
    final closed = Completer<void>();
    final subscription = inferno
        .generate(
          const InfernoGenerationRequest(
            // Long enough that dispose lands mid-stream rather than after it.
            prompt: 'Count slowly',
            sampling: InfernoSamplingParameters(
              maxTokens: 512,
              temperature: 0.2,
              topP: 0.9,
              seed: 7,
            ),
          ),
        )
        .listen(
          (event) {
            if (event is InfernoTextDelta && !firstDelta.isCompleted) {
              firstDelta.complete();
            }
          },
          onError: (Object _) {
            terminated++;
            if (!closed.isCompleted) closed.complete();
          },
          onDone: () {
            if (!closed.isCompleted) {
              terminated++;
              closed.complete();
            }
          },
        );
    addTearDown(subscription.cancel);

    await firstDelta.future;
    // Without this the test would pass vacuously whenever the toy model
    // outruns the teardown: the point is to dispose *under* a live worker.
    expect(terminated, 0, reason: 'generation must still be running');
    await inferno.dispose();
    await closed.future;

    expect(terminated, 1, reason: 'the stream ends exactly once');
    // Nothing may arrive after dispose returned: the worker has joined and
    // the callback port is closed. A late event here is the abort in slow
    // motion.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(terminated, 1);
  }, skip: skipReason);

  test('toy GGUF loads, streams, reports metrics, and unloads', () async {
    final inferno = Inferno.native();
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: modelPath!,
    );
    final events = await inferno
        .generate(
          const InfernoGenerationRequest(
            prompt: 'Hello',
            sampling: InfernoSamplingParameters(
              maxTokens: 8,
              temperature: 0.2,
              topP: 0.9,
              seed: 7,
            ),
          ),
        )
        .toList();
    expect(events.whereType<InfernoTextDelta>(), isNotEmpty);
    final metrics = events.whereType<InfernoMetricsEvent>().single.metrics;
    expectHonestTiming(metrics);
    // Measured on Apple platforms, null elsewhere — never a misleading zero.
    if (Platform.isMacOS || Platform.isIOS) {
      expect(metrics.peakPhysicalFootprintBytes, greaterThan(0));
    } else {
      expect(metrics.peakPhysicalFootprintBytes, isNull);
    }
    expect(events.last, isA<InfernoGenerationCompleted>());
    await inferno.unload();
  }, skip: skipReason);

  test('images without a projector fail as a typed error', () async {
    // Proves the ABI 3 image array marshals end to end: Dart copies the
    // buffers, the shim sees a non-zero count, and a text-only load refuses it.
    final inferno = Inferno.native();
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: modelPath!,
    );
    addTearDown(inferno.unload);

    // A one-pixel PNG; it is never decoded, the refusal comes first.
    final png = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    ]);
    await expectLater(
      inferno
          .generate(
            InfernoGenerationRequest(
              prompt: 'Describe <__media__>',
              sampling: const InfernoSamplingParameters(maxTokens: 4),
              images: [InfernoImageInput(png)],
            ),
          )
          .toList(),
      throwsA(
        isA<InfernoException>()
            .having(
              (error) => error.code,
              'code',
              InfernoErrorCode.generationFailed,
            )
            .having(
              (error) => error.message,
              'message',
              contains('image projector'),
            ),
      ),
    );
  }, skip: skipReason);

  test('ABI-2 load options apply against the real engine', () async {
    // Every option at once (#13 for CPU-only layers); the proof is that load
    // and a short generation still complete, since each feeds a different
    // llama.cpp path that would reject invalid values. The q8_0 KV knob is
    // deliberately absent: the toy fixture's 4-wide heads cannot take a
    // 32-block quantized cache, so it is proved against the pinned Gemma.
    final inferno = Inferno.native();
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: modelPath!,
      options: const InfernoLoadOptions(
        checkTensors: true,
        threadCount: 2,
        gpuLayers: 0,
        swaFull: true,
      ),
    );
    final events = await inferno
        .generate(
          const InfernoGenerationRequest(
            prompt: 'Hello',
            sampling: InfernoSamplingParameters(
              maxTokens: 8,
              temperature: 0.2,
              topP: 0.9,
              seed: 7,
            ),
          ),
        )
        .toList();
    expect(events.whereType<InfernoTextDelta>(), isNotEmpty);
    expect(events.last, isA<InfernoGenerationCompleted>());
    await inferno.unload();
  }, skip: skipReason);

  test(
    'the runtime survives load, unload, and reload in one process',
    () async {
      final inferno = Inferno.native();
      const request = InfernoGenerationRequest(
        prompt: 'Hello',
        sampling: InfernoSamplingParameters(maxTokens: 4, seed: 11),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        await inferno.load(
          engine: InfernoEngineKind.llamaCpp,
          modelPath: modelPath!,
        );
        final events = await inferno.generate(request).toList();
        expect(
          events.whereType<InfernoTextDelta>(),
          isNotEmpty,
          reason: 'cycle $cycle',
        );
        expect(
          events.last,
          isA<InfernoGenerationCompleted>(),
          reason: 'cycle $cycle',
        );
        await inferno.unload();
      }
    },
    skip: skipReason,
  );

  test(
    'toy GGUF generation can be cancelled without wedging the runtime',
    () async {
      final inferno = Inferno.native();
      await inferno.load(
        engine: InfernoEngineKind.llamaCpp,
        modelPath: modelPath!,
      );
      final events = <InfernoGenerationEvent>[];
      final done = Completer<void>();
      inferno
          .generate(
            const InfernoGenerationRequest(
              prompt: 'Keep generating random text',
              sampling: InfernoSamplingParameters(maxTokens: 256, seed: 9),
            ),
          )
          .listen((event) {
            events.add(event);
          }, onDone: done.complete);
      await inferno.cancel();
      await done.future;
      expect(
        events.whereType<InfernoGenerationCompleted>().single.reason,
        InfernoStopReason.cancelled,
      );
      // A cancel still reports metrics, and where it landed decides their
      // shape: before the first token there is no first-token time — null,
      // never a zero that reads like a measurement — and no decode rate.
      // Tokenization precedes prefill, so the prompt count is known either
      // way, and the request cost real time either way. An EOS-first reply
      // has the same shape; the toy fixture cannot be made to produce one
      // deterministically, so this branch is its coverage too.
      final metrics = events.whereType<InfernoMetricsEvent>().single.metrics;
      expect(
        metrics.timingSemanticsVersion,
        InfernoMetrics.currentTimingSemanticsVersion,
      );
      expect(metrics.elapsedSeconds, greaterThan(0));
      expect(metrics.promptTokenCount, greaterThan(0));
      if (metrics.generatedTokenCount == 0) {
        expect(metrics.timeToFirstTokenSeconds, isNull);
        expect(metrics.decodeTokensPerSecond, 0);
      } else {
        expect(
          metrics.timeToFirstTokenSeconds,
          lessThanOrEqualTo(metrics.elapsedSeconds),
        );
      }
      await inferno.unload();
    },
    skip: skipReason,
  );

  test('a single-token generation reports no decode rate', () async {
    // One token leaves no inter-token interval; the old window would have
    // inverted one decode step into tens of thousands of tokens per second.
    final inferno = Inferno.native();
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: modelPath!,
    );
    final events = await inferno
        .generate(
          const InfernoGenerationRequest(
            prompt: 'Hello',
            sampling: InfernoSamplingParameters(maxTokens: 1, seed: 7),
          ),
        )
        .toList();
    final metrics = events.whereType<InfernoMetricsEvent>().single.metrics;
    expect(metrics.generatedTokenCount, lessThanOrEqualTo(1));
    expect(metrics.decodeTokensPerSecond, 0);
    if (metrics.generatedTokenCount == 1) {
      expect(metrics.timeToFirstTokenSeconds, isNotNull);
      expect(
        metrics.timeToFirstTokenSeconds,
        lessThanOrEqualTo(metrics.elapsedSeconds),
      );
    }
    await inferno.unload();
  }, skip: skipReason);

  test(
    'the pinned Gemma GGUF satisfies the timing contract',
    () async {
      final inferno = Inferno.native();
      await inferno.load(
        engine: InfernoEngineKind.llamaCpp,
        modelPath: gemmaPath!,
      );
      final events = await inferno
          .generate(
            const InfernoGenerationRequest(
              prompt: '<bos><|turn>user\nSay hello.<turn|>\n<|turn>model\n',
              sampling: InfernoSamplingParameters(
                maxTokens: 16,
                temperature: 0.2,
                topP: 0.9,
                seed: 7,
                stopTokenIds: [1, 106],
              ),
            ),
          )
          .toList();
      expectHonestTiming(
        events.whereType<InfernoMetricsEvent>().single.metrics,
      );
      await inferno.unload();
    },
    skip: gemmaPath == null
        ? 'Set INFERNO_GEMMA_GGUF (see tool/fetch_model.dart) for the GGUF '
              'timing check.'
        : false,
    tags: ['real-model'],
  );

  test('topK 1 collapses sampling to greedy regardless of seed', () async {
    final inferno = Inferno.native();
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: modelPath!,
    );
    Future<String> generateText(int seed) async {
      final events = await inferno
          .generate(
            InfernoGenerationRequest(
              prompt: 'Hello',
              sampling: InfernoSamplingParameters(
                maxTokens: 8,
                temperature: 1,
                topK: 1,
                seed: seed,
              ),
            ),
          )
          .toList();
      return events.whereType<InfernoTextDelta>().map((e) => e.text).join();
    }

    // With a single surviving candidate the seed cannot matter.
    expect(await generateText(3), await generateText(1009));
    await inferno.unload();
  }, skip: skipReason);

  test('a presence penalty reaches the sampler chain', () async {
    final inferno = Inferno.native();
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: modelPath!,
    );
    Future<String> generateText(double? penalty) async {
      final events = await inferno
          .generate(
            InfernoGenerationRequest(
              prompt: 'Hello',
              sampling: InfernoSamplingParameters(
                maxTokens: 24,
                temperature: 1,
                presencePenalty: penalty,
                seed: 7,
              ),
            ),
          )
          .toList();
      return events.whereType<InfernoTextDelta>().map((e) => e.text).join();
    }

    // Same seed, so a diverging stream proves the penalty entered the
    // chain. The -1 "whole context" window regressed to a silent no-op —
    // the core sampler clamps negatives and returns an empty sampler — and
    // a no-op makes these byte-identical.
    expect(await generateText(5), isNot(await generateText(null)));
    await inferno.unload();
  }, skip: skipReason);

  test('a context budget below prompt plus max tokens fails clearly', () async {
    final inferno = Inferno.native();
    await inferno.load(
      engine: InfernoEngineKind.llamaCpp,
      modelPath: modelPath!,
    );
    await expectLater(
      inferno
          .generate(
            const InfernoGenerationRequest(
              prompt: 'Hello',
              sampling: InfernoSamplingParameters(
                maxTokens: 16,
                contextLength: 8,
                seed: 7,
              ),
            ),
          )
          .toList(),
      throwsA(
        isA<InfernoException>()
            .having(
              (error) => error.code,
              'code',
              InfernoErrorCode.contextExhausted,
            )
            .having(
              (error) => error.message,
              'message',
              contains('context budget'),
            ),
      ),
    );
    // The runtime must stay usable after the rejected request.
    final events = await inferno
        .generate(
          const InfernoGenerationRequest(
            prompt: 'Hello',
            sampling: InfernoSamplingParameters(maxTokens: 4, seed: 7),
          ),
        )
        .toList();
    expect(events.last, isA<InfernoGenerationCompleted>());
    await inferno.unload();
  }, skip: skipReason);

  test('damaged GGUF variants fail as catchable Dart errors', () async {
    final fixtureDirectory = File(modelPath!).parent.path;
    for (final fixture in {
      'corrupt.gguf': InfernoErrorCode.corruptModel,
      'truncated.gguf': InfernoErrorCode.corruptModel,
      'incompatible.gguf': InfernoErrorCode.incompatibleModel,
    }.entries) {
      final inferno = Inferno.native();
      await expectLater(
        inferno.load(
          engine: InfernoEngineKind.llamaCpp,
          modelPath: '$fixtureDirectory/${fixture.key}',
        ),
        throwsA(
          isA<InfernoException>().having(
            (error) => error.code,
            fixture.key,
            fixture.value,
          ),
        ),
      );
    }
  }, skip: skipReason);
}
