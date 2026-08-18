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
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/presentation_messages.dart';
import '../models/artifact_transfer.dart';

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
    required this.summary,
    this.artifactLine,
    this.recommendation,
    this.block,
    this.blockReason,
    this.transfer,
    this.transferLabel,
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

  /// What the model is *for*, in a user's words. Always present: a hand-added
  /// repository gets the sentence that says nobody characterized it, which is
  /// still copy the picker owes the row.
  final String summary;

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

  /// The shared projection for this row, or null where this sheet withholds
  /// the whole affordance rather than dimming it (ADR 0007).
  final ArtifactTransferPresentation? transfer;

  /// How this sheet words [transfer]: `Download · 1.58 GB`, `Resume`,
  /// `Downloading`. Settings words the same decision at greater length, which
  /// is why the projection carries the action and not the sentence.
  final String? transferLabel;
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
/// read only for the tier that explains the recommendation; the footnote words
/// [deviceRefusal] itself, so the two cannot disagree.
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
  required DeviceIneligibilityReason? deviceRefusal,
  required bool advanced,
  required bool simulatedTransfers,
  required AppLocalizations localizations,
  String? selectedKey,
}) {
  assert(
    pinnedCatalog.every((e) => catalog.any((c) => c.key == e.key)),
    'the pinned catalog is a subset of the rows; admission decides the '
    'recommendation, and one naming an entry that is not on screen would '
    'badge nothing',
  );
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
    localizations: localizations,
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
  // Over the whole catalog, not just the listed rows: the single-transfer rule
  // belongs to the repository, and a download this sheet happens not to show
  // still holds the slot. Offering a second would start a competing writer.
  final transferring = models == null ? null : _keyInFlight(models, catalog);

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
        localizations: localizations,
      ),
  ];

  return ModelPickerView(
    choices: choices,
    hiddenCount: hidden,
    hiddenNote: hidden == 0
        ? null
        : localizations.hiddenEngineModels(
            hidden,
            engineName(_composedEngine(backend)),
          ),
    footnote: _footnote(
      backend: backend,
      deviceRefusal: deviceRefusal,
      localizations: localizations,
    ),
  );
}

ModelChoice _choiceFor({
  required ModelCatalogEntry entry,
  required InferenceBackendConfig backend,
  required ModelState? models,
  required Set<String> loadableKeys,
  required DeviceIneligibilityReason? deviceRefusal,
  required bool advanced,
  required String? selectedKey,
  required bool ambiguousName,
  required String? recommendation,
  required String? transferringKey,
  required bool simulatedTransfers,
  required ModelAdmissionOption? admission,
  required Map<String, double> speeds,
  required bool downloadable,
  required AppLocalizations localizations,
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
      localizations.notAvailableOnDevice,
    ),
    false when backend.sideloaded => (
      ModelBlock.sideload,
      localizations.pinnedByBuild,
    ),
    // Not installed, and this device was sized against it: first run refuses
    // the same artifact for the same reason, in the same words.
    false
        when !installed &&
            admission?.block == ModelAdmissionBlock.needsPreferredTier =>
      (
        ModelBlock.needsMoreMemory,
        modelAdmissionReason(localizations, admission!),
      ),
    // Nothing can be fetched for a repository that never resolved, so the row
    // must not tell the user to download it. Settings says the same.
    false when !installed && !downloadable => (
      ModelBlock.unresolvedRepository,
      localizations.unresolvedRepositoryReason,
    ),
    false when installed && !loadsHere => (
      ModelBlock.otherEngine,
      // Plural deliberately: "a MLX" and "an MLX" are both wrong depending on
      // how the reader says it, and no copy is worth an article rule.
      localizations.installedOtherEngine(
        engineName(_composedEngine(backend)),
        engineFormat(entry.engine),
      ),
    ),
    false when installed && entry.profileKey == unresolvedProfileKey => (
      ModelBlock.unrecognizedTemplate,
      localizations.unrecognizedChatTemplate,
    ),
    // "Not installed" covers a transfer that has not started, one running, and
    // one stopped part-way. Telling a user to download a model they already
    // have 62% of reads as a bug, so the sentence follows the phase.
    false => (
      ModelBlock.notInstalled,
      switch (status.phase) {
        ArtifactPhase.downloading ||
        ArtifactPhase.verifying => localizations.pickAfterDownload,
        ArtifactPhase.paused => localizations.resumeForChat,
        ArtifactPhase.failed => localizations.unfinishedDownload,
        _ => localizations.downloadForChat,
      },
    ),
  };

  final suffix = simulatedTransfers ? ' · ${localizations.simulated}' : '';
  // Nothing is offered under either of these, so nothing is projected: the
  // sheet rebuilds on every download-progress snapshot, and a refused device
  // would otherwise pay for a full projection per row on every tick.
  final withheld = deviceRefusal != null || backend.sideloaded;
  final transfer = withheld
      ? null
      : _pickerTransfer(
          artifactTransfer(
            entry: entry,
            status: status,
            localizations: localizations,
            simulated: simulatedTransfers,
            admitted: admission?.enabled ?? true,
            downloadable: downloadable,
            // The fake backend loads every format, so nothing is blocked on
            // the engine under it — a fact about the backend, not about
            // whether the *download* is simulated.
            loadsHere: loadsHere || simulated,
            transferringKey: transferringKey,
          ),
        );

  return ModelChoice(
    entry: entry,
    title: ambiguousName
        ? '${entry.displayName} · ${engineFormat(entry.engine)}'
        : entry.displayName,
    detail: _detailLine(
      entry: entry,
      measured: speeds[entry.key],
      simulated: simulated,
      localizations: localizations,
    ),
    summary: _localizedSummary(entry, localizations),
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
    transfer: transfer,
    transferLabel: _transferLabel(
      transfer,
      entry: entry,
      suffix: suffix,
      localizations: localizations,
    ),
  );
}

