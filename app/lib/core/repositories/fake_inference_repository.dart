import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../domain/generation_settings.dart';
import '../domain/model_catalog.dart';
import '../domain/models.dart';
import 'contracts.dart';

/// Deterministic UI simulation. It never loads a model or performs inference.
final class FakeInferenceRepository implements InferenceRepository {
  FakeInferenceRepository({
    this.eventDelay = const Duration(milliseconds: 34),
    List<ModelCatalogEntry> Function()? catalog,
  }) : _catalog = catalog ?? _noCatalog;
  final Duration eventDelay;

  /// The catalog to name artifacts from, read per turn so a repository added
  /// after launch is reachable. The simulation must name the artifact the
  /// user picked, and `displayName` is the one place that name is declared.
  /// Empty in a bare construction, which only costs the generic fallback.
  final List<ModelCatalogEntry> Function() _catalog;

  static List<ModelCatalogEntry> _noCatalog() => const <ModelCatalogEntry>[];
  bool _prepared = true;
  int _generationEpoch = 0;

  /// Observable so a test can assert teardown actually ran, rather than
  /// inferring it from state the simulation starts in anyway.
  int releases = 0;

  /// Same reason as [releases]: bumping an epoch leaves no trace a test can
  /// read, and cancellation on the way out of the provider (#127) has to be
  /// provable rather than inferred from a stream that would have ended anyway.
  int cancels = 0;
  final ValueNotifier<InferenceResidency> _residency =
      ValueNotifier<InferenceResidency>(const InferenceResidency.unloaded());

  @override
  ValueListenable<InferenceResidency> get residency => _residency;

  static const _reasoning = <String>[
    'I’ll identify the main idea. ',
    'Then I’ll keep the answer concise and useful.',
  ];

  // Markdown-bearing on purpose: renderer, goldens and journeys all exercise
  // paragraphs, inline code, a fenced block and a list from this one reply.
  static const _answer = <String>[
    'This is a deterministic response from Golem’s simulated backend — '
        'no model is loaded and nothing measures this device.\n\n',
    'Use the built-in `csv` module. It streams row by row, so memory '
        'stays flat no matter how big the file is.\n\n',
    '```python\nimport csv\n\ndef rows(path):\n'
        '    with open(path, newline="") as file:\n'
        '        yield from csv.reader(file)\n```\n\n',
    'Two things worth knowing:\n\n',
    '- `newline=""` stops Python mangling quoted line breaks.\n',
    '- Swap in **DictReader** if the file has a header row.',
  ];

  /// Invented, deterministic, and labelled `simulated` wherever it surfaces —
  /// but ordered like the artifacts they stand for. Keying these on a
  /// `startsWith('qwen35')` prefix charged Qwen 3.5 2B the 4B's rate, so the
  /// simulation claimed the smaller model was the slower one, contradicting
  /// the catalog's own copy for it (#118).
  static const _simulatedDecodeRates = <String, double>{
    'gemma4': 21.4,
    'qwen35-2b': 24.6,
    'qwen35': 14.2,
  };

  /// Simulated per-model voice and speed, so the picker is provable. The name
  /// comes from the catalog rather than a prefix match, so it stays correct
  /// for every entry and for any added later.
  ({String name, double decodeRate}) _profileFor(String? modelKey) {
    final entry = _catalog().where((item) => item.key == modelKey).firstOrNull;
    // Longest prefix wins, so `qwen35-2b-*` cannot fall through to `qwen35`.
    final matches =
        _simulatedDecodeRates.keys
            .where((prefix) => modelKey?.startsWith('$prefix-') ?? false)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    return (
      name: entry?.displayName ?? 'the default model',
      decodeRate: _simulatedDecodeRates[matches.firstOrNull] ?? 21.4,
    );
  }

  @override
  Future<void> prepare({String? modelKey}) async {
    await Future<void>.delayed(eventDelay);
    _prepared = true;
    if (modelKey != null) {
      _residency.value = InferenceResidency(loaded: true, catalogKey: modelKey);
    }
  }

  @override
  Future<void> unload() async {
    _generationEpoch++;
    _prepared = false;
    _residency.value = const InferenceResidency.unloaded();
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _generationEpoch++;
  }

  @override
  void releaseEngine() {
    releases++;
    _generationEpoch++;
    _prepared = false;
    _residency.value = const InferenceResidency.unloaded();
  }

