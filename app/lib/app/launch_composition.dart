import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:path_provider/path_provider.dart';

import '../broker/configured_inference_repository.dart';
import '../broker/model_catalog.dart';
import '../broker/model_profile.dart';
import '../core/app_identity.dart';
import '../core/application/session_bridges.dart';
import '../core/domain/app_preferences.dart';
import '../core/domain/app_state.dart';
import '../core/domain/device_eligibility.dart';
import '../core/domain/inference_backend.dart';
import '../core/domain/model_catalog.dart';
import '../core/providers/app_providers.dart';
import '../core/repositories/contracts.dart';
import '../core/repositories/fake_benchmark_repository.dart';
import '../core/repositories/fake_model_management_repository.dart';
import '../core/repositories/file_attachment_repository.dart';
import '../core/repositories/file_chat_history_repository.dart';
import '../core/repositories/file_preferences_repository.dart';
import '../core/repositories/file_settings_repository.dart';
import '../core/repositories/real_model_management_repository.dart';
import '../core/services/artifact_downloader.dart';
import '../core/services/cache_probe.dart';
import '../core/services/custom_repository_resolver.dart';
import '../core/services/device_storage.dart';
import '../core/services/hugging_face_api.dart';
import '../core/services/repository_resolver.dart';
import '../features/chat/application/chat_providers.dart';
import '../features/models/application/model_providers.dart';

/// Everything one successful launch composition produces: the full set of
/// inputs for [launchOverrides]. Interface-typed throughout so host tests can
/// assemble one from in-memory fakes without touching the platform.
final class LaunchDependencies {
  const LaunchDependencies({
    required this.backendConfig,
    required this.deviceEligibility,
    required this.chatHistoryRepository,
    required this.settingsRepository,
    required this.preferencesRepository,
    required this.attachmentRepository,
    required this.cacheProbe,
    required this.diskFreeSpaceProbe,
    required this.inferenceRepository,
    required this.modelCatalogEntries,
    required this.customRepositoryResolver,
    required this.modelManagementRepository,
    required this.deviceCapacityProbe,
    required this.documentsPath,
    required this.benchmarkRepository,
  });

  final InferenceBackendConfig backendConfig;

  /// The device classification this launch made, from the same read that chose
  /// the model (#27).
  final DeviceEligibility deviceEligibility;
  final ChatHistoryRepository chatHistoryRepository;
  final SettingsRepository settingsRepository;
  final PreferencesRepository preferencesRepository;
  final AttachmentRepository attachmentRepository;
  final CacheProbe cacheProbe;
  final DiskSpaceProbe diskFreeSpaceProbe;
  final InferenceRepository inferenceRepository;
  final List<ModelCatalogEntry> modelCatalogEntries;
  final CustomRepositoryResolver customRepositoryResolver;
  final ModelManagementRepository modelManagementRepository;
  final DiskCapacityProbe deviceCapacityProbe;
  final String documentsPath;
  final BenchmarkRepository? benchmarkRepository;
}

/// The fallible launch composition, injectable so the bootstrap gate and its
/// tests can substitute failure for the real thing.
typedef LaunchComposer =
    Future<LaunchDependencies> Function(AppIdentity identity);

/// Deadline over the required launch stages: backend resolution, the
/// application-directory lookups, the preferences read, and repository
/// construction. The downloader start is bounded separately and can only
/// degrade, never fail the launch — so a composition that times out has never
/// constructed a downloader, and a retry can never race a second instance
/// against the plugin's process-wide singletons.
const launchDeadline = Duration(seconds: 8);

/// Bound on the optional downloader start; on expiry the launch proceeds and
/// the abandoned future is explicitly ignored.
const downloaderStartDeadline = Duration(seconds: 5);

