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

- The first Flutter frame is deferred (`WidgetsBinding.deferFirstFrame`)
  until the composition resolves *and* the composed app has read its
  preferences, so the native solid-navy launch screen stays up for exactly as
  long as the real work takes and the shell — already in the stored theme,
  language and text size — is the first frame drawn. While deferred the
  bootstrap builds nothing but a navy box: no pane, no layout, no icon decode
  for a frame nobody sees. No hold, no ticks, no bar, no spinner.
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
- The onboarding gate's first wait — the store loads behind what used to be
  the splash — paints as the launch screen's navy and shows its activity
  indicator only after a 400 ms grace: with no splash in front of it, an
  instant spinner would flash on every ordinary launch, while a multi-second
  sideload validation still shows one. A wait that follows the user's own
  Try again sits on the ordinary canvas and answers at once.

## Consequences

An ordinary launch goes native launch screen → shell, with the gate's navy
wait covering whatever the store loads still owe. A hung required stage
still resolves at the 8 s composition deadline into the failure pane rather
than the native screen forever; the bounded 5 s downloader start that follows
it (ADR 0006) can only degrade, so the worst case is 13 s of navy and then the
shell — unchanged from before, when it was 13 s of a splash with the bar at
zero. The former theatre's failure and missing-model
demos are gone; the failure pane is demonstrated with real injected failures.
