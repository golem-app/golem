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
        // The engine accepted the request here: the instants' clock starts
        // now, not when the run did, since the load sat between the two.
        InferencePhase.promptProcessing => _advance(
          run,
          LabRunPhase.promptProcessing,
        ).copyWith(acceptedAt: run.acceptedAt ?? now ?? DateTime.now()),
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

/// Stop was pressed: the run reads as cancelling, in the phase it reached,
/// until the engine ends the stream — which then records as cancelled
/// whether it ends in a completion or, as a cancelled load does, an error.
LabRun requestCancel(LabRun run) =>
    run.isTerminal ? run : run.copyWith(cancelRequested: true);

/// The stream ended in an error: partial output and the snapshot stay. After
/// Stop the error is the cancellation's, so the run reads as cancelled.
LabRun failRun(
  LabRun run,
  InferenceFailureKind kind, {
  int? contextTokens,
  DateTime? now,
}) {
  if (run.isTerminal) return run;
  if (run.cancelRequested) {
    return run.copyWith(
      phase: LabRunPhase.cancelled,
      stopReason: InferenceStopReason.cancelled,
      endedAt: now ?? DateTime.now(),
    );
  }
  return run.copyWith(
    phase: LabRunPhase.failed,
    failure: kind,
    failureContextTokens: contextTokens,
    endedAt: now ?? DateTime.now(),
  );
}

/// Phases only move forward, and never after Stop: a stream that keeps
/// producing is still a run being cancelled in the phase it reached.
LabRun _advance(LabRun run, LabRunPhase phase) =>
    run.cancelRequested || run.phase.reaches(phase)
    ? run
    : run.copyWith(phase: phase);
