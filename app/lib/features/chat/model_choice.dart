/// What the per-chat model picker offers, and why (#79).
///
/// Which model a chat *runs* belongs to `core/domain/model_activation.dart` and
/// how it is *worded* to `model_label.dart`; this file decides what a user is
/// shown before they choose. It is pure so the whole of that decision — the
/// recommendation and its reason, every disabled row's explanation, and every
/// download affordance — is provable without a widget.
///
/// Two rules hold every branch together, and both are load-bearing:
///
/// - **No row may be blocked without copy.** [ModelChoice] asserts it, so a new
///   refusal cannot be added without a sentence explaining it.
/// - **Nothing is claimed that was not measured or proven.** Speed appears only
///   where a generation recorded it, image input only where the artifact's own
///   modalities carry the #18 proof, and the recommendation's reason only where
///   a real device was actually classified.
library;

import '../../core/domain/byte_format.dart';
import '../../core/domain/device_eligibility.dart';
import '../../core/domain/inference_backend.dart';
import '../../core/domain/model_activation.dart';
import '../../core/domain/model_admission.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/domain/model_speed.dart';
import '../../core/domain/models.dart';

/// A download affordance a picker row may offer. Absent (`null` on the choice)
/// when the artifact is installed, or when the device is refused and the
/// affordance is *withheld* rather than dimmed (ADR 0007).
sealed class ModelTransfer {
  const ModelTransfer();
}

/// A transfer this row can start: a first download, a resume, or a retry.
final class ModelTransferOffer extends ModelTransfer {
  const ModelTransferOffer({
    required this.label,
    required this.enabled,
    this.note,
  });

  /// `Download · 1.58 GB`, `Resume`, or `Retry`.
  final String label;

  /// False while another artifact holds the one transfer slot; [note] says so.
  final bool enabled;

  /// Why the offer is disabled, or what went wrong on the attempt before it.
  final String? note;
}

/// A transfer already running, described for a progress bar.
final class ModelTransferProgress extends ModelTransfer {
  const ModelTransferProgress({
    required this.fraction,
    required this.label,
    required this.pausable,
  });

  /// 0–1, derived from the catalog total; the repository never stores a stale
  /// percentage (`ArtifactStatus.downloadedBytes`).
  final double fraction;
  final String label;

  /// Verification cannot be interrupted; a download can.
  final bool pausable;
}

/// Why a row cannot be chosen. Carried alongside the copy rather than instead
/// of it: the enum is for tests and keys, the sentence is for the user.
enum ModelBlock {
  /// Not on this device yet.
  notInstalled,

  /// Installed, but the engine this build composed cannot load its format.
  otherEngine,

  /// Installed, but no chat template this build knows matches it (#43).
  unrecognizedTemplate,

  /// This device is admitted to no model at all (#27).
  deviceRefused,

  /// Admitted, but not to this artifact: the launch classification sized this
  /// build for a lighter one, and first run refuses it for the same reason.
  needsMoreMemory,

  /// The build pins an operator-supplied file, so there is nothing to switch to.
  sideload,

  /// A hand-added repository whose file list was never resolved (#52).
  unresolvedRepository,
}

/// One row of the picker: everything shown, nothing computed by the widget.
final class ModelChoice {
  ModelChoice({
    required this.entry,
    required this.title,
    required this.detail,
    required this.selected,
    required this.selectable,
    this.needsConsent = false,
    this.summary,
    this.artifactLine,
    this.recommendation,
    this.block,
    this.blockReason,
    this.transfer,
  }) : assert(
         selectable == (blockReason == null),
         'a row a user cannot choose owes them a reason (#79)',
       ),
       assert(
         (block == null) == (blockReason == null),
         'a block and its copy travel together',
       );

  final ModelCatalogEntry entry;

  /// The family and its size. Carries the engine only when another visible row
  /// shares the name, which is the one case where the name alone is ambiguous.
  final String title;

  /// Size, proven capability, and measured speed — `1.58 GB · reads pictures`.
  final String detail;

  /// What the model is *for*, in a user's words; null for a hand-added
  /// repository, which nobody has characterized.
  final String? summary;

  /// `GGUF · Q4_0 · unsloth/…`. Non-null only under Advanced mode: the exact
  /// artifact stays discoverable for operators without leading with it
  /// (docs/decisions/0008-model-presentation.md).
  final String? artifactLine;

  /// Why this is the model the build would pick. Non-null on exactly one row,
  /// and only where something actually picked it.
  final String? recommendation;

