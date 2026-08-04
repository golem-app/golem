import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'broker/configured_inference_repository.dart';
import 'core/providers/app_providers.dart';
import 'core/repositories/fake_benchmark_repository.dart';
import 'core/repositories/fake_model_management_repository.dart';
import 'core/repositories/file_chat_history_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const streamDelayMilliseconds = int.fromEnvironment(
    'GOLEM_STREAM_DELAY_MS',
    defaultValue: 34,
  );
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();
  runApp(
    ProviderScope(
      overrides: [
        chatHistoryRepositoryProvider.overrideWithValue(
          FileChatHistoryRepository(
            File('${support.path}/flutter-chat-v1.json'),
          ),
        ),
        inferenceRepositoryProvider.overrideWithValue(
          createConfiguredInferenceRepository(
            fakeStreamDelay: Duration(milliseconds: streamDelayMilliseconds),
            documentsDirectory: documents.path,
          ),
        ),
        modelManagementRepositoryProvider.overrideWithValue(
          FakeModelManagementRepository(
            File('${support.path}/flutter-model-v1.json'),
          ),
        ),
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
