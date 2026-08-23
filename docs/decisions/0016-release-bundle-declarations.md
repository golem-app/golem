# What the 1.0 bundle declares, and what it keeps off the phone's backups

Status: decided on `chore/154-pre-1-0-technical-audit` (issue #154)

Four facts about the shipped binary were either unstated or stated wrongly
before submission. Each is a file in the bundle or a flag on the container,
not a console form — the store forms (#22, #24) are written against these.

## The privacy manifest names one API, with two reasons

`ios/Runner/PrivacyInfo.xcprivacy` declares no tracking, no collected data,
and one required-reason category, `NSPrivacyAccessedAPICategoryDiskSpace`,
because `AppDelegate.swift` reads the volume's capacity over the storage
channel. Two reasons cover both uses: `85F4.1` — the figure is shown to the
user on the Storage screen and the drawer meter — and `E174.1` — the download
preflight refuses a transfer that would not fit. Every plugin ships its own
manifest; Flutter's engine covers the file-timestamp reads Dart performs.
`os_proc_available_memory` is not a required-reason API and stays undeclared.
macOS has no such rule and gets no manifest; its distribution is #14.

## Export compliance is exempt, and the bundle says so

`ITSAppUsesNonExemptEncryption` is `false`. Golem's cryptography is the OS's
own HTTPS to Hugging Face and SHA-256 integrity hashing of downloaded files.
Hashing is not encryption, `swift-crypto` in the MLX carrier is a transitive
dependency of `swift-transformers` used for digests, and nothing the app
ships encrypts data at rest or in transit on its own. Declaring it spares
every TestFlight upload the export-compliance prompt; a future dependency
that adds proprietary encryption reverses this decision, not the key alone.

## The iOS floor is 17.0, the engine's own

ADR 0012 made MLX the iOS engine. The MLX carrier declares iOS 17, and it is
not linked at launch but `dlopen`ed by the first native call — the launch
probe — so with the old 15.0 floor an iPhone on iOS 15 or 16 would install,
launch, and die at that call with an error nothing catches. The floor is now
the carrier's: `IPHONEOS_DEPLOYMENT_TARGET = 17.0` in every configuration.
Every A12-or-later iPhone, the store gate from ADR 0007, runs iOS 17, so the
two describe the same phones. Apple allows requirements to expand in an update
and never to contract, so 17 is the value to be right about first.

## Nothing Golem stores leaves the phone — backups included

ADR 0004 kept attachments in platform backups on the argument that a photo,
unlike a model, is not re-fetchable. That argument was sound and the outcome
was not: chats, preferences and pictures rode into iCloud and Google backups
while the first-run copy promised "no copy of your conversations anywhere
else", and on Android the 25 MB Auto Backup quota meant a handful of
attached PNGs silently stopped the chats from backing up at all.

The decision is the strict one. Every store is excluded:

- **iOS and macOS:** launch composition marks the application-support and
  documents roots `NSURLIsExcludedFromBackupKey` through the storage channel
  on every launch (`keepOutOfBackups`). A directory's flag covers its
  contents, so every store — chats, attachments, both preference files, model
  state, weights — is covered at once; the per-download exclusion of
  `models/` stays as belt and braces.
- **Android:** `android:allowBackup="false"` for cloud backup, plus
  `dataExtractionRules` excluding every domain from both `<cloud-backup>`
  and `<device-transfer>`, because on some manufacturers' devices the switch
  alone leaves device-to-device transfer running. The pre-12
  `fullBackupContent` file is gone; `allowBackup` covers that regime.

What this costs: a new phone does not carry chats over. Settings ▸ Privacy &
data ▸ Export every chat is the migration path, and the Privacy screen's
statement says so. What it buys: the app's claim that nothing leaves the
device is literally true, and #22's data-safety answers can say "not
collected, not shared, not backed up" without a footnote.

This supersedes ADR 0004's section "Attachments are app-owned, and not
excluded from backup" in its backup half only; the app-owned store, opaque
ids, and `retainOnly` collection stand.