  /// Whether starting this row's transfer is a *fresh* multi-gigabyte fetch,
  /// which every entrance in the app gates behind explicit consent (#26). A
  /// resume or a retry continues one the user already approved.
  final bool needsConsent;

  final bool selected;
  final bool selectable;
  final ModelBlock? block;
  final String? blockReason;
  final ModelTransfer? transfer;
}

/// The whole sheet: its rows, and an honest account of what is not among them.
final class ModelPickerView {
  const ModelPickerView({
    required this.choices,
    required this.hiddenCount,
    this.hiddenNote,
    this.footnote,
  });

  final List<ModelChoice> choices;

  /// Catalog entries left out because this build's engine could never load them
  /// and they are not on disk — dead multi-gigabyte options (#63).
  final int hiddenCount;

  /// Why those are absent. Non-null exactly when [hiddenCount] is positive, so
  /// absence is never silent.
  final String? hiddenNote;

  /// What choosing does, or why it cannot be done here.
  final String? footnote;
}

/// Builds the picker's rows from the state the app already owns.
///
/// [deviceRefusal] is `deviceRefusalProvider`'s answer, passed in rather than
/// re-derived from [eligibility]: the refusal rule — including that a simulated
/// backend is never gated — has one owner, and this is not it. [eligibility] is
/// read only for the tier that explains the recommendation.
ModelPickerView buildModelPickerView({
  required List<ModelCatalogEntry> catalog,

  /// Admission is a policy about the artifacts this project ships and has
  /// weighed. A hand-added repository has a synthesized size and no tier the
  /// rule could judge, so it is not put to it — first run only ever asked
  /// about pinned entries either.
  required List<ModelCatalogEntry> pinnedCatalog,
  required Set<String> downloadableKeys,
  required InferenceBackendConfig backend,
  required ModelState? models,
  required Set<String> loadableKeys,
  required List<ChatConversation> conversations,
  required DeviceEligibility eligibility,
  required String? deviceRefusal,
  required bool advanced,
  required bool simulatedTransfers,
  String? selectedKey,
}) {
  final simulated = backend.simulatedInference;

  // Installed artifacts stay visible even when this build cannot load them,
  // exactly as the Settings catalog keeps them (#63): a model a user installed
  // and then cannot find is the absence #79 exists to explain. What is neither
  // loadable nor installed is a dead multi-gigabyte option, and is counted
  // instead of listed.
  final usable = <ModelCatalogEntry>[];
  final foreign = <ModelCatalogEntry>[];
  var hidden = 0;
  for (final entry in catalog) {
    final installed =
        models?.statusOf(entry.key).phase == ArtifactPhase.installed;
    if (simulated || backend.kind.loads(entry.engine)) {
      usable.add(entry);
    } else if (installed) {
      foreign.add(entry);
    } else {
      hidden += 1;
    }
  }
  // Catalog order within each group, but everything this build could actually
  // run comes first: an artifact kept only to explain itself must not be the
  // first thing a user reads.
  final visible = [...usable, ...foreign];

  // One pass over the history for the whole sheet rather than one per row:
  // measuredTokensPerSecond walks every conversation and every message, and
  // this widget rebuilds on each download-progress snapshot.
  final speeds = measuredTokensPerSecondByModel(
    conversations,
    defaultModelKey: defaultMeasuredModelKey(backend, models),
  );

  final duplicated = <String>{};
  final seen = <String>{};
  for (final entry in visible) {
    if (!seen.add(entry.displayName)) duplicated.add(entry.displayName);
  }

  // Admission is asked, not restated: the same policy first run consults
  // decides which artifacts this device may have and which one it recommends,
  // so the two surfaces cannot reach opposite verdicts on one phone (#26/#79).
  final admission = {
    for (final option in modelAdmissionOptions(
      catalog: pinnedCatalog,
      backend: backend,
      eligibility: eligibility,
    ))
      option.entry.key: option,
  };

  // A sideload recommends nothing: the policy still derives an artifactKey,
  // but the build loads a pinned file instead, and badging a catalog row would
  // name an artifact it never touches.
  final recommendedKey = deviceRefusal != null || backend.sideloaded
      ? null
      : admission.values
                .where((option) => option.recommended)
                .firstOrNull
                ?.entry
                .key ??
            models?.activeArtifactKey;
  final recommendation = _recommendationReason(
    simulated: simulated,
    tier: eligibility.tier,
    memoryKnown: eligibility.memoryKnown,
    fromDevicePolicy:
        backend.artifactFromDevicePolicy &&
        recommendedKey == backend.artifactKey,
  );

  // Over the visible rows, not the catalog: a transfer on a row this sheet
  // does not list would otherwise withhold every Download button on screen and
  // blame a model the user cannot see.
  final transferring = models == null ? null : _keyInFlight(models, visible);

  final choices = [
    for (final entry in visible)
      _choiceFor(
        entry: entry,
        backend: backend,
        models: models,
        loadableKeys: loadableKeys,
        speeds: speeds,
        deviceRefusal: deviceRefusal,
        advanced: advanced,
        selectedKey: selectedKey,
        ambiguousName: duplicated.contains(entry.displayName),
        recommendation: entry.key == recommendedKey ? recommendation : null,
        transferringKey: transferring,
        simulatedTransfers: simulatedTransfers,
        admission: admission[entry.key],
        downloadable: downloadableKeys.contains(entry.key),
      ),
  ];

  return ModelPickerView(
    choices: choices,
    hiddenCount: hidden,
    hiddenNote: hidden == 0
        ? null
        : '$hidden other '
              '${hidden == 1 ? 'model is' : 'models are'} built for a '
              'different engine and ${hidden == 1 ? 'is' : 'are'} not listed. '
              'This build runs ${engineName(_composedEngine(backend))}.',
    footnote: _footnote(backend: backend, deviceRefusal: deviceRefusal),
  );
}

