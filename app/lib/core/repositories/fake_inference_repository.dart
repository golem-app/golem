import 'dart:async';

import '../domain/generation_settings.dart';
import '../domain/models.dart';
import 'contracts.dart';

/// Deterministic UI simulation. It never loads a model or performs inference.
final class FakeInferenceRepository implements InferenceRepository {
  FakeInferenceRepository({this.eventDelay = const Duration(milliseconds: 34)});
  final Duration eventDelay;
  bool _prepared = true;
  int _generationEpoch = 0;

  static const _reasoning = <String>[
    'I’ll identify the main idea. ',
    'Then I’ll keep the answer concise and useful.',
  ];

  // Markdown-bearing on purpose: the transcript renderer, goldens, and
  // journeys all exercise paragraphs, inline code, a fenced block, and a
  // list from this one deterministic reply.
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

  /// Simulated per-model voice and speed, so the per-chat model picker is
  /// provable end to end without a real engine.
  static ({String name, double decodeRate}) _profileFor(String? modelKey) =>
      switch (modelKey) {
        final key? when key.startsWith('qwen35') => (
          name: 'Qwen 3.5 4B',
          decodeRate: 14.2,
        ),
        final key? when key.startsWith('gemma4') => (
          name: 'Gemma 4 E2B',
          decodeRate: 21.4,
        ),
        _ => (name: 'the default model', decodeRate: 21.4),
      };

  @override
  Future<void> prepare() async {
    await Future<void>.delayed(eventDelay);
    _prepared = true;
  }

  @override
  Future<void> unload() async {
    _generationEpoch++;
    _prepared = false;
  }

  @override
  Future<void> cancel() async => _generationEpoch++;

  @override
  Stream<InferenceEvent> generate({
    required List<Map<String, String>> context,
    required bool reasoningEnabled,
    // Deliberately unused: deterministic simulation has no sampling.
    SamplingOverrides? overrides,
    String? modelKey,
  }) async* {
    if (!_prepared) throw StateError('The simulated runtime is unloaded.');
    final epoch = ++_generationEpoch;
    final profile = _profileFor(modelKey);
    final prompt = context.lastOrNull?['content'] ?? '';
    if (prompt.contains('[fail]')) {
      if (reasoningEnabled) yield const ReasoningDelta('A partial thought…');
      yield const AnswerDelta('A partial simulated response');
      throw StateError('Injected simulated generation failure.');
    }
    if (prompt.contains('[oom]')) {
      yield const AnswerDelta('A partial simulated response');
      throw StateError(
        'Ran out of memory at 4,096 tokens. Lower the context length or '
        'pick a smaller model.',
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
