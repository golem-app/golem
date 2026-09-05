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
  // prompt rate describes cannot outlast it. The rate is published rather
  // than the window, so the epsilon covers one divide and the JSON round
  // trip — nanoseconds against an inversion that would be milliseconds.
  expect(
    ttft,
    greaterThanOrEqualTo(
      metrics.promptTokenCount! / metrics.promptTokensPerSecond - 1e-6,
    ),
  );
  // The decode rate is recomputable from the published numbers.
  if (metrics.generatedTokenCount > 1) {
    expect(
      metrics.decodeTokensPerSecond,
      closeTo(
        (metrics.generatedTokenCount - 1) / (metrics.elapsedSeconds - ttft!),
        1e-6,
      ),
    );
  } else {
    expect(metrics.decodeTokensPerSecond, 0);
  }
}