ModelChoice _choiceFor({
  required ModelCatalogEntry entry,
  required InferenceBackendConfig backend,
  required ModelState? models,
  required Set<String> loadableKeys,
  required String? deviceRefusal,
  required bool advanced,
  required String? selectedKey,
  required bool ambiguousName,
  required String? recommendation,
  required String? transferringKey,
  required bool simulatedTransfers,
  required ModelAdmissionOption? admission,
  required Map<String, double> speeds,
  required bool downloadable,
}) {
  final simulated = backend.simulatedInference;
  final status = models?.statusOf(entry.key) ?? const ArtifactStatus();
  final installed = status.phase == ArtifactPhase.installed;
  final loadsHere = backend.kind.loads(entry.engine);

  // The existing selection rule, unchanged: the fake honors any choice, a real
  // engine only one it could load, and a sideload none at all (#20). Widening
  // it here would let a label name weights the next send would refuse.
  //
  // The device verdict is checked first and separately. `loadableKeys` asks
  // whether an artifact is installed and of the right engine — questions that
  // still answer yes on a device admitted to nothing, which is reachable when a
  // release tightens the floor under models a user already downloaded. Without
  // this, such a row stayed selectable and unexplained beside a footnote saying
  // the device cannot run models (#27, #79).
  // Admission gates *acquiring* a model, not choosing one already on disk. A
  // light-tier device is not invited to download the larger artifact — first
  // run refuses it for the same reason — but an artifact already installed
  // stays selectable, because stranding weights a user already has helps
  // nobody and the #62 load preflight is the guard at the moment of load.
  final selectable =
      deviceRefusal == null &&
      (simulated || (!backend.sideloaded && loadableKeys.contains(entry.key)));

  final (ModelBlock?, String?) blocked = switch (selectable) {
    true => (null, null),
    // Both of these refuse the whole sheet rather than this row, so the row
    // says only that it is refused and the footnote — printed once — carries
    // the explanation. Six copies of one sentence explains nothing twice.
    //
    // The device verdict outranks the sideload: under both, nothing will load
    // for either reason, and "this device cannot run models" is the one a user
    // can do nothing about.
    false when deviceRefusal != null => (
      ModelBlock.deviceRefused,
      'Not available on this device.',
    ),
    false when backend.sideloaded => (
      ModelBlock.sideload,
      'Pinned by this build.',
    ),
    // Not installed, and this device was sized against it: first run refuses
    // the same artifact for the same reason, in the same words.
    false
        when !installed &&
            admission?.block == ModelAdmissionBlock.needsPreferredTier =>
      (ModelBlock.needsMoreMemory, admission!.disabledReason!),
    // Nothing can be fetched for a repository that never resolved, so the row
    // must not tell the user to download it. Settings says the same.
    false when !installed && !downloadable => (
      ModelBlock.unresolvedRepository,
      'This repository has not been resolved against Hugging Face, so its '
          'files are unknown. Add it again in Settings to resolve it.',
    ),
    false when installed && !loadsHere => (
      ModelBlock.otherEngine,
      // Plural deliberately: "a MLX" and "an MLX" are both wrong depending on
      // how the reader says it, and no copy is worth an article rule.
      'Installed, but this build runs ${engineName(_composedEngine(backend))} '
          'and cannot load ${engineFormat(entry.engine)} models.',
    ),
    false when installed && entry.profileKey == unresolvedProfileKey => (
      ModelBlock.unrecognizedTemplate,
      'Installed, but Golem does not recognize this model’s chat template, so '
          'it cannot prompt it.',
    ),
    // "Not installed" covers a transfer that has not started, one running, and
    // one stopped part-way. Telling a user to download a model they already
    // have 62% of reads as a bug, so the sentence follows the phase.
    false => (
      ModelBlock.notInstalled,
      switch (status.phase) {
        ArtifactPhase.downloading ||
        ArtifactPhase.verifying => 'Pick it once the download finishes.',
        ArtifactPhase.paused => 'Resume the download to use it in this chat.',
        ArtifactPhase.failed =>
          'The download did not finish, so it cannot be picked yet.',
        _ => 'Download it to use it in this chat.',
      },
    ),
  };

  return ModelChoice(
    entry: entry,
    title: ambiguousName
        ? '${entry.displayName} · ${engineFormat(entry.engine)}'
        : entry.displayName,
    detail: _detailLine(
      entry: entry,
      measured: speeds[entry.key],
      simulated: simulated,
    ),
    // Every pinned entry carries copy by construction, so a missing summary
    // means a hand-added repository — which nobody has characterized and this
    // project will not characterize on its behalf.
    summary: entry.summary ?? 'Added by you from Hugging Face.',
    artifactLine: advanced
        ? '${engineFormat(entry.engine)} · ${entry.quantization} · '
              '${entry.repository}'
        : null,
    recommendation: recommendation,
    // The tick marks the chat's model, and only a model that can run is one.
    // `effectiveModelKey` falls back to the artifact the build *would* load,
    // which on a fresh install is not downloaded — ticking that row while it
    // reads "Download it to use it in this chat" is the kind of contradiction
    // this ticket exists to remove. The RECOMMENDED badge still points at it.
    selected: selectable && entry.key == selectedKey,
    selectable: selectable,
    needsConsent: status.phase == ArtifactPhase.notDownloaded,
    block: blocked.$1,
    blockReason: blocked.$2,
    transfer: _transferFor(
      entry: entry,
      status: status,
      deviceRefusal: deviceRefusal,
      loadsHere: loadsHere,
      simulated: simulated,
      sideloaded: backend.sideloaded,
      transferringKey: transferringKey,
      simulatedTransfers: simulatedTransfers,
      downloadable: downloadable,
      admitted: admission?.enabled ?? true,
    ),
  );
}

