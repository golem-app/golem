import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/app_state.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';

part 'benchmark_providers.g.dart';

/// KeepAlive — a decision, not the old blanket default: a running benchmark
/// keeps running and its result survives leaving the screen.
@Riverpod(keepAlive: true, retry: noRetry)
class BenchmarkController extends _$BenchmarkController {
  int _epoch = 0;

  @override
  BenchmarkState build() => const BenchmarkState();

  // A result belongs to the exact case/phase it was produced for.
  void selectCase(String caseId) =>
      state = state.copyWith(caseId: caseId, clearResult: true);
  void selectPhase(BenchmarkPhase phase) =>
      state = state.copyWith(phase: phase, clearResult: true);

  Future<void> run() async {
    final epoch = ++_epoch;
    state = state.copyWith(isRunning: true, clearResult: true);
    final result = await ref
        .read(benchmarkRepositoryProvider)
        .run(state.caseId, state.phase);
    if (epoch != _epoch) return;
    state = state.copyWith(isRunning: false, result: result);
  }

  void stop() {
    _epoch++;
    state = state.copyWith(isRunning: false);
  }

  Future<String?> export() async {
    final result = state.result;
    if (result == null) return null;
    return ref.read(benchmarkRepositoryProvider).export(result);
  }
}
