import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/domain/generation_settings.dart';
import '../core/domain/models.dart';
import '../core/repositories/contracts.dart';
import 'context_window.dart';
import 'hash.dart';
import 'model_profile.dart';
import 'model_runtime_config.dart';
import 'effective_sampling.dart';
import 'runtime.dart';

typedef InferenceDiagnosticSink = void Function(String message);

/// The single owner of engine residency (#42): exactly one model is loaded at
/// a time, keyed by catalog entry, and every load or unload goes through here.
final class InfernoInferenceRepository implements InferenceRepository {
  InfernoInferenceRepository(
    this._runtime, {
    required BrokerEngine engine,
    required String modelPath,
    required ModelProfile profile,
    String? initialCatalogKey,
    String? initialProjectorPath,
    bool initialSupportsImages = false,
    this.documentsDirectory = '',
    this.resolveConfig = resolveModelRuntimeConfig,
    this.availableMemoryBytes,
    this.modelSizeBytes = _modelSizeOnDisk,
    this.loadOptions = const BrokerLoadOptions(),
    this.seed,
    this.readAttachment,
    this.diagnosticSink,
  }) : _initial = _Target(
         catalogKey: initialCatalogKey,
         engine: engine,
         modelPath: modelPath,
         profile: profile,
         projectorPath: initialProjectorPath,
         supportsImages: initialSupportsImages,
       );

  final BrokerRuntime _runtime;
  final int? seed;
  final InferenceDiagnosticSink? diagnosticSink;

  /// Null in builds with no attachment store — which is every build that
  /// declares no image capability, so an image cannot reach an engine.
  final Future<List<int>?> Function(String attachmentId)? readAttachment;

  /// A message can outlive its bytes — the OS may trim the container — so a
  /// missing attachment is a typed failure, not a prompt short one picture.
  Future<List<BrokerImageInput>> _loadImages(List<ImagePart> images) async {
    if (images.isEmpty) return const [];
    final reader = readAttachment;
    if (reader == null) {
      throw const InferenceException(
        InferenceFailureKind.unsupportedImages,
        'This build cannot read image attachments.',
      );
    }
    final loaded = <BrokerImageInput>[];
    for (final image in images) {
      final bytes = await reader(image.attachmentId);
      if (bytes == null) {
        throw const InferenceException(
          InferenceFailureKind.attachmentUnavailable,
          'An image in this conversation is no longer available. Remove it '
          'and send again.',
        );
      }
      loaded.add(BrokerImageInput(Uint8List.fromList(bytes)));
    }
    return loaded;
  }

  final String documentsDirectory;
  final ModelRuntimeConfig Function(String catalogKey) resolveConfig;

  /// Free-memory probe for the load preflight; no probe or a null reading
  /// skips it — the engine's own failure stays the loud path.
  final Future<int?> Function()? availableMemoryBytes;

  final Future<int?> Function(String path) modelSizeBytes;

  final BrokerLoadOptions loadOptions;

  /// Headroom beyond the weights: KV cache (low hundreds of MB at the 8192
  /// budget per ADR 0003) plus runtime overhead. Modest on purpose — the typed
  /// failure is retryable, so a borderline refusal costs one tap.
  static const int loadHeadroomBytes = 512 << 20;

  /// The boot-resolved configuration. Its path may be an operator sideload, so
  /// activation by its own key reuses it rather than re-deriving from catalog.
  final _Target _initial;

  /// The initial configuration's surface; the resident target may differ.
  BrokerEngine get engine => _initial.engine;
  String get modelPath => _initial.modelPath;
  ModelProfile get profile => _initial.profile;

  _Target? _resident;
  Future<void>? _activating;
  String? _activatingKey;
  int? _lastAvailableReading;
  final ValueNotifier<InferenceResidency> _residency =
      ValueNotifier<InferenceResidency>(const InferenceResidency.unloaded());

  @override
  ValueListenable<InferenceResidency> get residency => _residency;

  @override
  Future<void> prepare({String? modelKey}) =>
      _ensureResident(_targetFor(modelKey));

  @override
  Future<void> unload() async {
    // Let an in-flight activation settle first; its caller owns the error.
    final pending = _activating;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final resident = _resident;
    if (resident == null) return;
    try {
      await _runtime.unload();
    } catch (error) {
      // The load path logs its own (phase: 'load'), so without this the unload
      // half is the one engine failure nothing in the process records: the
      // controller above classifies it as a kind and drops the error (#130).
      _logFailure(resident.engine, phase: 'unload', error: error);
      rethrow;
    }
    _resident = null;
    _residency.value = const InferenceResidency.unloaded();
  }

