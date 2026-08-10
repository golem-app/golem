import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/inferno_inference_repository.dart';
import 'package:golem_flutter/broker/model_profile.dart';
import 'package:golem_flutter/broker/model_runtime_config.dart';
import 'package:golem_flutter/broker/runtime.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/acceptance_hud.dart';

/// Proves a real engine actually swaps models mid-conversation, and that each
/// turn is rendered and sampled with *its own* model's profile (#20).
///
/// ```sh
/// flutter test integration_test/model_switch_acceptance_test.dart \
///   -d macos --flavor qa \
///   --dart-define=GOLEM_SWITCH_GEMMA_GGUF=/abs/path/gemma-4-...gguf \
///   --dart-define=GOLEM_SWITCH_QWEN_GGUF=/abs/path/Qwen3.5-2B-Q4_0.gguf
/// ```
///
/// Deliberately below the UI and below the downloader: those paths are proven
/// elsewhere (#15, #52). What is new here is one process loading two different
/// artifacts under two different chat templates.
///
/// The given artifacts are symlinked into the app's own
/// `Documents/models/<key>/` layout, because that is the only shape activation
/// resolves — it derives every path from the catalog entry, so a loose absolute
/// path is not expressible. The links are removed afterwards; the weights they
/// point at are never touched.
///
/// CI never sets the defines, so this self-skips and touches no weights.
const _gemma = String.fromEnvironment('GOLEM_SWITCH_GEMMA_GGUF');
const _qwen = String.fromEnvironment('GOLEM_SWITCH_QWEN_GGUF');

ModelCatalogEntry _entry({
  required String key,
  required String profileKey,
  required String source,
}) => ModelCatalogEntry(
  key: key,
  displayName: key,
  engine: ModelEngine.gguf,
  quantization: 'local',
  repository: 'local/switch-acceptance',
  revision: 'a' * 40,
  profileKey: profileKey,
  files: [
    ModelArtifactFile(
      path: source.split('/').last,
      bytes: File(source).lengthSync(),
      sha256: null,
      role: ModelFileRole.weights,
    ),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'one process loads two artifacts, each under its own profile',
    skip: _gemma.isEmpty || _qwen.isEmpty
        ? 'Set GOLEM_SWITCH_GEMMA_GGUF and GOLEM_SWITCH_QWEN_GGUF to local '
              'GGUF artifacts to run the model-switch acceptance.'
        : false,
    () async {
      AcceptanceHud.takeOver();
      AcceptanceHud.step('Linking both artifacts into the container');
      final metrics = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.startsWith('INFERNO_METRICS')) {
          metrics.add(message);
        }
        original(message, wrapWidth: wrapWidth);
      };
      addTearDown(() => debugPrint = original);

      final catalog = [
        _entry(key: 'switch-gemma', profileKey: 'gemma4', source: _gemma),
        _entry(key: 'switch-qwen', profileKey: 'qwen35', source: _qwen),
      ];
      final documents = (await getApplicationDocumentsDirectory()).path;
      for (final (entry, source) in [
        (catalog[0], _gemma),
        (catalog[1], _qwen),
      ]) {
        final directory = Directory('$documents/${entry.installDirectory}');
        await directory.create(recursive: true);
        final link = Link('${directory.path}/${entry.files.single.path}');
        if (await link.exists()) await link.delete();
        await link.create(source);
        addTearDown(() => directory.delete(recursive: true));
      }

      final repository = InfernoInferenceRepository(
        InfernoRuntimeAdapter.native(),
        engine: BrokerEngine.llamaCpp,
        modelPath: _gemma,
        profile: modelProfiles['gemma4']!,
        // No initial key, so every turn below resolves through the catalog
        // rather than reusing the boot configuration for the first one.
        documentsDirectory: documents,
        resolveConfig: (key) =>
            resolveModelRuntimeConfig(key, catalog: catalog),
      );
      addTearDown(repository.unload);

      Future<String> ask(String modelKey, String question) async {
        AcceptanceHud.step('Loading $modelKey');
        final answer = StringBuffer();
        var tokens = 0;
        await for (final event in repository.generate(
          context: [PromptMessage.text('user', question)],
          reasoningEnabled: false,
          modelKey: modelKey,
        )) {
          if (event is AnswerDelta) {
            if (tokens == 0) AcceptanceHud.step('Answering on $modelKey');
            answer.write(event.text);
            AcceptanceHud.progress(detail: 'tokens: ${++tokens}');
          }
        }
        return answer.toString();
      }

      // Turn one on Gemma.
      final first = await ask(
        'switch-gemma',
        'Name the capital of France. Answer with one word.',
      );
      expect(repository.residentModelKey.value, 'switch-gemma');
      expect(first, contains('Paris'), reason: first);

      // Turn two on Qwen, same process: the engine must unload and reload, and
      // the prompt must be rendered by Qwen's template rather than Gemma's.
      final second = await ask(
        'switch-qwen',
        'Name the capital of Japan. Answer with one word.',
      );
      expect(
        repository.residentModelKey.value,
        'switch-qwen',
        reason:
            'residency must follow the switch, or every label built on it '
            'names the wrong model',
      );
      expect(second, contains('Tokyo'), reason: second);

      // Back to Gemma, to prove the swap is not one-way.
      final third = await ask(
        'switch-gemma',
        'Name the capital of Italy. Answer with one word.',
      );
      expect(repository.residentModelKey.value, 'switch-gemma');
      expect(third, contains('Rome'), reason: third);

      AcceptanceHud.step('Checking each turn sampled under its own profile');
      // Each turn's sampling came from its own profile. Qwen 3.5 pins its
      // non-thinking sampling; Gemma's defaults differ, so the metrics lines
      // are the evidence the profile travelled with the model.
      expect(metrics, hasLength(3));
      final temperatures = [
        for (final line in metrics)
          RegExp(r'temperature=([0-9.]+)').firstMatch(line)?.group(1),
      ];
      expect(
        temperatures[0],
        isNot(temperatures[1]),
        reason:
            'both turns sampled identically, so one profile was applied to '
            'both models: $metrics',
      );
      expect(temperatures[0], temperatures[2]);
      // debugPrint, not stdout: the integration harness forwards the former and
      // swallows the latter, which is how INFERNO_METRICS reaches a device log.
      original(
        'GOLEM_SWITCH gemma="${first.trim()}" qwen="${second.trim()}" '
        'gemma="${third.trim()}"',
      );
      AcceptanceHud.finish('Done — three turns, two templates, one process');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