/// The row's download affordance, or null when there is nothing to offer.
///
/// Withheld outright — not disabled — on a refused device and under a sideload,
/// because a full-width button that does nothing when tapped undoes the honesty
/// the copy beside it provides (ADR 0007).
ModelTransfer? _transferFor({
  required ModelCatalogEntry entry,
  required ArtifactStatus status,
  required String? deviceRefusal,
  required bool loadsHere,
  required bool simulated,
  required bool sideloaded,
  required String? transferringKey,
  required bool simulatedTransfers,
  required bool downloadable,
  required bool admitted,
}) {
  if (deviceRefusal != null || sideloaded) return null;
  // Nothing is offered for an artifact this device is not admitted to: the
  // shared policy already refused it on the first-run screen.
  if (!admitted) return null;
  // A hand-added repository that never resolved has synthesized files and no
  // real byte count, so the request could not succeed; Settings withholds its
  // button for the same reason rather than failing on the tap.
  if (!downloadable) return null;
  // Nothing is offered for an artifact this build could never run, even when a
  // previous build installed it. Its row explains itself and stops there.
  if (!loadsHere && !simulated) return null;
  final busyElsewhere = transferringKey != null && transferringKey != entry.key;
  // The same qualifier Settings appends to every transfer phase: a simulated
  // download must never read like a real one, and the two surfaces describe one
  // repository.
  final suffix = simulatedTransfers ? ' · simulated' : '';
  return switch (status.phase) {
    ArtifactPhase.installed => null,
    ArtifactPhase.downloading => ModelTransferProgress(
      fraction: _fraction(status.downloadedBytes, entry.totalBytes),
      label: 'Downloading$suffix',
      pausable: true,
    ),
    ArtifactPhase.verifying => ModelTransferProgress(
      fraction: 1,
      label: 'Verifying files$suffix',
      pausable: false,
    ),
    ArtifactPhase.paused => ModelTransferOffer(
      label: 'Resume',
      enabled: !busyElsewhere,
      note: busyElsewhere
          ? _busyNote
          : 'Paused at ${gigabytes(status.downloadedBytes)} '
                'of ${gigabytes(entry.totalBytes)}$suffix.',
    ),
    ArtifactPhase.failed => ModelTransferOffer(
      label: 'Retry',
      enabled: !busyElsewhere,
      note: busyElsewhere ? _busyNote : status.failure ?? 'Download failed.',
    ),
    ArtifactPhase.notDownloaded => ModelTransferOffer(
      label: 'Download · ${gigabytes(entry.totalBytes)}$suffix',
      enabled: !busyElsewhere,
      note: busyElsewhere ? _busyNote : null,
    ),
  };
}

