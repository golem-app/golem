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
import 'core/repositories/file_chat_history_repository.dart';
import 'core/repositories/file_settings_repository.dart';
import 'core/repositories/real_model_management_repository.dart';
import 'core/services/artifact_downloader.dart';
import 'core/services/device_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const streamDelayMilliseconds = int.fromEnvironment(
    'GOLEM_STREAM_DELAY_MS',
    defaultValue: 34,
  );
  const inferenceBackend = String.fromEnvironment(
    'GOLEM_INFERENCE_BACKEND',
    defaultValue: 'fake',
  );
  const modelProfile = String.fromEnvironment(
    'GOLEM_MODEL_PROFILE',
    defaultValue: 'gemma4',
  );
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();
  final stateFile = File('${support.path}/flutter-model-v2.json');
  // The qa flavor and flavorless test harness stay on the deterministic
  // fake so goldens, journeys, and CI never touch the network; dev and
  // production builds download for real.
  final identity = AppIdentity.current;
  final useFakeModels =
      identity == AppIdentity.qa || identity == AppIdentity.flutter;
  final ModelManagementRepository modelManagement = useFakeModels
      ? FakeModelManagementRepository(stateFile, catalog: modelCatalog)
      : RealModelManagementRepository(
          stateFile: stateFile,
          documentsDirectory: documents.path,
          catalog: modelCatalog,
          downloader: BackgroundArtifactDownloader(),
          diskSpace: const DeviceStorageChannel(),
          backupExclusion: const DeviceStorageChannel(),
          activeArtifactKey: activeArtifactKeyFor(
            backend: inferenceBackend,
            modelProfile: modelProfile,
          ),
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
        inferenceRepositoryProvider.overrideWithValue(
          createConfiguredInferenceRepository(
            fakeStreamDelay: Duration(milliseconds: streamDelayMilliseconds),
            documentsDirectory: documents.path,
          ),
        ),
        modelCatalogEntriesProvider.overrideWithValue(modelCatalog),
        modelManagementRepositoryProvider.overrideWithValue(modelManagement),
        benchmarkRepositoryProvider.overrideWithValue(
          FakeBenchmarkRepository(
            Directory('${documents.path}/SimulatedBenchmarks'),
            readAsset: rootBundle.loadString,
          ),
        ),
      ],
      child: const GolemApp(),
    ),
  );
}
