import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:path_provider/path_provider.dart';

import '../broker/configured_inference_repository.dart';
import '../broker/model_catalog.dart';
import '../broker/model_profile.dart';
import '../core/app_identity.dart';
import '../core/domain/app_preferences.dart';
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

/// Everything one successful launch composition produces: the full set of
/// inputs for [launchOverrides]. Interface-typed throughout so host tests can
/// assemble one from in-memory fakes without touching the platform.
final class LaunchDependencies {
  const LaunchDependencies({
    required this.backendConfig,
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
  final BenchmarkRepository benchmarkRepository;
}

/// The fallible launch composition, injectable so the bootstrap gate and its
/// tests can substitute failure for the real thing.
typedef LaunchComposer = Future<LaunchDependencies> Function();

/// Composes the production repository graph. Every fallible launch dependency
/// lives here: backend resolution, the application-directory lookups, the
/// preferences read, and the downloader start.
Future<LaunchDependencies> composeLaunch() async {
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
  final backendConfig = await resolveConfiguredBackend();
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();
  final temporary = await getTemporaryDirectory();
  final stateFile = File('${support.path}/flutter-model-v2.json');
  final identity = AppIdentity.current;
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

  // The real repository's catalog grows in place as repositories are added, so
  // holding the concrete instance is what lets the engine resolve an entry that
  // did not exist at launch (#20).
  // Held rather than constructed inline: it has to be started before the first
  // frame, and only the real path may touch the plugin at all.
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
  // Before the first chat or settings surface can ask for a download: the
  // plugin discards updates that arrive with no listener attached, and startup
  // replays every status delivered while this process did not exist. Guarded
  // like the stores above — a platform channel that refuses must not take the
  // launch down with it; downloads degrade, everything else still works.
  try {
    await artifactDownloader?.initialize();
  } catch (_) {}
  return LaunchDependencies(
    backendConfig: backendConfig,
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
    benchmarkRepository: FakeBenchmarkRepository(
      Directory('${documents.path}/SimulatedBenchmarks'),
      readAsset: rootBundle.loadString,
    ),
  );
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
  benchmarkRepositoryProvider.overrideWithValue(
    dependencies.benchmarkRepository,
  ),
];
