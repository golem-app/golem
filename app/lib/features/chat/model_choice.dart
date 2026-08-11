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

  /// The build pins an operator-supplied file, so there is nothing to switch to.
  sideload,
}

/// One row of the picker: everything shown, nothing computed by the widget.
final class ModelChoice {
  ModelChoice({
    required this.entry,
    required this.title,
    required this.detail,
    required this.selected,
    required this.selectable,
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
  required InferenceBackendConfig backend,
  required ModelState? models,
  required Set<String> loadableKeys,
  required List<ChatConversation> conversations,
  required DeviceEligibility eligibility,
  required String? deviceRefusal,
  required bool advanced,
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

  final duplicated = <String>{};
  final seen = <String>{};
  for (final entry in visible) {
    if (!seen.add(entry.displayName)) duplicated.add(entry.displayName);
  }

  // The build's own resolved artifact, never a second reading of the 7 GiB
  // rule: the badge and the model that actually loads must agree by
  // construction (broker/backend_policy.dart). Two builds recommend nothing —
  // a refused device, which has no model to be recommended, and a sideload,
  // which still carries an artifactKey the policy derived but will load a
  // pinned file instead. Badging that row would name a catalog artifact the
  // build never touches, which `InferenceBackendConfig.sideloaded` exists to
  // prevent.
  final recommendedKey = deviceRefusal != null || backend.sideloaded
      ? null
      : backend.artifactKey ?? models?.activeArtifactKey;
  final recommendation = _recommendationReason(
    simulated: simulated,
    tier: eligibility.tier,
    memoryKnown: eligibility.memoryKnown,
  );

  final transferring = models == null ? null : _keyInFlight(models, catalog);

  final choices = [
    for (final entry in visible)
      _choiceFor(
        entry: entry,
        backend: backend,
        models: models,
        loadableKeys: loadableKeys,
        conversations: conversations,
        deviceRefusal: deviceRefusal,
        advanced: advanced,
        selectedKey: selectedKey,
        ambiguousName: duplicated.contains(entry.displayName),
        recommendation: entry.key == recommendedKey ? recommendation : null,
        transferringKey: transferring,
        simulatedTransfers: models?.simulated ?? simulated,
      ),
  ];

  return ModelPickerView(
    choices: choices,
    hiddenCount: hidden,
    hiddenNote: hidden == 0
        ? null
        : '$hidden ${hidden == 1 ? 'other model is' : 'other models are'} '
              'built for a different engine and are not listed. This build '
              'runs ${engineName(_composedEngine(backend))}.',
    footnote: _footnote(backend: backend, deviceRefusal: deviceRefusal),
  );
}

ModelChoice _choiceFor({
  required ModelCatalogEntry entry,
  required InferenceBackendConfig backend,
  required ModelState? models,
  required Set<String> loadableKeys,
  required List<ChatConversation> conversations,
  required String? deviceRefusal,
  required bool advanced,
  required String? selectedKey,
  required bool ambiguousName,
  required String? recommendation,
  required String? transferringKey,
  required bool simulatedTransfers,
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
      backend: backend,
      conversations: conversations,
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
}) {
  if (deviceRefusal != null || sideloaded) return null;
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
  required InferenceBackendConfig backend,
  required List<ChatConversation> conversations,
  required bool simulated,
}) {
  final measured = measuredTokensPerSecond(
    conversations,
    modelKey: entry.key,
    defaultModelKey: backend.artifactKey,
  );
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
}) {
  if (simulated) return 'This build’s default model.';
  // The light tier is also where an unreadable memory probe lands (ADR 0007:
  // unknown is not a refusal). Saying it was "sized to fit this phone" there
  // would describe a measurement nothing performed.
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

/// What choosing does, or the one reason nothing here can be chosen.
///
/// The sideload sentence names the file the build pins — never the path around
/// it, which is a developer's machine and not the user's business
/// (`sideloadedModelLabel`).
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
