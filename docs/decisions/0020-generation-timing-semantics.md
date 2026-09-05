# Generation timing semantics, versioned

Status: decided on `fix/57-honest-ttft` (issue #57)

## Context

Both shims reported a field called `timeToFirstTokenSeconds` that was not a
time to first token. llama.cpp measured from the end of prefill to the first
sampled token; the MLX shim reconstructed the same window by subtracting its
library-reported prompt time from the wall clock, which is why every recorded
MLX row under `docs/evals/` reads 0.000–0.002 s. Prefill is the part of the
wait a user feels on a long prompt, and both numbers excluded it. The elapsed
clocks were uneven in the same way, and ADR 0002's footnote ² described that
state as the aligned one.

The numbers are already on disk. Every assistant turn in a chat history
carries an `InferenceMetrics`, and five reports under `docs/evals/` quote a
`ttft s` column. Correcting the measurement without saying which contract
produced a number would relabel those old values as corrected ones — the same
dishonesty, one layer down.

## Decision

The contract is **version 2**, defined once in
`docs/architecture/inferno.md` and carried with the numbers:

- `timeToFirstTokenSeconds` — native request acceptance → first output token.
  Worker dispatch, request parsing, tokenization, allocation and prefill are
  inside the window. Null when no token was produced.
- `elapsedSeconds` — request acceptance → end of the generation loop.
- `decodeTokensPerSecond` — `(tokens − 1)` over the inter-token intervals
  after the first token, on both engines. A one-token reply has no interval
  and reports no rate; the model-speed label skips such a turn rather than
  quote a zero.

Every metrics record states its contract in `timingSemanticsVersion`, carried
from the shim payload (`INFERNO_ABI_VERSION` 5, `INFERNO_TIMING_SEMANTICS_VERSION`
2) through `InfernoMetrics`, `BrokerRuntimeMetrics`, the `INFERNO_METRICS`
line, `InferenceMetrics`, the persisted chat history, and both evaluation
report formats. It is an `int`, not an enum: a value a newer build writes must
round-trip through an older one unchanged rather than degrade to "unknown".

**Version 1 is what shipped before this record** — the post-prefill delay
above. A persisted metrics object with no `timingSemanticsVersion` key is read
as version 1 and re-saved as version 1. Nothing relabels a legacy number, and
the chat history stays at schema version 3: the key is additive with a defined
default, per the store's own convention, and a bump would make an older build
quarantine a history it can still read.

An evaluation report derives its version from the rows it holds and refuses to
render when they disagree. One `ttft s` column cannot honestly hold a
post-prefill delay and a time to first token at once.

## Consequences

- Version 1 and version 2 timings are not comparable in either direction. The
  five historical reports and ADR 0002 say so above their tables; their
  numbers stay verbatim, because a generated artefact is evidence of what was
  measured, not of what it should have been called.
- A version-2 time to first token is larger than the version-1 number for the
  same generation by roughly the prefill. A regression against a pre-#57
  baseline is a units change until proven otherwise.
- Decode rates move by about a percent in opposite directions: llama.cpp's old
  window included the first token's step, MLX counted every token over the
  steps after the first. Both now report the same reciprocal inter-token
  latency.
- The next contract change is version 3, in the same three places: the shims,
  this record, and the report preamble.
- No UI shows a latency, before or after. This is a measurement channel.
