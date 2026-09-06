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

/// Whether the tested flavor is Golem Model Lab. Every phone flavor and the
/// consumer macOS flavors must compile with `kLabBuild` false — that constant
/// is what keeps the lab out of a store build (ADR 0021).
const _expectedLab = bool.fromEnvironment('GOLEM_EXPECTED_LAB');

final class _ModelFreeRuntime implements BrokerRuntime {
  @override
  Future<void> load({
    required BrokerEngine engine,
    required String modelPath,
    BrokerLoadOptions options = const BrokerLoadOptions(),
    String? projectorPath,
    BrokerLoadProgress? onProgress,
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

Iterable<String> _routePaths(List<RouteBase> routes) sync* {
  for (final route in routes) {
    if (route is GoRoute) yield route.path;
    yield* _routePaths(route.routes);
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
    expect(
      identity.isLab,
      _expectedLab,
      reason: 'Pass GOLEM_EXPECTED_LAB=true only for --flavor lab.',
    );
    expect(kLabBuild, _expectedLab);

    final router = createAppRouter(
      picker: const AttachmentPicker(),
      identity: identity,
    );
    addTearDown(router.dispose);
    // Every route sits inside the first-run ShellRoute (ADR 0015), so only
    // a recursive walk sees it — the top level alone holds no GoRoute, which
    // would read as "no benchmark" on every identity.
    final paths = _routePaths(router.configuration.routes).toList();
    expect(
      paths.contains('/benchmark'),
      identity.composesBenchmark,
      reason: 'The benchmark route must follow what the identity composes.',
    );
    expect(identity.internalToolsEnabled, _expectedInternalTools);

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