/// This sheet's reading of the shared projection.
///
/// Withheld outright — not disabled — for anything this build could never
/// fetch or run, because a full-width button that does nothing when tapped
/// undoes the honesty the copy beside it provides (ADR 0007). A busy slot is
/// the one block that keeps its offer: the note explains the wait and the
/// sheet hides only the button. The refused device and the sideload never get
/// here at all; the caller withholds them before projecting.
ArtifactTransferPresentation? _pickerTransfer(
  ArtifactTransferPresentation transfer,
) {
  return switch (transfer.affordance) {
    null => null,
    TransferOffer(:final block?) when block != TransferBlock.busy => null,
    _ => transfer,
  };
}

/// How this sheet words a transfer. Short by design: these buttons sit inside
/// a row, where Settings' "Resume download" would wrap.
String? _transferLabel(
  ArtifactTransferPresentation? transfer, {
  required ModelCatalogEntry entry,
  required String suffix,
  required AppLocalizations localizations,
}) => switch (transfer?.affordance) {
  null => null,
  TransferInFlight(pausable: true) => localizations.downloadingStatus(suffix),
  TransferInFlight() => localizations.verifyingFilesPicker(suffix),
  TransferOffer(action: TransferAction.resume) => localizations.resume,
  TransferOffer(action: TransferAction.retry) => localizations.retry,
  TransferOffer() => localizations.downloadSizeAction(
    '${gigabytes(entry.totalBytes)}$suffix',
  ),
};

/// Size first, because it is the cost; then capability, which is proven per
/// artifact (#18); then speed, only where a generation measured it — the fake's
/// canned rate is labeled as such and never claimed of a phone.
String _detailLine({
  required ModelCatalogEntry entry,
  required double? measured,
  required bool simulated,
  required AppLocalizations localizations,
}) {
  return [
    gigabytes(entry.totalBytes),
    if (entry.supportsImages) localizations.readsPictures,
    if (measured != null)
      simulated
          ? localizations.modelSpeedSimulated(measured.toStringAsFixed(1))
          : localizations.modelSpeedOnPhone(measured.toStringAsFixed(1)),
  ].join(' · ');
}

/// Why the recommended row is the recommended one.
///
/// A simulated build claims nothing about hardware: it never probed any. The
/// tier sentences are the user-facing half of the classification recorded in
/// `docs/decisions/0007-supported-device-policy.md`.
String _recommendationReason({
  required AppLocalizations localizations,
  required bool simulated,
  required DeviceTier tier,
  required bool memoryKnown,
  required bool fromDevicePolicy,
}) {
  if (simulated) return localizations.buildDefaultModel;
  // An explicit GOLEM_MODEL_ARTIFACT or GOLEM_MODEL_PROFILE fixes the artifact
  // and the tier is never read (backend_policy.dart), so a memory sentence
  // there would credit a classification that played no part. The build says
  // which case it is rather than the copy guessing from a key prefix.
  if (!fromDevicePolicy) return localizations.buildDefaultModel;
  // The light tier is also where an unreadable probe lands (ADR 0007: unknown
  // is not a refusal), and absence of evidence is not a low reading.
  if (!memoryKnown) return localizations.lighterModelUnknownMemory;
  return switch (tier) {
    DeviceTier.preferred => localizations.largerModelFits,
    DeviceTier.light => localizations.sizedForPhone,
    // Unreachable while a refusal suppresses the badge; stated rather than
    // asserted so a future caller cannot get a blank reason.
    DeviceTier.unsupported => localizations.buildDefaultModel,
  };
}

/// What choosing does, or the one reason nothing here can be chosen.
///
/// The sideload sentence names the file the build pins — never the path around
/// it, which is a developer's machine and not the user's business
/// (`sideloadedModelLabel`).
String? _footnote({
  required InferenceBackendConfig backend,
  required DeviceIneligibilityReason? deviceRefusal,
  required AppLocalizations localizations,
}) {
  if (backend.simulatedInference) return null;
  if (deviceRefusal != null) {
    return deviceRefusalMessage(localizations, deviceRefusal);
  }
  if (backend.sideloaded) {
    return localizations.sideloadPreventsSwitch(
      sideloadedModelLabel(backend.modelPath!),
    );
  }
  return localizations.modelLoadsNextMessage;
}

/// Pinned entries are described from the ARB rather than by a field on the
/// entry: the copy is one of thirteen catalogs, and a `summary` string on the
/// manifest would be the English one nobody translates (#130).
///
/// Exact keys, not prefixes. A `qwen35-7b-` added later matches `qwen35-` and
/// would present the 4B copy — leans towards code, thinks a problem through —
/// for a model nobody characterized, with nothing failing. Falling through
/// instead makes it read as hand-added, which `model_choice_test` catches for
/// every key in `modelCatalog`.
String _localizedSummary(
  ModelCatalogEntry entry,
  AppLocalizations localizations,
) => switch (entry.key) {
  'gemma4-mlx' || 'gemma4-gguf' => localizations.gemmaModelSummary,
  'qwen35-2b-mlx' || 'qwen35-2b-gguf' => localizations.qwenTwoBModelSummary,
  'qwen35-mlx' || 'qwen35-gguf' => localizations.qwenFourBModelSummary,
  // A hand-added repository, which nobody has characterized and this project
  // will not characterize on its behalf.
  _ => localizations.customModelSummary,
};

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
