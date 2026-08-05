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
  static const _answer = <String>[
    'This is a deterministic response from Golem’s simulated backend. ',
    'It exercises streaming, cancellation, editing, persistence, and metrics ',
    'without loading a model or measuring this device.',
  ];

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
  }) async* {
    if (!_prepared) throw StateError('The simulated runtime is unloaded.');
    final epoch = ++_generationEpoch;
    final prompt = context.lastOrNull?['content'] ?? '';
    if (prompt.contains('[fail]')) {
      if (reasoningEnabled) yield const ReasoningDelta('A partial thought…');
      yield const AnswerDelta('A partial simulated response');
      throw StateError('Injected simulated generation failure.');
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
    for (final part in _answer) {
      await Future<void>.delayed(eventDelay);
      if (epoch != _generationEpoch) {
        yield const CompletedEvent();
        return;
      }
      tokens += part.split(RegExp(r'\s+')).length;
      yield AnswerDelta(part);
      yield MetricsEvent(
        InferenceMetrics(
          promptTokensPerSecond: 144,
          decodeTokensPerSecond: 21.4,
          tokenCount: tokens,
          elapsedSeconds: tokens / 21.4,
        ),
      );
    }
    yield const CompletedEvent();
  }
}
