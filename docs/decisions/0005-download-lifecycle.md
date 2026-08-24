# Reconciling downloads with the OS, and who decides what restarts

Status: decided on `chore/65-download-reconciliation` (issue #65)

Background downloads outlive the app process. The plugin's native halves —
`URLSession` on iOS, `DownloadWorker` on Android — keep moving bytes after the
Dart isolate is gone, and the app has no memory of what it started. Everything
below is about who is allowed to believe what, and who is allowed to start a
transfer.

## The rules, stated once

- **Identity travels in `Task.metaData` and a dedicated `golem-models` group,
  never in the task id.** The id stays plugin-random and unique per generation.
- **`ModelState` plus the files on disk plus the SHA-256 receipt remain the
  verdict.** Everything the plugin reports is a hint used to *choose an
  action*, never to declare an artifact installed.
- **The app decides what restarts.** `doRescheduleKilledTasks` stays false, and
  the plugin's database is never auto-cleaned.
- **A transfer the platform is still running is adopted, never duplicated.**
  Only after a cancel is confirmed may a fresh one be enqueued.
- **Silence is not a verdict.** A stalled stream triggers a probe; only a probe
  that proves the platform holds nothing turns into an actionable state.

## Why identity is not the task id

A deterministic task id derived from the artifact is the obvious reconciliation
key. It is the wrong one, and each reason is in the plugin's own native source:

- Android enqueues with `workManager.enqueue`, not `enqueueUniqueWork`
  (`BDPlugin.kt`), and iOS creates its `URLSession` task unconditionally
  (`BDPlugin.swift`). Reusing an id makes a duplicate *detectable*, never
  *impossible*.
- `doEnqueue` clears the id's pending cancel flag, so enqueueing a fresh
  transfer under a reused id **un-cancels** the dying one — two writers on one
  file.
- Cancel is `cancelAllWorkByTag("taskId=…")`, so a cancel issued for one
  generation kills its successor.
- `Task ==` compares ids alone, so a stale terminal update passes the stream's
  own filter and tears down a healthy download.

A per-file key derived from the catalog entry's revision is wrong here for a
second reason: `ModelArtifactFile` carries per-file `repository` and `revision`
overrides, and pinned entries use them — `gemma4-gguf`'s projector comes from a
different repository at a different commit. The identity is therefore the
**resolved** `resolve/<revision>/` URL plus the destination path, which is
correct for overridden and inherited files alike.

## Why the app owns restart decisions

`FileDownloader.start()` offers `rescheduleKilledTasks`, which re-enqueues every
tracked task the native queue has lost. It is the wrong default for this app:
the repository sequences files one at a time, preflights disk space, verifies
each file's SHA-256, and writes a receipt. A task re-enqueued underneath it is a
writer nothing sequenced and no hash gate governs — precisely the second writer
issue #65 forbids. Tracking and background replay are enabled; automatic
rescheduling is not.

`autoCleanDatabase` is off for a smaller reason: its defaults drop records older
than ten days, and a paused multi-gigabyte download is exactly the thing a user
returns to after two weeks.

## What this decision does not change

Trust and integrity policy is untouched. Every file is still verified by
SHA-256 where the publisher pinned one, still receipted per revision, and still
installed only once the whole artifact has arrived. Adoption skips the network,
never the proof: an adopted or already-complete transfer is still checked for
exact length and still hashed before it counts as installed. Nothing here
weakens `docs/architecture/inferno.md`'s pinning discipline or the
`.golem-verified.json` receipt.

## Consequences

- The seam is identity-aware (`ArtifactFileRef`) and answers about the platform
  (`inspect`), so pause, cancel and delete work after a process recreation
  instead of silently no-opping and then deleting a directory a live transfer is
  still writing into.
- Reconciliation runs at startup and on every foreground return, so a card
  reflects the OS rather than the app's last memory of it.
- Two partial-file leaks close: Settings' Clear cache no longer deletes live
  transfer data staged in the cache directory, and orphaned staging files are
  swept once resume data has been restored.
- Evidence for backgrounding, screen lock and process recreation is
  hand-driven — see `../notes/download-lifecycle.md`. No test process can
  produce it, and that is a property of the platforms, not a gap to close later.
