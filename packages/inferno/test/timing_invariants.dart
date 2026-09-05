import 'package:inferno/inferno.dart';
import 'package:test/test.dart';

/// The version-2 timing contract (docs/architecture/inferno.md), asserted the
/// same way against every engine so the two cannot drift apart again. Relations
/// only — an absolute bound would be a statement about the host.
void expectHonestTiming(InfernoMetrics metrics) {
  expect(
    metrics.timingSemanticsVersion,
    InfernoMetrics.currentTimingSemanticsVersion,
  );
  expect(metrics.generatedTokenCount, greaterThan(0));
  expect(metrics.promptTokenCount, greaterThan(0));
  expect(metrics.promptTokensPerSecond, greaterThan(0));
  final ttft = metrics.timeToFirstTokenSeconds;
  expect(
    ttft,
    isNotNull,
    reason: 'a token was produced, so a first one exists',
  );
  // Worker dispatch, tokenization, allocation and prefill all precede it.
  expect(ttft, greaterThan(0));
  expect(ttft, lessThanOrEqualTo(metrics.elapsedSeconds));
  // Prompt evaluation is inside the first-token window, so the window the
  // prompt rate describes cannot outlast it. A millisecond of slack: MLX's
  // prompt time is the library's wall clock against the shim's monotonic
  // one, and the anchor this guards against was off by the whole prefill.
  expect(
    ttft,
    greaterThanOrEqualTo(
      metrics.promptTokenCount! / metrics.promptTokensPerSecond - 1e-3,
    ),
  );
  // The decode rate is recomputable from the published numbers, down to a
  // one-token reply, whose window is the single step that ended it.
  expect(
    metrics.decodeTokensPerSecond,
    closeTo(
      metrics.generatedTokenCount / (metrics.elapsedSeconds - ttft!),
      1e-6,
    ),
  );
}

/// The observation contract (ABI 6): timing batches are contiguous — each
/// starts where the previous ended — carry non-decreasing instants measured
/// from the request's acceptance, and together count every observation the
/// engine reported. [count] is what the metrics say was produced when the
/// observations are tokens; a chunk series has no count to match.
void expectContiguousObservations(
  Iterable<InfernoTokenTimingEvent> batches, {
  required InfernoObservationKind kind,
  int? count,
  required double elapsedSeconds,
}) {
  var next = 0;
  double last = 0;
  for (final batch in batches) {
    expect(batch.kind, kind);
    expect(batch.firstIndex, next, reason: 'batches are contiguous');
    expect(batch.timesMs, isNotEmpty);
    for (final time in batch.timesMs) {
      expect(
        time,
        greaterThanOrEqualTo(last),
        reason: 'instants never go back',
      );
      // A hair of slack: the elapsed clock stops at the loop's end, after the
      // last instant, and both are the same monotonic clock.
      expect(time, lessThanOrEqualTo(elapsedSeconds * 1000 + 1));
      last = time;
    }
    next += batch.timesMs.length;
  }
  if (count != null) expect(next, count, reason: 'one instant per token');
}