const _busyNote = 'Another model is downloading.';

/// Size first, because it is the cost; then capability, which is proven per
/// artifact (#18); then speed, only where a generation measured it — the fake's
/// canned rate is labeled as such and never claimed of a phone.
String _detailLine({
  required ModelCatalogEntry entry,
  required double? measured,
  required bool simulated,
}) {
  return [
    gigabytes(entry.totalBytes),
    if (entry.supportsImages) 'reads pictures',
    if (measured != null)
      '${measured.toStringAsFixed(1)} tok/s '
          '${simulated ? 'simulated' : 'on this phone'}',
  ].join(' · ');
}

/// Why the recommended row is the recommended one.
///
/// A simulated build claims nothing about hardware: it never probed any. The
/// tier sentences are the user-facing half of the classification recorded in
/// `docs/decisions/0007-supported-device-policy.md`.
String _recommendationReason({
  required bool simulated,
  required DeviceTier tier,
  required bool memoryKnown,
  required bool fromDevicePolicy,
}) {
  if (simulated) return 'This build’s default model.';
  // An explicit GOLEM_MODEL_ARTIFACT or GOLEM_MODEL_PROFILE fixes the artifact
  // and the tier is never read (backend_policy.dart), so a memory sentence
  // there would credit a classification that played no part. The build says
  // which case it is rather than the copy guessing from a key prefix.
  if (!fromDevicePolicy) return 'This build’s default model.';
  // The light tier is also where an unreadable probe lands (ADR 0007: unknown
  // is not a refusal), and absence of evidence is not a low reading.
  if (!memoryKnown) {
    return 'The lighter model, picked because this phone’s memory could '
        'not be read.';
  }
  return switch (tier) {
    DeviceTier.preferred => 'This phone has the memory for the larger model.',
    DeviceTier.light => 'Sized to fit this phone’s memory.',
    // Unreachable while a refusal suppresses the badge; stated rather than
    // asserted so a future caller cannot get a blank reason.
    DeviceTier.unsupported => 'This build’s default model.',
  };
}

String? _footnote({
  required InferenceBackendConfig backend,
  required String? deviceRefusal,
}) {
  if (backend.simulatedInference) return null;
  if (deviceRefusal != null) return deviceRefusal;
  if (backend.sideloaded) {
    return 'This build runs ${sideloadedModelLabel(backend.modelPath!)} from a '
        'path it pins, so this chat cannot switch models.';
  }
  return 'The model you pick loads with your next message.';
}

/// Which artifact holds the single transfer slot, mirroring the Settings rule
/// that one download runs at a time (`models_screen.dart`).
String? _keyInFlight(ModelState models, List<ModelCatalogEntry> catalog) {
  for (final entry in catalog) {
    final phase = models.statusOf(entry.key).phase;
    if (phase == ArtifactPhase.downloading ||
        phase == ArtifactPhase.verifying) {
      return entry.key;
    }
  }
  return null;
}

/// The engine a real build composed. The fake loads every format, so it has no
/// single engine to name — callers only reach this on the real paths.
ModelEngine _composedEngine(InferenceBackendConfig backend) =>
    backend.kind.loads(ModelEngine.gguf) ? ModelEngine.gguf : ModelEngine.mlx;

double _fraction(int downloaded, int total) =>
    total <= 0 ? 0 : (downloaded / total).clamp(0, 1).toDouble();
