import '../core/domain/byte_format.dart';
import '../core/domain/device_eligibility.dart';
import '../core/domain/model_admission.dart';
import '../core/domain/model_catalog.dart';
import '../core/domain/models.dart';
import '../core/domain/repository_resolution.dart';
import '../core/repositories/contracts.dart';
import 'bidi.dart';
import 'generated/app_localizations.dart';

/// The engine half of a model card's format line. Deliberately unlocalized:
/// engine and quantization tokens are stable technical labels.
String engineLabel(ModelEngine engine) => switch (engine) {
  ModelEngine.mlx => 'MLX',
  ModelEngine.gguf => 'GGUF · llama.cpp',
};

String deviceRefusalMessage(
  AppLocalizations l10n,
  DeviceIneligibilityReason? reason,
) => switch (reason) {
  DeviceIneligibilityReason.missingInstructionSet =>
    l10n.deviceMissingInstructionSet,
  DeviceIneligibilityReason.belowMemoryFloor => l10n.deviceBelowMemoryFloor,
  DeviceIneligibilityReason.virtualDevice => l10n.deviceVirtualHardware,
  null => l10n.modelsUnavailableGeneric,
};

String modelAdmissionReason(
  AppLocalizations l10n,
  ModelAdmissionOption option,
) => switch (option.block) {
  ModelAdmissionBlock.otherEngine => l10n.otherEngineAdmission(
    ltrIsolate(option.entry.engine == ModelEngine.mlx ? 'GGUF' : 'MLX'),
  ),
  ModelAdmissionBlock.needsPreferredTier when !option.memoryKnown =>
    l10n.memoryUnreadableLighterModel,
  ModelAdmissionBlock.needsPreferredTier => l10n.needsMoreReportedMemory,
  ModelAdmissionBlock.unsupportedDevice => l10n.modelsUnavailableOnDevice,
  null => '',
};

String repositoryRejectionMessage(
  AppLocalizations l10n,
  RepositoryRejection reason,
) => switch (reason) {
  RepositoryRejection.malformedIdentifier => l10n.repositoryMalformedIdentifier,
  RepositoryRejection.notFoundOrPrivate => l10n.repositoryNotFoundOrPrivate,
  RepositoryRejection.gated => l10n.repositoryGated,
  RepositoryRejection.disabled => l10n.repositoryDisabled,
  RepositoryRejection.rateLimited => l10n.repositoryRateLimited,
  RepositoryRejection.network => l10n.repositoryNetwork,
  RepositoryRejection.malformedMetadata => l10n.repositoryMalformedMetadata,
  RepositoryRejection.unsafePath => l10n.repositoryUnsafePath,
  RepositoryRejection.noWeights => l10n.repositoryNoWeights,
  RepositoryRejection.shardedWeights => l10n.repositoryShardedWeights,
  RepositoryRejection.unsafeWeightFormat => l10n.repositoryUnsafeWeightFormat,
  RepositoryRejection.missingRequiredFile => l10n.repositoryMissingRequiredFile,
  RepositoryRejection.inconsistentMetadata =>
    l10n.repositoryInconsistentMetadata,
  RepositoryRejection.unsupportedArchitecture =>
    l10n.repositoryUnsupportedArchitecture,
  RepositoryRejection.headerTooLarge => l10n.repositoryHeaderTooLarge,
  RepositoryRejection.duplicateEntry => l10n.repositoryDuplicateEntry,
};

String artifactFailureMessage(AppLocalizations l10n, ArtifactStatus status) =>
    switch (status.failureReason) {
      ArtifactFailure(
        kind: ArtifactFailureKind.insufficientStorage,
        :final requiredBytes?,
        :final availableBytes?,
      ) =>
        l10n.downloadInsufficientStorage(
          ltrIsolate(gigabytes(requiredBytes)),
          ltrIsolate(gigabytes(availableBytes)),
        ),
      ArtifactFailure(
        kind: ArtifactFailureKind.hashVerification,
        :final fileName?,
      ) =>
        l10n.downloadHashVerificationFailed(ltrIsolate(fileName)),
      ArtifactFailure(
        kind: ArtifactFailureKind.unexpectedSize,
        :final fileName?,
      ) =>
        l10n.downloadUnexpectedFileSize(ltrIsolate(fileName)),
      _ => l10n.downloadFailed,
    };

/// What a generation failure means, by kind, for a surface that shows a run
/// rather than a chat (#58): the same sentences the chat recovery banner
/// uses for the kinds an engine can raise.
String inferenceFailureMessage(
  AppLocalizations l10n,
  InferenceFailureKind kind, {
  int? contextTokens,
}) => switch (kind) {
  InferenceFailureKind.engine => l10n.generationFailed,
  InferenceFailureKind.modelUnavailable => l10n.modelUnavailableFailure,
  InferenceFailureKind.unsupportedModel => l10n.unsupportedModelFailure,
  InferenceFailureKind.attachmentUnavailable =>
    l10n.attachmentUnavailableFailure,
  InferenceFailureKind.unsupportedImages => l10n.unsupportedImagesFailure,
  InferenceFailureKind.invalidModelArtifact => l10n.invalidModelArtifactFailure,
  InferenceFailureKind.unsupportedDevice => l10n.modelsUnavailableGeneric,
  InferenceFailureKind.contextExhausted => l10n.contextExhausted,
  InferenceFailureKind.outOfMemory =>
    contextTokens == null
        ? l10n.outOfMemory
        : l10n.outOfMemoryAtContext(contextTokens),
  InferenceFailureKind.insufficientMemory => l10n.insufficientMemory,
  InferenceFailureKind.budgetExhaustedBeforeAnswer => l10n.budgetExhausted,
};
