import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

/// The operator sideload seam, where `prepare()` is both the load and the
/// check. Shared because two suites drive the same startup gate: a fake whose
/// idea of "a validated sideload" drifts between them proves nothing.
final class ValidatingSideload implements InferenceRepository {
  ValidatingSideload({this.failuresRemaining = 0, this.park = false});

  /// Each `prepare()` throws while this is positive, and decrements.
  int failuresRemaining;

  /// While true, `prepare()` blocks until [release], so a test can observe
  /// what the gate renders *during* a multi-gigabyte load.
  bool park;

  int prepareCalls = 0;
  Completer<void>? _parked;

  void release() {
    _parked?.complete();
    _parked = null;
  }

  final ValueNotifier<InferenceResidency> _residency =
      ValueNotifier<InferenceResidency>(const InferenceResidency.unloaded());

  @override
  ValueListenable<InferenceResidency> get residency => _residency;

  @override
  void releaseEngine() {}

  @override
  Future<void> prepare({String? modelKey}) async {
    prepareCalls++;
    if (park) {
      final gate = _parked = Completer<void>();
      await gate.future;
    }
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const InferenceException(
        InferenceFailureKind.invalidModelArtifact,
        'injected invalid sideload',
      );
    }
    _residency.value = const InferenceResidency(loaded: true);
  }

  @override
  Future<void> unload() async =>
      _residency.value = const InferenceResidency.unloaded();

  @override
  Future<void> cancel() async {}

  @override
  Stream<InferenceEvent> generate({
    required List<PromptMessage> context,
    required bool reasoningEnabled,
    SamplingOverrides? overrides,
    String? modelKey,
    String? systemPrompt,
  }) => const Stream.empty();
}
