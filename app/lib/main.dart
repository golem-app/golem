import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'broker/configured_inference_repository.dart';
import 'broker/model_catalog.dart';
import 'broker/model_profile.dart';
import 'core/app_identity.dart';
import 'core/domain/inference_backend.dart';
import 'core/providers/app_providers.dart';
import 'core/repositories/contracts.dart';
import 'core/repositories/fake_benchmark_repository.dart';
import 'core/repositories/fake_model_management_repository.dart';
import 'core/repositories/file_attachment_repository.dart';
import 'core/repositories/file_chat_history_repository.dart';
import 'core/repositories/file_preferences_repository.dart';
import 'core/repositories/file_settings_repository.dart';
import 'core/repositories/real_model_management_repository.dart';
import 'core/services/artifact_downloader.dart';
import 'core/services/cache_probe.dart';
import 'core/services/custom_repository_resolver.dart';
import 'core/services/device_storage.dart';
import 'core/services/hugging_face_api.dart';
import 'core/services/repository_resolver.dart';
import 'features/chat/widgets/attach_sheet.dart';

Future<void> main() => launch();

/// Composes and launches the app. The picker seam lets the integration
/// journey drive the whole attach flow without an OS photo-library UI.
Future<void> launch({
  AttachmentPicker picker = const AttachmentPicker(),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final preferences = await preferencesRepository.load();
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
  final realModels = useFakeModels
      ? null
      : RealModelManagementRepository(
          stateFile: stateFile,
          documentsDirectory: documents.path,
          catalog: realCatalog,
          downloader: BackgroundArtifactDownloader(),
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
  runApp(
    ProviderScope(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          FileChatHistoryRepository(
            File('${support.path}/flutter-chat-v1.json'),
          ),
        ),
        settingsRepositoryProvider.overrideWithValue(
          FileSettingsRepository(File('${support.path}/flutter-prefs-v1.json')),
        ),
        preferencesRepositoryProvider.overrideWithValue(preferencesRepository),
        // In application support beside the other stores, so each flavor's
        // container stays self-contained.
        attachmentRepositoryProvider.overrideWithValue(attachments),
        cacheProbeProvider.overrideWithValue(
          useFakeModels
              ? FakeCacheProbe()
              : DirectoryCacheProbe(temporary.path),
        ),
        diskFreeSpaceProbeProvider.overrideWithValue(
          const DeviceStorageChannel(),
        ),
        inferenceBackendProvider.overrideWithValue(backendConfig),
        inferenceRepositoryProvider.overrideWithValue(
          createConfiguredInferenceRepository(
            config: backendConfig,
            fakeStreamDelay: Duration(milliseconds: streamDelayMilliseconds),
            documentsDirectory: documents.path,
            readAttachment: attachments.read,
            // The download layer's own list, live: a repository added in
            // Advanced mode becomes activatable without a relaunch.
            activationCatalog: realModels == null
                ? null
                : () => realModels.catalog,
          ),
        ),
        modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
        customRepositoryResolverProvider.overrideWithValue(
          // The fake identity never reaches the network, so its resolution is
          // synthesized; the real one carries the broker's profiles because
          // core cannot import them itself.
          backendConfig.kind == InferenceBackendKind.fake
              ? const DeterministicRepositoryResolver()
              : HuggingFaceRepositoryResolver(
                  api: HttpClientHuggingFaceApi(),
                  profiles: brokerProfileSpecs,
                ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(modelManagement),
        deviceCapacityProbeProvider.overrideWithValue(
          const DeviceStorageChannel(),
        ),
        documentsPathProvider.overrideWithValue(documents.path),
        benchmarkRepositoryProvider.overrideWithValue(
          FakeBenchmarkRepository(
            Directory('${documents.path}/SimulatedBenchmarks'),
            readAsset: rootBundle.loadString,
          ),
        ),
      ],
      child: GolemApp(picker: picker),
    ),
  );
}
