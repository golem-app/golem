import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/domain/generation_settings.dart';
import '../core/domain/models.dart';
import '../core/repositories/contracts.dart';
import 'context_window.dart';
import 'hash.dart';
import 'model_profile.dart';
import 'model_runtime_config.dart';
import 'runtime.dart';

/// The single owner of engine residency (#42): exactly one model is loaded
/// at a time, activation is keyed by catalog entry, and every load or
/// unload of weights goes through this repository.
final class InfernoInferenceRepository implements InferenceRepository {
  InfernoInferenceRepository(
    this._runtime, {
    required BrokerEngine engine,
    required String modelPath,
    required ModelProfile profile,
    String? initialCatalogKey,
    this.documentsDirectory = '',
    this.resolveConfig = resolveModelRuntimeConfig,
    this.availableMemoryBytes,
    this.modelSizeBytes = _modelSizeOnDisk,
    this.seed,
  }) : _initial = _Target(
         catalogKey: initialCatalogKey,
         engine: engine,
         modelPath: modelPath,
         profile: profile,
       );

  final BrokerRuntime _runtime;
  final int? seed;
  final String documentsDirectory;
  final ModelRuntimeConfig Function(String catalogKey) resolveConfig;

  /// Free-memory probe for the load preflight; null (no probe) or a null
  /// reading skips the preflight — the engine's own failure stays the
  /// loud path when the platform cannot report headroom.
  final Future<int?> Function()? availableMemoryBytes;

  /// Size of the artifact at a resolved path; null skips the preflight.
  final Future<int?> Function(String path) modelSizeBytes;

  /// Headroom the preflight demands beyond the weights themselves: KV
  /// cache (low hundreds of MB at the 8192 budget per ADR 0003) plus
  /// runtime overhead. Deliberately conservative-but-modest; the typed
  /// failure is retryable, so a borderline refusal costs one tap.
  static const int loadHeadroomBytes = 512 << 20;

  /// The boot-resolved configuration. Its model path may be an operator
  /// sideload, so activation by its own key must reuse this path rather
  /// than re-derive it from the catalog.
  final _Target _initial;

  /// The initial configuration's surface, kept public for construction
  /// tests and diagnostics; the resident target may differ at runtime.
  BrokerEngine get engine => _initial.engine;
  String get modelPath => _initial.modelPath;
  ModelProfile get profile => _initial.profile;

  _Target? _resident;
  Future<void>? _activating;
  String? _activatingKey;
  final ValueNotifier<String?> _residentKey = ValueNotifier<String?>(null);

