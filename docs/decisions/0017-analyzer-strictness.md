# Strict analyzer modes for the app, and which lints came with them

Status: decided on `chore/154-pre-1-0-technical-audit` (issue #154)

`app/analysis_options.yaml` was the stock `flutter_lints` template while the
app hand-parses four versioned JSON stores, every one of them through the
`dynamic` that `jsonDecode` returns. Handbook v5.0 books the strict modes as
an open decision (§1.2, §5.1, §16.3) and makes enabling them an ADR trigger
(§0.6); this is that record.

## Decision

`strict-casts` and `strict-raw-types` are on. Measured on `main` @ `67cfb8b`
with the #154 branch applied, both modes report nothing: every store already
casts explicitly through a `fromJson` factory, so the modes cost no code and
guard what is there. Generated Dart stays analyzed: a `.g.dart` is a part of a
hand-written library, and excluding it would hide a stale part's hard errors
from the one analyzer gate the repository runs (review of PR #155 proved an
excluded part with a type error analyzes clean). Its lints carry their own
pragmas, so nothing is lost by keeping it in.

Two of the five lints `packages/inferno` runs joined the app:

- `unawaited_futures` — a `Future` discarded in a statement is the
  fire-and-forget #154 found leaving a Models row on `loading`. Seven sites
  were deliberate and now say so with `unawaited(...)`.
- `avoid_dynamic_calls` — the runtime half of `strict-casts`; zero sites.

Three were declined, with the counts that decided it:

- `discarded_futures` — 34 sites, all `onPressed: () => controller.x()`
  arrow callbacks where a discarded `Future` is the idiom, not a defect.
  Wrapping each in `unawaited` would add ceremony and find nothing; the
  controller guards its own commands instead (#154's `toggleRuntime` fix).
- `cancel_subscriptions` — one site, the process-wide listener in
  `artifact_downloader.dart` that is static by documented design.
- `close_sinks` — one site, a test fake whose controller ends with the test.

`strict-inference` stays off: its value is in untyped generics the codebase
does not write, and it was not measured here.

## Consequences

`flutter analyze` is part of the gate, so an implicit downcast from `dynamic`
is now a build error rather than a runtime `TypeError` that the store loader
would quarantine. No `// ignore:` was added; a future lint that needs one is
a decision to record, not a pragma to add. Lints stay a per-package choice:
`packages/inferno` keeps its Dart-only set.