/// Maps a composition error onto the failure pane's copy. `Error` covers the
/// dart-define `StateError`s (and kin): developer text that goes to
/// diagnostics, never onto a surface.
LaunchFailure classifyLaunchFailure(Object error) => switch (error) {
  TimeoutException() => const LaunchFailure(LaunchFailureKind.timedOut),
  MissingPluginException() || PlatformException() => const LaunchFailure(
    LaunchFailureKind.storageUnavailable,
  ),
  Error() => const LaunchFailure(LaunchFailureKind.invalidConfiguration),
  _ => const LaunchFailure(LaunchFailureKind.unknown),
};

/// Release-mode evidence seam (`GOLEM_LAUNCH_FAILURES=<n>`): fails the first
/// n compositions so one process can demonstrate the failure pane, Try
/// again, and recovery on a device. A decorator, so [composeLaunch] itself
/// stays deterministic.
int _injectedFailuresRemaining = const int.fromEnvironment(
  'GOLEM_LAUNCH_FAILURES',
);

bool shouldInjectLaunchFailure(AppIdentity identity, int remaining) =>
    identity.internalToolsEnabled && remaining > 0;

Future<LaunchDependencies> composeLaunchWithInjectedFailures(
  AppIdentity identity,
) async {
  if (shouldInjectLaunchFailure(identity, _injectedFailuresRemaining)) {
    _injectedFailuresRemaining--;
    throw Exception('Injected launch failure (GOLEM_LAUNCH_FAILURES).');
  }
  return composeLaunch(identity: identity);
}

/// Monotonic composition generation: an attempt superseded by a retry aborts
/// at the stage boundary before downloader construction, because
/// `Future.timeout` abandons rather than cancels the underlying work.
int _compositionGeneration = 0;

/// Composes the production repository graph. Every fallible launch dependency
/// lives here; the bootstrap gate renders this future's outcome.
Future<LaunchDependencies> composeLaunch({
  required AppIdentity identity,
  Duration requiredDeadline = launchDeadline,
  Duration downloaderDeadline = downloaderStartDeadline,
}) async {
  final generation = ++_compositionGeneration;
  final (:dependencies, :downloader) = await _composeRequired(
    identity: identity,
    superseded: () => generation != _compositionGeneration,
  ).timeout(requiredDeadline);
  // Before the first chat or settings surface can ask for a download: the
  // plugin discards updates that arrive with no listener attached, and startup
  // replays every status delivered while this process did not exist. Bounded
  // and guarded — a platform channel that refuses or hangs must not take the
  // launch down with it; downloads degrade (the repository's next call retries
  // the start), everything else still works.
  if (downloader != null) {
    final start = downloader.initialize();
    try {
      await start.timeout(downloaderDeadline);
    } on TimeoutException {
      start.ignore();
    } catch (_) {}
  }
  return dependencies;
}

Future<
  ({LaunchDependencies dependencies, BackgroundArtifactDownloader? downloader})