  @override
  ValueListenable<String?> get residentModelKey => _residentKey;

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
    if (_resident == null) return;
    await _runtime.unload();
    _resident = null;
    _residentKey.value = null;
  }

  @override
  Future<void> cancel() => _runtime.cancel();

  /// The configuration a request addresses: the initial one for null or
  /// its own key, otherwise the catalog resolution for [modelKey].
  _Target _targetFor(String? modelKey) {
    if (modelKey == null || modelKey == _initial.catalogKey) return _initial;
    final config = resolveConfig(modelKey);
    return _Target(
      catalogKey: config.catalogKey,
      engine: config.engine,
      modelPath: config.modelPath,
      profile: config.profile,
    );
  }

  /// Activates [target] unless it is already resident. Single-flight per
  /// key: concurrent callers for the same key join the load in flight; a
  /// different key queues behind it rather than tripping the runtime's
  /// single-operation lifecycle.
  Future<void> _ensureResident(_Target target) {
    if (_resident != null && _resident!.catalogKey == target.catalogKey) {
      return Future.value();
    }
    if (_activating != null && _activatingKey == target.catalogKey) {
      return _activating!;
    }
    final previous = _activating;
    _activatingKey = target.catalogKey;
    final activation = () async {
      if (previous != null) {
        // A failed predecessor reports to its own caller; this activation
        // still gets its attempt.
        try {
          await previous;
        } catch (_) {}
      }
      // Note `_resident == null` and a null-keyed target must not compare
      // equal: a sideloaded initial configuration has no catalog key.
      if (_resident != null && _resident!.catalogKey == target.catalogKey) {
        return;
      }
      if (_resident != null) {
        await _runtime.unload();
        _resident = null;
        _residentKey.value = null;
      }
      final path = _resolvePath(target.modelPath);
      await _preflightMemory(path);
      await _runtime.load(engine: target.engine, modelPath: path);
      _resident = target;
      _residentKey.value = target.catalogKey;
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

  /// Refuses a load that cannot fit — typed and retryable — instead of
  /// letting the engine OOM into a crash or a misleading "damaged model"
  /// verdict. Skipped whenever either reading is unknown (§8: the
  /// repository hides the probe mechanism; the controller owns the copy's
  /// consequences).
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
    if (available == null || required == null) return;
    if (available < required + loadHeadroomBytes) {
      throw const InferenceException(
        InferenceFailureKind.insufficientMemory,
        'Not enough free memory to load the model. Close other apps and '
        'try again.',
      );
    }
  }

  /// Weights on disk: the file's own size, or a directory's file sum for
  /// MLX artifacts. Null (skip) when the path does not resolve — the load
  /// itself reports missing files with better copy.
  static Future<int?> _modelSizeOnDisk(String path) async {
    try {
      if (await File(path).exists()) return File(path).length();
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
    required List<Map<String, String>> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
  }) async* {
    // Activate the addressed configuration when it is not already
    // resident (#42); the load joins any activation in flight.
    final target = _targetFor(modelKey);
    await _ensureResident(target);
    final profile = target.profile;
    final parser = profile.newParser(reasoningEnabled: reasoningEnabled);
    final (sampling, overridesApplied) = _effectiveSampling(
      profile,
      profile.sampling(reasoningEnabled: reasoningEnabled),
      overrides,
    );
    // Window the conversation before rendering: newest turns that fit the
    // budget, typed contextExhausted when even the final turn cannot. The
    // engines' own budget check stays the backstop for estimation drift.
    final windowed = windowedContext(
      context: context,
      contextLength:
          sampling.contextLength ??
          profile.sampling(reasoningEnabled: reasoningEnabled).contextLength,
      maxTokens: sampling.maxTokens,
      systemPrompt: systemPrompt,
    );
    // Both profile templates accept an optional leading system turn; the
    // custom prompt becomes exactly that, ahead of the conversation.
    final renderedContext = systemPrompt == null || systemPrompt.isEmpty
        ? windowed
        : [
            {'role': 'system', 'content': systemPrompt},
            ...windowed,
          ];
    BrokerRuntimeMetrics? finalMetrics;
    var sawAnswer = false;
    final probe = seed == null ? null : StringBuffer();
    await for (final event in _runtime.generate(
      BrokerGenerationRequest(
        prompt: profile.render(
          renderedContext,
          reasoningEnabled: reasoningEnabled,
        ),
        sampling: sampling,
      ),
    )) {
      switch (event) {
        case BrokerTextDelta():
          probe?.write(event.text);
          for (final domainEvent in _domainEvents(parser.consume(event.text))) {
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
            ),
          );
        case BrokerGenerationCompleted():
          _logMetrics(
            target.engine,
            finalMetrics,
            event.reason,
            sampling,
            overridesApplied,
          );
          if (probe != null) _logProbe(target.engine, probe.toString());
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
  }

  /// Merges the user's sparse overrides onto the profile's defaults.
  /// Pinned modes keep their sampling fields (a correctness constraint —
  /// see the profile); token budgets stay the user's to size. Returns the
  /// effective parameters and whether any override was actually consumed.
  (BrokerSamplingParameters, bool) _effectiveSampling(
    ModelProfile profile,
    ProfileSampling defaults,
    SamplingOverrides? overrides,
  ) {
    final user = overrides ?? const SamplingOverrides();
    final samplingOverridable = !defaults.pinned;
    final applied =
        user.maxTokens != null ||
        user.contextLength != null ||
        (samplingOverridable &&
            (user.temperature != null ||
                user.topP != null ||
                user.topK != null));
    return (
      BrokerSamplingParameters(
        maxTokens: user.maxTokens ?? defaults.maxTokens,
        temperature: samplingOverridable
            ? (user.temperature ?? defaults.temperature)
            : defaults.temperature,
        topP: samplingOverridable
            ? (user.topP ?? defaults.topP)
            : defaults.topP,
        topK: samplingOverridable
            ? (user.topK ?? defaults.topK)
            : defaults.topK,
        contextLength: user.contextLength ?? defaults.contextLength,
        seed: seed,
        stopSequences: profile.stopSequences,
        stopTokenIds: profile.stopTokenIds,
      ),
      applied,
    );
  }

  /// One greppable line per completed generation; this is the capture channel
  /// for on-device measurement (the app contract carries only core metrics).
  /// The effective sampling fields are the evidence that a settings change
  /// actually reached the engine.
  void _logMetrics(
    BrokerEngine engine,
    BrokerRuntimeMetrics? metrics,
    BrokerStopReason reason,
    BrokerSamplingParameters sampling,
    bool overridesApplied,
  ) {
    if (metrics == null) return;
    debugPrint(
      'INFERNO_METRICS engine=${engine.name}'
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
      ' maxTokens=${sampling.maxTokens}'
      ' contextLength=${sampling.contextLength}'
      ' seed=${sampling.seed}'
      ' overridesApplied=$overridesApplied',
    );
  }

  /// One greppable line per seeded generation, hashing the raw pre-parser
  /// text so two devices can be compared for token-identical output without
  /// shipping the transcript through logs. Only emitted when a fixed seed is
  /// configured (`GOLEM_SAMPLING_SEED`), i.e. during determinism probes.
  void _logProbe(BrokerEngine engine, String rawText) {
    debugPrint(
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

/// One activatable configuration. [catalogKey] is null only for a
/// sideloaded initial configuration whose backend derives no artifact key.
final class _Target {
  const _Target({
    required this.catalogKey,
    required this.engine,
    required this.modelPath,
    required this.profile,
  });

  final String? catalogKey;
  final BrokerEngine engine;
  final String modelPath;
  final ModelProfile profile;
}