  @override
  Stream<InferenceEvent> generate({
    required List<PromptMessage> context,
    required bool reasoningEnabled,
    // Deliberately unused: deterministic simulation has no sampling.
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
    GenerationObservation? observe,
    // Deliberately unused: nothing here samples, so nothing is seeded.
    int? seed,
  }) async* {
    if (!_prepared) throw StateError('The simulated runtime is unloaded.');
    final epoch = ++_generationEpoch;
    final observation = observe ?? const GenerationObservation();
    // An observed activation is a phase with a determinate, invented load —
    // the bench's goldens and journeys need every state without weights.
    // Unobserved (chat), residency flips silently as it always did.
    final activates =
        modelKey != null && _residency.value.catalogKey != modelKey;
    if (activates && !observation.isEmpty) {
      yield const RunPhaseEvent(InferencePhase.loading);
      if (observation.loadProgress) {
        for (final fraction in const [0.25, 0.5, 0.75, 1.0]) {
          await Future<void>.delayed(eventDelay);
          if (epoch != _generationEpoch) {
            yield const CompletedEvent();
            return;
          }
          yield LoadProgressEvent(fraction);
        }
      }
      yield const RunPhaseEvent(
        InferencePhase.loaded,
        loadDuration: Duration(milliseconds: 1240),
      );
    }
    if (modelKey != null) {
      _residency.value = InferenceResidency(loaded: true, catalogKey: modelKey);
    }
    final profile = _profileFor(modelKey);
    final last = context.lastOrNull;
    final prompt = last?.text ?? '';
    // The prompt "prefills" in two halves; four characters stand in for a
    // token, which is the broker's own estimate.
    final promptTokens = prompt.isEmpty ? 1 : (prompt.length / 4).ceil();
    if (!observation.isEmpty) {
      yield const RunPhaseEvent(InferencePhase.promptProcessing);
      if (observation.promptProgress) {
        for (final completed in [promptTokens ~/ 2, promptTokens]) {
          yield PromptProgressEvent(completed: completed, total: promptTokens);
        }
      }
    }
    // Deterministic ack so journeys can exercise an image turn offline.
    final attachedImages = last?.images.length ?? 0;
    if (attachedImages > 0) {
      yield AnswerDelta(
        attachedImages == 1
            ? 'I can see the image you attached. '
            : 'I can see the $attachedImages images you attached. ',
      );
    }
    if (prompt.contains('[fail]')) {
      if (reasoningEnabled) yield const ReasoningDelta('A partial thought…');
      yield const AnswerDelta('A partial simulated response');
      throw const InferenceException(
        InferenceFailureKind.engine,
        'Injected simulated generation failure.',
      );
    }
    if (prompt.contains('[oom]')) {
      // Metrics land before the failure so the transcript can render the
      // design's "Stopped after N tokens" caption under the partial.
      yield const AnswerDelta('A partial simulated response');
      yield MetricsEvent(
        InferenceMetrics(
          promptTokensPerSecond: 144,
          decodeTokensPerSecond: profile.decodeRate,
          tokenCount: 41,
          elapsedSeconds: 41 / profile.decodeRate,
        ),
      );
      throw const InferenceException(
        InferenceFailureKind.outOfMemory,
        'Ran out of memory at 4,096 tokens. Lower the context length or '
        'pick a smaller model.',
        contextTokens: 4096,
      );
    }
    if (prompt.contains('[context]')) {
      // Banner action is New chat, never Retry — provable without a window.
      throw const InferenceException(
        InferenceFailureKind.contextExhausted,
        'This conversation no longer fits the model’s context window. '
        'Start a new chat to continue.',
      );
    }
    if (reasoningEnabled) {
      for (final part in _reasoning) {
        await Future<void>.delayed(eventDelay);
        if (epoch != _generationEpoch) {
          yield const CompletedEvent();
          return;
        }
        yield ReasoningDelta(part);
      }
    }
    // Acknowledged here, after the failure branches and the reasoning loop:
    // answer text arriving while reasoning still streams would end the
    // reasoning card's live state, and the injections must stay pristine.
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      yield const AnswerDelta(
        'Simulated note: your custom system prompt is applied.\n\n',
      );
    }
    var tokens = 0;
    for (final (index, part) in _answer.indexed) {
      await Future<void>.delayed(eventDelay);
      if (epoch != _generationEpoch) {
        yield const CompletedEvent();
        return;
      }
      if (index == 0 && !observation.isEmpty) {
        yield const RunPhaseEvent(InferencePhase.generating);
      }
      final before = tokens;
      tokens += part.split(RegExp(r'\s+')).length;
      yield AnswerDelta(
        index == 0 && modelKey != null
            ? 'Simulated ${profile.name} here. $part'
            : part,
      );
      if (observation.tokenTiming) {
        // One instant per invented token, on an invented clock: a steady
        // cadence from a 310 ms first token, with one stall at the eighth
        // token so a latency chart has something honest to show a stall as.
        yield TokenTimingEvent(
          kind: ObservationKind.token,
          firstIndex: before,
          timesMs: [
            for (var i = before; i < tokens; i++)
              310 + i * (1000 / profile.decodeRate) + (i >= 7 ? 130 : 0),
          ],
        );
      }
      yield MetricsEvent(
        InferenceMetrics(
          promptTokensPerSecond: 144,
          decodeTokensPerSecond: profile.decodeRate,
          tokenCount: tokens,
          elapsedSeconds: tokens / profile.decodeRate,
          // Measurement-grade fields only when a bench asked: chat's
          // simulated metrics stay exactly what its goldens record.
          promptTokenCount: observation.isEmpty ? null : promptTokens,
          timeToFirstTokenSeconds: observation.isEmpty ? null : 0.31,
        ),
      );
    }
    yield const CompletedEvent();
  }
}
