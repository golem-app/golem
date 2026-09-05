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
