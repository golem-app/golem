import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'broker/configured_inference_repository.dart';
import 'broker/model_catalog.dart';
import 'core/app_identity.dart';
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
import 'core/services/device_storage.dart';
import 'features/chat/widgets/attach_sheet.dart';

Future<void> main() => launch();

/// Composes and launches the app. The picker seam lets the integration
/// journey exercise the complete attach sheet and composer flow without
/// handing control to an OS photo-library UI; production uses the default.
Future<void> launch({
  AttachmentPicker picker = const AttachmentPicker(),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  const streamDelayMilliseconds = int.fromEnvironment(
    'GOLEM_STREAM_DELAY_MS',
    defaultValue: 34,
  );
  // One resolution feeds the inference repository, the active artifact,
  // and the backend signal provider, so they can never disagree. The
  // composition rule, stated once: qa and the flavorless test identity
  // wire all fakes (inference, model management, benchmark) so goldens,
  // journeys, and CI stay deterministic and offline; production and dev
  // wire the real implementations. Explicit dart-defines override the
  // flavor default in any build — and an override to real inference
  // carries model management to the real implementation with it: a real
  // engine fed by a download simulation would "install" files that do
  // not exist.
  final backendConfig = await resolveConfiguredBackend();
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();
  final temporary = await getTemporaryDirectory();
  final stateFile = File('${support.path}/flutter-model-v2.json');
  final identity = AppIdentity.current;
  final useFakeModels =
      (identity == AppIdentity.qa || identity == AppIdentity.flutter) &&
      backendConfig.simulatedInference;
  // Preferences load before the repositories so persisted custom
  // repositories (Advanced mode) are part of the fake downloader's catalog
  // from the first frame. The provider catalog stays the pinned list; the
  // UI derives pinned + custom reactively.
  final preferencesRepository = FilePreferencesRepository(
    File('${support.path}/flutter-ui-prefs-v1.json'),
  );
  final preferences = await preferencesRepository.load();
  final pinnedKeys = {for (final entry in modelCatalog) entry.key};
  final mergedCatalog = [
    ...modelCatalog,
    for (final spec in preferences.customModels)
      if (!pinnedKeys.contains(spec.key)) spec.toCatalogEntry(),
  ];
  // Created before the scope so the inference repository can read the bytes
  // an image part refers to without going through a provider.
  final attachments = FileAttachmentRepository(
    Directory('${support.path}/attachments'),
  );

  final ModelManagementRepository modelManagement = useFakeModels
      ? FakeModelManagementRepository(stateFile, catalog: mergedCatalog)
      : RealModelManagementRepository(
          stateFile: stateFile,
          documentsDirectory: documents.path,
          catalog: modelCatalog,
          downloader: BackgroundArtifactDownloader(),
          diskSpace: const DeviceStorageChannel(),
          backupExclusion: const DeviceStorageChannel(),
          activeArtifactKey: backendConfig.artifactKey,
        );
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
        // Beside the other per-flavor stores in application support, so the
        // container stays self-contained and each flavor keeps its own.
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
          ),
        ),
        modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
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
