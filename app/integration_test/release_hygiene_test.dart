import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golem_flutter/app/app.dart';
import 'package:golem_flutter/broker/configured_inference_repository.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/widgets/attach_sheet.dart';
import 'package:integration_test/integration_test.dart';

const _expectedInternalTools = bool.fromEnvironment(
  'GOLEM_EXPECTED_INTERNAL_TOOLS',
);

final class _ModelFreeRuntime implements BrokerRuntime {
  @override
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
    BrokerLoadOptions options = const BrokerLoadOptions(),
    String? projectorPath,
  }) async {}

  @override
  Future<void> unload() async {}

  @override
  void releaseEngine() {}

  @override
  Future<void> cancel() async {}

  @override
  Stream<BrokerRuntimeEvent> generate(BrokerGenerationRequest request) async* {
    yield const BrokerTextDelta('Hello');
    yield const BrokerMetricsDelta(
      BrokerRuntimeMetrics(
        decodeTokensPerSecond: 12,
        promptTokensPerSecond: 34,
        generatedTokenCount: 1,
        elapsedSeconds: 0.1,
        timingSemanticsVersion: currentTimingSemantics,
      ),
    );
    yield const BrokerGenerationCompleted(BrokerStopReason.endOfSequence);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compiled flavor enforces release hygiene', (tester) async {
    final identity = AppIdentity.current;
    expect(
      identity.internalToolsEnabled,
      _expectedInternalTools,
      reason: 'Pass GOLEM_EXPECTED_INTERNAL_TOOLS for the tested flavor.',
    );

    final router = createAppRouter(
      picker: const AttachmentPicker(),
      identity: identity,
    );
    addTearDown(router.dispose);
    final paths = router.configuration.routes.whereType<GoRoute>().map(
      (route) => route.path,
    );
    expect(
      paths.contains('/benchmark'),
      _expectedInternalTools,
      reason: 'The internal route must follow the compiled identity.',
    );

    final diagnostics = <String>[];
    final repository = selectInferenceRepository(
      identity: identity,
      backend: 'llama',
      modelPath: '/model-free-test.gguf',
      modelProfile: 'gemma4',
      fakeStreamDelay: Duration.zero,
      documentsDirectory: '',
      createRuntime: _ModelFreeRuntime.new,
      samplingSeed: 7,
      diagnosticSink: diagnostics.add,
    );
    await repository
        .generate(
          context: [PromptMessage.text('user', 'Hello')],
          reasoningEnabled: false,
        )
        .drain<void>();
    await expectLater(
      repository
          .generate(
            context: [PromptMessage.text('user', 'x' * 100000)],
            reasoningEnabled: false,
          )
          .drain<void>(),
      throwsException,
    );

    final prefixes = diagnostics.map((line) => line.split(' ').first).toSet();
    if (_expectedInternalTools) {
      expect(
        prefixes,
        containsAll(['INFERNO_METRICS', 'INFERNO_PROBE', 'INFERNO_FAILURE']),
      );
    } else {
      expect(diagnostics, isEmpty);
    }
  });
}