>
_composeRequired({
  required AppIdentity identity,
  required bool Function() superseded,
}) async {
  const streamDelayMilliseconds = int.fromEnvironment(
    'GOLEM_STREAM_DELAY_MS',
    defaultValue: 34,
  );
  // One resolution feeds the inference repository, the active artifact, and
  // the backend signal provider, so they can never disagree. qa and the
  // flavorless test identity wire all fakes so goldens, journeys, and CI stay
  // deterministic and offline; production and dev wire the real ones. Explicit
  // dart-defines override the flavor default, and an override to real
  // inference drags model management along with it: a real engine fed by a
  // download simulation would "install" files that do not exist.
  final (config: backendConfig, :eligibility) = await resolveConfiguredBackend(
    identity: identity,
  );
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();
  final temporary = await getTemporaryDirectory();
  final stateFile = File('${support.path}/flutter-model-v2.json');
  final useFakeModels =
      (identity == AppIdentity.qa || identity == AppIdentity.flutter) &&
      backendConfig.simulatedInference;
  // Preferences load before the repositories so persisted custom repositories
  // (Advanced mode) are in the fake downloader's catalog from the first frame.
  // The provider catalog stays the pinned list; the UI derives pinned + custom.
  final preferencesRepository = FilePreferencesRepository(
    File('${support.path}/flutter-ui-prefs-v1.json'),
  );
  AppPreferences preferences;
  try {
    preferences = await preferencesRepository.load();
  } on Exception {
    // A store the process cannot read must not kill the launch: the catalog
    // merge degrades to the pinned set, and the preferences surfaces present
    // the read failure with a retry once the UI is up.
    preferences = const AppPreferences();
  }
  final pinnedKeys = {for (final entry in modelCatalog) entry.key};
  final customEntries = [
    for (final spec in preferences.customModels)
      if (!pinnedKeys.contains(spec.key)) spec,
  ];
  final mergedCatalog = [
    ...modelCatalog,
    for (final spec in customEntries) spec.toCatalogEntry(),
  ];
  // The real downloader only takes repositories that resolved: an unresolved
  // entry's file list is synthesized, so offering to fetch it would put a
  // request on the wire for a file nobody has seen. Those stay out of its
  // catalog and their card keeps saying it cannot download here.
  final realCatalog = [
    ...modelCatalog,
    for (final spec in customEntries)
      if (spec.resolved != null) spec.toCatalogEntry(),
  ];
  // Created before the scope so the inference repository can read an image
  // part's bytes without going through a provider.
  final attachments = FileAttachmentRepository(
    Directory('${support.path}/attachments'),
  );

  // A timed-out attempt keeps running past its deadline (Future.timeout does
  // not cancel), so the abandoned run must stop here: only the live attempt
  // may construct the downloader against the plugin's process-wide singletons.
  // The throw lands in the timeout wrapper's already-completed future, where
  // it is dropped, never classified.
  if (superseded()) {
    throw StateError('Launch composition superseded by a retry.');
  }
  // The real repository's catalog grows in place as repositories are added, so
  // holding the concrete instance is what lets the engine resolve an entry that
  // did not exist at launch (#20).
  // Held rather than constructed inline: it has to be started before the
  // composed app can ask for a download, and only the real path may touch the
  // plugin at all.
  final artifactDownloader = useFakeModels
      ? null
      : BackgroundArtifactDownloader(
          // Where the plugin stages partial transfers: Android uses the cache
          // directory for small files and application support for large ones,
          // and orphans in either survive a kill with nothing to sweep them.
          temporaryDirectories: [temporary.path, support.path],
        );
  final realModels = artifactDownloader == null
      ? null
      : RealModelManagementRepository(
          stateFile: stateFile,
          documentsDirectory: documents.path,
          catalog: realCatalog,
          downloader: artifactDownloader,
          diskSpace: const DeviceStorageChannel(),
          backupExclusion: const DeviceStorageChannel(),
          // A sideload has no catalog entry, so no pinned artifact may be
          // called active on its behalf.
          activeArtifactKey: backendConfig.sideloaded
              ? null
              : backendConfig.artifactKey,
        );
  final ModelManagementRepository modelManagement =
      realModels ??
      FakeModelManagementRepository(stateFile, catalog: mergedCatalog);
  final dependencies = LaunchDependencies(
    backendConfig: backendConfig,
    deviceEligibility: eligibility,
    chatHistoryRepository: FileChatHistoryRepository(
      File('${support.path}/flutter-chat-v1.json'),
    ),
    settingsRepository: FileSettingsRepository(
      File('${support.path}/flutter-prefs-v1.json'),
    ),
    preferencesRepository: preferencesRepository,
    // In application support beside the other stores, so each flavor's
    // container stays self-contained.
    attachmentRepository: attachments,
    cacheProbe: useFakeModels
        ? FakeCacheProbe()
        : DirectoryCacheProbe(temporary.path),
    diskFreeSpaceProbe: const DeviceStorageChannel(),
    inferenceRepository: createConfiguredInferenceRepository(
      identity: identity,
      config: backendConfig,
      fakeStreamDelay: const Duration(milliseconds: streamDelayMilliseconds),
      documentsDirectory: documents.path,
      readAttachment: attachments.read,
      // The download layer's own list, live: a repository added in
      // Advanced mode becomes activatable without a relaunch.
      activationCatalog: realModels == null ? null : () => realModels.catalog,
    ),
    modelCatalogEntries: modelCatalog,
    customRepositoryResolver:
        // The fake identity never reaches the network, so its resolution is
        // synthesized; the real one carries the broker's profiles because
        // core cannot import them itself.
        backendConfig.kind == InferenceBackendKind.fake
        ? const DeterministicRepositoryResolver()
        : HuggingFaceRepositoryResolver(
            api: HttpClientHuggingFaceApi(),
            profiles: brokerProfileSpecs,
          ),
    modelManagementRepository: modelManagement,
    deviceCapacityProbe: const DeviceStorageChannel(),
    documentsPath: documents.path,
    benchmarkRepository: identity.internalToolsEnabled
        ? FakeBenchmarkRepository(
            Directory('${documents.path}/SimulatedBenchmarks'),
            readAsset: rootBundle.loadString,
          )
        : null,
  );
  return (dependencies: dependencies, downloader: artifactDownloader);
}

