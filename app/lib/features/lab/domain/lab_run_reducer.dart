import '../../../core/domain/models.dart';
import '../../../core/repositories/contracts.dart';
import 'lab_run.dart';

/// Folds one streaming event into a run. Pure, and the one statement of how
/// the engine's events become bench state; the controller only decides which
/// run an event belongs to.
///
/// A terminal run is returned unchanged: the stream may still carry a late
/// metrics or completion event after Stop, and a run ends exactly once.
LabRun reduceLabRun(LabRun run, InferenceEvent event, {DateTime? now}) {
  if (run.isTerminal) return run;
  final telemetry = run.telemetry;
  switch (event) {
    case RunPhaseEvent():
      return switch (event.phase) {
        InferencePhase.loading => _advance(run, LabRunPhase.loading),
        InferencePhase.loaded => run.copyWith(
          telemetry: telemetry.copyWith(
            loadDuration: event.loadDuration,
            // An engine that reported no fraction still finished its load.
            loadFraction: 1,
          ),
        ),
        InferencePhase.promptProcessing => _advance(
          run,
          LabRunPhase.promptProcessing,
        ),
        InferencePhase.generating => _advance(run, LabRunPhase.generating),
      };
    case LoadProgressEvent():
      // Only ever climbing: a late fraction never pulls a finished bar back.
      return run.copyWith(
        telemetry: telemetry.copyWith(
          loadFraction: telemetry.loadFraction == null
              ? event.fraction
              : (event.fraction > telemetry.loadFraction!
                    ? event.fraction
                    : telemetry.loadFraction),
        ),
      );
    case PromptProgressEvent():
      return run.copyWith(
        telemetry: telemetry.copyWith(
          promptCompleted: event.completed,
          promptTotal: event.total,
        ),
      );
    case TokenTimingEvent():
      return _advance(
        run,
        LabRunPhase.generating,
      ).copyWith(telemetry: telemetry.withInstants(event.kind, event.timesMs));
    case ReasoningDelta():
      return _advance(
        run,
        LabRunPhase.generating,
      ).copyWith(reasoning: '${run.reasoning}${event.text}');
    case AnswerDelta():
      return _advance(
        run,
        LabRunPhase.generating,
      ).copyWith(answer: '${run.answer}${event.text}');
    case AnswerResetEvent():
      return run.copyWith(answer: '');
    case MetricsEvent():
      return run.copyWith(metrics: event.metrics);
    case CompletedEvent():
      final cancelled =
          run.cancelRequested ||
          event.stopReason == InferenceStopReason.cancelled;
      return run.copyWith(
        phase: cancelled ? LabRunPhase.cancelled : LabRunPhase.completed,
        stopReason: event.stopReason,
        endedAt: now ?? DateTime.now(),
      );
  }
}

/// Stop was pressed: the run reads as cancelling until the engine ends the
/// stream, which the reducer then records as cancelled.
LabRun requestCancel(LabRun run) => run.isTerminal
    ? run
    : run.copyWith(phase: LabRunPhase.cancelling, cancelRequested: true);

/// The stream ended in an error: partial output and the snapshot stay.
LabRun failRun(
  LabRun run,
  InferenceFailureKind kind, {
  int? contextTokens,
  DateTime? now,
}) => run.isTerminal
    ? run
    : run.copyWith(
        phase: LabRunPhase.failed,
        failure: kind,
        failureContextTokens: contextTokens,
        endedAt: now ?? DateTime.now(),
      );

/// Phases only move forward, and never out of cancelling: a stream that keeps
/// producing after Stop is still a run being cancelled.
LabRun _advance(LabRun run, LabRunPhase phase) =>
    run.phase == LabRunPhase.cancelling || run.phase.reaches(phase)
    ? run
    : run.copyWith(phase: phase);
