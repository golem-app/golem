# No splash wait: the shell is the first frame

Status: decided on `fix/159-no-splash-wait` (issue #159)

## Context

After the launch composition succeeded, a startup theatre took over the
splash frame: a progress track stepped `0.18 → 0.72 → 1.0` on timers behind a
1.4 s minimum hold, and two injected scenarios parked it at `0.42` and `0.86`.
None of it corresponded to work — on a fake build the real composition is
done in well under 200 ms, so the hold was effectively the whole splash. Real
readiness lived underneath, in the onboarding gate's store loads, which the
timer ignored; the hold merely masked that pane.

Readiness is two opaque stages (the composition, then the store loads or a
sideload `prepare()`) with no sub-progress and wildly varying duration. A
determinate bar over that is a stepper, not progress. Both platform owners
also reject a held launch: Apple's HIG says the launch screen must not delay
people from getting into the experience and is not a branding opportunity;
Android's splash guidance says to dismiss on the first frame, extend only
while real data loads, and never add artificial delays.

## Decision

- The first Flutter frame is deferred until the composition resolves
  (`WidgetsBinding.deferFirstFrame`). The native solid-navy launch screen stays
  up for exactly as long as the real work takes, and the shell is the first
  frame drawn. No hold, no ticks, no bar, no spinner on the launch path.
- The theatre is deleted: `StartupController`, `StartupSequence`,
  `StartupState`/`StartupPhase`, the `StartupGate` overlay, the `splash`
  feature, its goldens and l10n strings, and the three scenario defines.
  `GOLEM_LAUNCH_FAILURES=<n>` stays as the one launch fault injector, because
  it fails real compositions.
- The bootstrap pane (`LaunchPane`, in `app/lib/app/bootstrap.dart`) survives
  only for what needs a frame: a failed composition (classified copy, Try
  again) and a retry in flight (caption only). It keeps the `launch-splash`
  and `splash-retry` automation keys, so the journeys' "poll the splash away"
  loops still hold.
- The onboarding gate's waiting pane shows its activity indicator only after
  a wait has lasted a 400 ms grace. With no splash in front of it, an instant
  spinner would flash on every ordinary launch; a multi-second sideload
  validation still shows one.

## Consequences

An ordinary launch goes native launch screen → shell. A hang still resolves
at the 8 s composition deadline into the failure pane rather than the native
screen forever (ADR 0006). The former theatre's failure and missing-model
demos are gone; the failure pane is demonstrated with real injected failures.