/// Maps one coherent set of launch dependencies onto the provider seams.
/// Pure: composition failures happen in [composeLaunch], never here.
List<Override> launchOverrides(LaunchDependencies dependencies) => [
  chatHistoryRepositoryProvider.overrideWithValue(
    dependencies.chatHistoryRepository,
  ),
  settingsRepositoryProvider.overrideWithValue(dependencies.settingsRepository),
  preferencesRepositoryProvider.overrideWithValue(
    dependencies.preferencesRepository,
  ),
  attachmentRepositoryProvider.overrideWithValue(
    dependencies.attachmentRepository,
  ),
  cacheProbeProvider.overrideWithValue(dependencies.cacheProbe),
  diskFreeSpaceProbeProvider.overrideWithValue(dependencies.diskFreeSpaceProbe),
  inferenceBackendProvider.overrideWithValue(dependencies.backendConfig),
  deviceEligibilityProvider.overrideWithValue(dependencies.deviceEligibility),
  inferenceRepositoryProvider.overrideWithValue(
    dependencies.inferenceRepository,
  ),
  modelCatalogEntriesProvider.overrideWithValue(
    dependencies.modelCatalogEntries,
  ),
  customRepositoryResolverProvider.overrideWithValue(
    dependencies.customRepositoryResolver,
  ),
  modelManagementRepositoryProvider.overrideWithValue(
    dependencies.modelManagementRepository,
  ),
  deviceCapacityProbeProvider.overrideWithValue(
    dependencies.deviceCapacityProbe,
  ),
  documentsPathProvider.overrideWithValue(dependencies.documentsPath),
  // The session bridges' ensure-owner hooks: a command reaching an unbuilt
  // owner constructs it — the pre-split `ref.read(...notifier)` semantics —
  // and the owner's build binds the bridge before the dispatch proceeds.
  // Only the composition root may name the feature providers; the bridges
  // themselves stay core (#88).
  // Container reads, not ref reads: the owners watch their bridge to re-bind
  // on refresh, so a ref read here would register bridge→owner and trip the
  // circular-dependency assert. The container read force-builds without
  // registering a dependency.
  chatSessionBridgeProvider.overrideWith((ref) {
    final bridge = ChatSessionBridge();
    bridge.bindEnsureOwner(() => ref.container.read(chatControllerProvider));
    return bridge;
  }),
  modelSessionBridgeProvider.overrideWith((ref) {
    final bridge = ModelSessionBridge();
    bridge.bindEnsureOwner(() => ref.container.read(modelControllerProvider));
    return bridge;
  }),
  if (dependencies.benchmarkRepository case final benchmarkRepository?)
    benchmarkRepositoryProvider.overrideWithValue(benchmarkRepository),
];