  /// The generation a cancel applies to. The engine's own cancel reaches
  /// only a generation in flight; one requested while the generation is
  /// still activating its model would be lost, so it is remembered here and
  /// honoured the moment the activation returns.
  int _generationTicket = 0;
  int? _cancelledTicket;

  @override
  Future<void> cancel() {
    _cancelledTicket = _generationTicket;
    return _runtime.cancel();
  }

  @override
  void releaseEngine() {
    // No await anywhere on this path, deliberately: see the contract.
    _runtime.releaseEngine();
    _resident = null;
    _residency.value = const InferenceResidency.unloaded();
  }

  _Target _targetFor(String? modelKey) {
    if (modelKey == null || modelKey == _initial.catalogKey) return _initial;
    final config = resolveConfig(modelKey);
    return _Target(
      catalogKey: config.catalogKey,
      engine: config.engine,
      modelPath: config.modelPath,
      profile: config.profile,
      projectorPath: config.projectorPath,
      supportsImages: config.supportsImages,
    );
  }

  /// Single-flight per key: concurrent callers for the same key join the load
  /// in flight; a different key queues behind it rather than tripping the
  /// runtime's single-operation lifecycle.
  bool _isResident(_Target target) =>
      _resident != null && _resident!.catalogKey == target.catalogKey;

  Future<void> _ensureResident(
    _Target target, {
    BrokerLoadProgress? onProgress,
  }) {
    if (_isResident(target)) return Future.value();
    if (_activating != null && _activatingKey == target.catalogKey) {
      return _activating!;
    }
    final previous = _activating;
    _activatingKey = target.catalogKey;
    final activation = () async {
      if (previous != null) {
        // A failed predecessor reports to its own caller; this attempt goes on.
        try {
          await previous;
        } catch (_) {}
      }
      // `_resident == null` and a null-keyed target must not compare equal: a
      // sideloaded initial configuration has no catalog key.
      if (_resident != null && _resident!.catalogKey == target.catalogKey) {
        return;
      }
      if (_resident != null) {
        await _runtime.unload();
        _resident = null;
        _residency.value = const InferenceResidency.unloaded();
      }
      final path = _resolvePath(target.modelPath);
      try {
        await _preflightMemory(path);
      } catch (error) {
        _logFailure(target.engine, phase: 'preflight', error: error);
        rethrow;
      }
      try {
        await _runtime.load(
          engine: target.engine,
          modelPath: path,
          options: loadOptions,
          projectorPath: target.projectorPath == null
              ? null
              : _resolvePath(target.projectorPath!),
          onProgress: onProgress,
        );
      } catch (error) {
        _logFailure(target.engine, phase: 'load', error: error);
        rethrow;
      }
      _resident = target;
      _residency.value = InferenceResidency(
        loaded: true,
        catalogKey: target.catalogKey,
      );
    }();
    _activating = activation;
    activation.whenComplete(() {
      if (identical(_activating, activation)) {
        _activating = null;
        _activatingKey = null;
      }
    }).ignore();
    return activation;
  }

  String _resolvePath(String path) => path.startsWith('documents:')
      ? '$documentsDirectory/${path.substring('documents:'.length)}'
      : path;

  /// Refuses a load that cannot fit — typed and retryable — instead of letting
  /// the engine OOM into a crash or a misleading "damaged model" verdict.
  Future<void> _preflightMemory(String path) async {
    final probe = availableMemoryBytes;
    if (probe == null) return;
    final int? available;
    final int? required;
    try {
      available = await probe();
      required = await modelSizeBytes(path);
    } catch (_) {
      return;
    }
    _lastAvailableReading = available;
    if (available == null || required == null) return;
    if (available < required + loadHeadroomBytes) {
      throw const InferenceException(
        InferenceFailureKind.insufficientMemory,
        'Not enough free memory to load the model. Close other apps and '
        'try again.',
      );
    }
  }

