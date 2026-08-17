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
  int cancels = 0;
  int disposes = 0;
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
    _generationEpoch++;
    cancels++;
  }

  /// Nothing native to release; the epoch bump ends any simulated stream so
  /// callers observe the same terminal behaviour as the real backend.
  @override
  Future<void> dispose() async {
    disposes++;
    await unload();
  }

  @override
  Stream<InferenceEvent> generate({
    required List<PromptMessage> context,
    required bool reasoningEnabled,
    // Deliberately unused: deterministic simulation has no sampling.
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
  }) async* {
    if (!_prepared) throw StateError('The simulated runtime is unloaded.');
    final epoch = ++_generationEpoch;
    if (modelKey != null) {
      _residency.value = InferenceResidency(loaded: true, catalogKey: modelKey);
    }
    final profile = _profileFor(modelKey);
    final last = context.lastOrNull;
    final prompt = last?.text ?? '';
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
      tokens += part.split(RegExp(r'\s+')).length;
      yield AnswerDelta(
        index == 0 && modelKey != null
            ? 'Simulated ${profile.name} here. $part'
            : part,
      );
      yield MetricsEvent(
        InferenceMetrics(
          promptTokensPerSecond: 144,
          decodeTokensPerSecond: profile.decodeRate,
          tokenCount: tokens,
          elapsedSeconds: tokens / profile.decodeRate,
        ),
      );
    }
    yield const CompletedEvent();
  }
}