  /// The file's own size, or a directory's file sum for MLX. Null when the path
  /// does not resolve — the load itself reports missing files with better copy.
  static Future<int?> _modelSizeOnDisk(String path) async {
    try {
      if (await File(path).exists()) return await File(path).length();
      final directory = Directory(path);
      if (!await directory.exists()) return null;
      var total = 0;
      await for (final entry in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File) total += await entry.length();
      }
      return total;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<InferenceEvent> generate({
    required List<PromptMessage> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
    GenerationObservation? observe,
    int? seed,
  }) {
    // Taken here, not in the generator: an `async*` body starts a microtask
    // after `listen`, and a cancel issued in between must name this run.
    final ticket = ++_generationTicket;
    // The generator learns when its consumer has gone: a generator parked
    // on the fractions stream outlives a cancelled subscription until the
    // load ends, and a load that fails then has nobody to throw to.
    var consumerGone = false;
    StreamSubscription<InferenceEvent>? inner;
    late final StreamController<InferenceEvent> controller;
    controller = StreamController<InferenceEvent>(
      onListen: () {
        inner =
            _generate(
              context: context,
              reasoningEnabled: reasoningEnabled,
              overrides: overrides,
              modelKey: modelKey,
              systemPrompt: systemPrompt,
              observe: observe,
              seed: seed,
              ticket: ticket,
              consumerGone: () => consumerGone,
            ).listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
      },
      onCancel: () {
        consumerGone = true;
        return inner?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<InferenceEvent> _generate({
    required List<PromptMessage> context,
    required bool reasoningEnabled,
    required SamplingOverrides? overrides,
    required String? modelKey,
    required String? systemPrompt,
    required GenerationObservation? observe,
    required int? seed,
    required int ticket,
    required bool Function() consumerGone,
  }) async* {
    final target = _targetFor(modelKey);
    // Phases are part of the observation: a caller that never asks — chat —
    // gets the stream it always had, byte for byte, like the fake.
    final observed = observe != null;
    final observation = observe ?? const GenerationObservation();
    if (_isResident(target)) {
      // Nothing to wait for.
    } else if (_activating != null && _activatingKey == target.catalogKey) {
      // Someone else's activation is in flight: join it silently. Its
      // fractions went to that caller, and a duration measured from here
      // would be the tail of a load this run did not make.
      await _ensureResident(target);
    } else {
      // This generation owns its activation, so the caller sees it as a
      // phase with a measured wall time rather than as silence before the
      // first token. The engine's fraction, when asked for, arrives on the
      // load's own callback and is forwarded here between the two phases.
      if (observed) yield const RunPhaseEvent(InferencePhase.loading);
      final loading = Stopwatch()..start();
      final fractions = StreamController<double>();
      final activation = _ensureResident(
        target,
        onProgress: observation.loadProgress ? fractions.add : null,
      );
      unawaited(activation.whenComplete(fractions.close).catchError((_) {}));
      await for (final fraction in fractions.stream) {
        yield LoadProgressEvent(fraction);
      }
      try {
        await activation;
      } catch (_) {
        // The activation logged its own failure; with the consumer gone a
        // rethrow would land in nobody's hands but the zone's.
        if (consumerGone()) return;
        rethrow;
      }
      if (observed) {
        yield RunPhaseEvent(
          InferencePhase.loaded,
          loadDuration: loading.elapsed,
        );
      }
    }
    if (_cancelledTicket == ticket) {
      yield const CompletedEvent(stopReason: InferenceStopReason.cancelled);
      return;
    }
    final profile = target.profile;
    final parser = profile.newParser(reasoningEnabled: reasoningEnabled);
    final effectiveSeed = seed ?? this.seed;
    final (sampling, overridesApplied) = effectiveSampling(
      profile: profile,
      defaults: profile.sampling(reasoningEnabled: reasoningEnabled),
      overrides: overrides,
      seed: effectiveSeed,
    );
    final promptChars = context.fold<int>(
      0,
      (sum, message) => sum + message.text.length,
    );
    // The engines' own budget check stays the backstop for estimation drift.
    final List<PromptMessage> windowed;
    try {
      windowed = windowedContext(
        context: context,
        contextLength:
            sampling.contextLength ??
            profile.sampling(reasoningEnabled: reasoningEnabled).contextLength,
        maxTokens: sampling.maxTokens,
        systemPrompt: systemPrompt,
        imageTokenCost: profile.spec.imageTokenCost,
      );
    } catch (error) {
      _logFailure(
        target.engine,
        phase: 'generate',
        error: error,
        sampling: sampling,
        promptChars: promptChars,
        windowedMessages: 0,
      );
      rethrow;
    }
    // Both templates accept an optional leading system turn; this is it.
    final renderedContext = systemPrompt == null || systemPrompt.isEmpty
        ? windowed
        : [PromptMessage.text('system', systemPrompt), ...windowed];
    // One image per rendered media marker, in the order the turns carry them.
    final images = [
      for (final message in renderedContext)
        for (final image in message.images) image,
    ];
    if (images.isNotEmpty && !target.supportsImages) {
      // The composer gates this: reaching here means an image-carrying chat was
      // pointed at a text-only model. Refuse before the engine.
      throw const InferenceException(
        InferenceFailureKind.unsupportedImages,
        'This model cannot read images. Pick a model that can, or remove the '
        'image.',
      );
    }
    BrokerRuntimeMetrics? finalMetrics;
    var sawAnswer = false;
    var sawOutput = false;
    final probe = effectiveSeed == null ? null : StringBuffer();
    if (observed) yield const RunPhaseEvent(InferencePhase.promptProcessing);
    // The last look before the engine is asked: a cancel that landed while
    // the phase above was being consumed would reach an engine that is not
    // generating yet, and be lost.
    if (_cancelledTicket == ticket) {
      yield const CompletedEvent(stopReason: InferenceStopReason.cancelled);
      return;
    }
    try {
      final loadedImages = await _loadImages(images);
      await for (final event in _runtime.generate(
        BrokerGenerationRequest(
          prompt: profile.render(
            renderedContext,
            reasoningEnabled: reasoningEnabled,
          ),
          sampling: sampling,
          images: loadedImages,
          observe: observation.isEmpty ? null : observation,
        ),
      )) {
        switch (event) {
          case BrokerTextDelta():
            if (!sawOutput) {
              sawOutput = true;
              if (observed) {
                yield const RunPhaseEvent(InferencePhase.generating);
              }
            }
            probe?.write(event.text);
            for (final domainEvent in _domainEvents(
              parser.consume(event.text),
            )) {
              if (domainEvent is AnswerDelta) sawAnswer = true;
              if (domainEvent is AnswerResetEvent) sawAnswer = false;
              yield domainEvent;
            }
          case BrokerMetricsDelta():
            final metrics = event.metrics;
            finalMetrics = metrics;
            yield MetricsEvent(
              InferenceMetrics(
                promptTokensPerSecond: metrics.promptTokensPerSecond,
                decodeTokensPerSecond: metrics.decodeTokensPerSecond,
                tokenCount: metrics.generatedTokenCount,
                elapsedSeconds: metrics.elapsedSeconds,
                promptTokenCount: metrics.promptTokenCount,
                timeToFirstTokenSeconds: metrics.timeToFirstTokenSeconds,
                peakPhysicalFootprintBytes: metrics.peakPhysicalFootprintBytes,
                // The engine's numbers carry the engine's contract.
                timingSemanticsVersion: metrics.timingSemanticsVersion,
                promptBatchSize: metrics.promptBatchSize,
              ),
            );
          case BrokerPromptProgress():
            yield PromptProgressEvent(
              completed: event.completed,
              total: event.total,
            );
          case BrokerTokenTiming():
            // An engine's first instant can land before the text it belongs
            // to is visible (a stop-sequence hold-back), and is output too.
            if (!sawOutput) {
              sawOutput = true;
              if (observed) {
                yield const RunPhaseEvent(InferencePhase.generating);
              }
            }
            yield TokenTimingEvent(
              kind: event.kind,
              firstIndex: event.firstIndex,
              timesMs: event.timesMs,
            );
          case BrokerGenerationCompleted():
            _logMetrics(
              target.engine,
              finalMetrics,
              event.reason,
              sampling,
              overridesApplied,
            );
            if (probe != null) {
              _logProbe(target.engine, probe.toString(), seed: effectiveSeed);
            }
            for (final domainEvent in _domainEvents(parser.finish())) {
              if (domainEvent is AnswerDelta) sawAnswer = true;
              yield domainEvent;
            }
            if (event.reason == BrokerStopReason.maxTokens && !sawAnswer) {
              throw const BrokerRuntimeException(
                'The response used its whole token budget before reaching an '
                'answer. Try again, or turn reasoning off.',
                kind: InferenceFailureKind.budgetExhaustedBeforeAnswer,
              );
            }
            yield CompletedEvent(
              stopReason: _stopReason(event.reason),
              rawTextHash: probe == null ? null : fnv1a64(probe.toString()),
              rawTextLength: probe?.length,
            );
        }
      }
    } catch (error) {
      _logFailure(
        target.engine,
        phase: 'generate',
        error: error,
        sampling: sampling,
        promptChars: promptChars,
        windowedMessages: windowed.length,
      );
      rethrow;
    }
  }

  /// One greppable line per completed generation — the on-device measurement
  /// channel, and the evidence that a settings change reached the engine.
  void _logMetrics(
    BrokerEngine engine,
    BrokerRuntimeMetrics? metrics,
    BrokerStopReason reason,
    BrokerSamplingParameters sampling,
    bool overridesApplied,
  ) {
    if (metrics == null) return;
    diagnosticSink?.call(
      'INFERNO_METRICS engine=${engine.name}'
      ' timingSemanticsVersion=${metrics.timingSemanticsVersion}'
      ' stopReason=${reason.name}'
      ' decodeTokensPerSecond=${metrics.decodeTokensPerSecond.toStringAsFixed(2)}'
      ' promptTokensPerSecond=${metrics.promptTokensPerSecond.toStringAsFixed(2)}'
      ' generatedTokenCount=${metrics.generatedTokenCount}'
      ' promptTokenCount=${metrics.promptTokenCount}'
      ' timeToFirstTokenSeconds=${metrics.timeToFirstTokenSeconds?.toStringAsFixed(3)}'
      ' elapsedSeconds=${metrics.elapsedSeconds.toStringAsFixed(2)}'
      ' peakPhysicalFootprintBytes=${metrics.peakPhysicalFootprintBytes}'
      ' temperature=${sampling.temperature}'
      ' topP=${sampling.topP}'
      ' topK=${sampling.topK}'
      ' presencePenalty=${sampling.presencePenalty}'
      ' maxTokens=${sampling.maxTokens}'
      ' contextLength=${sampling.contextLength}'
      ' seed=${sampling.seed}'
      ' promptBatchSize=${metrics.promptBatchSize}'
      ' overridesApplied=$overridesApplied',
    );
  }

  /// The INFERNO_METRICS counterpart for paths that never reach a completion
  /// event (#63). User copy never rides here, only classification.
  void _logFailure(
    BrokerEngine engine, {
    required String phase,
    required Object error,
    BrokerSamplingParameters? sampling,
    int? promptChars,
    int? windowedMessages,
  }) {
    final code = error is InferenceException ? error.kind.name : 'unknown';
    diagnosticSink?.call(
      'INFERNO_FAILURE engine=${engine.name}'
      ' phase=$phase'
      ' code=$code'
      ' promptChars=$promptChars'
      ' contextLength=${sampling?.contextLength}'
      ' maxTokens=${sampling?.maxTokens}'
      ' windowedMessages=$windowedMessages'
      ' availableMemoryBytes=$_lastAvailableReading',
    );
  }

  /// Hashes the raw pre-parser text so two devices can be compared for
  /// token-identical output without shipping transcripts through logs.
  void _logProbe(BrokerEngine engine, String rawText, {required int? seed}) {
    diagnosticSink?.call(
      'INFERNO_PROBE engine=${engine.name}'
      ' seed=$seed'
      ' chars=${rawText.length}'
      ' fnv1a64=${fnv1a64(rawText)}',
    );
  }

  static InferenceStopReason _stopReason(BrokerStopReason reason) =>
      switch (reason) {
        BrokerStopReason.endOfSequence => InferenceStopReason.endOfSequence,
        BrokerStopReason.stopSequence => InferenceStopReason.stopSequence,
        BrokerStopReason.stopToken => InferenceStopReason.stopToken,
        BrokerStopReason.maxTokens => InferenceStopReason.maxTokens,
        BrokerStopReason.cancelled => InferenceStopReason.cancelled,
      };

  static Iterable<InferenceEvent> _domainEvents(
    ReasoningStreamDelta delta,
  ) sync* {
    if (delta.resetAnswer) yield const AnswerResetEvent();
    if (delta.reasoning.isNotEmpty) yield ReasoningDelta(delta.reasoning);
    if (delta.answer.isNotEmpty) yield AnswerDelta(delta.answer);
  }
}

/// [catalogKey] is null only for a sideloaded initial configuration.
final class _Target {
  const _Target({
    required this.catalogKey,
    required this.engine,
    required this.modelPath,
    required this.profile,
    this.projectorPath,
    this.supportsImages = false,
  });

  final String? catalogKey;
  final BrokerEngine engine;
  final String modelPath;
  final ModelProfile profile;

  /// Only ever paired with the weights it was pinned against.
  final String? projectorPath;
  final bool supportsImages;
}
