import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/features/chat/model_choice.dart';

void main() {
  const llama = InferenceBackendConfig(
    kind: InferenceBackendKind.llama,
    profileKey: 'gemma4',
    artifactKey: 'gemma4-gguf',
    modelPath: 'documents:models/gemma4-gguf/weights.gguf',
    modelPathFromCatalog: true,
  );
  const mlx = InferenceBackendConfig(
    kind: InferenceBackendKind.mlx,
    profileKey: 'gemma4',
    artifactKey: 'gemma4-mlx',
    modelPath: 'documents:models/gemma4-mlx',
    modelPathFromCatalog: true,
  );
  // What resolveBackendPolicy actually produces for an operator sideload: the
  // artifactKey is still derived, only modelPathFromCatalog is false.
  const sideload = InferenceBackendConfig(
    kind: InferenceBackendKind.llama,
    profileKey: 'gemma4',
    artifactKey: 'gemma4-gguf',
    modelPath: '/opt/models/hand-rolled.gguf',
  );
  const fake = InferenceBackendConfig.fake();

  ModelState stateWith(Map<String, ArtifactStatus> artifacts) {
    var state = const ModelState(activeArtifactKey: 'gemma4-mlx');
    artifacts.forEach((key, status) {
      state = state.withArtifact(key, status);
    });
    return state;
  }

  const installed = ArtifactStatus(phase: ArtifactPhase.installed);

  Set<String> loadable(
    InferenceBackendConfig backend,
    ModelState models, {
    List<ModelCatalogEntry>? catalog,
  }) => {
    for (final entry in catalog ?? modelCatalog)
      if (entry.profileKey != unresolvedProfileKey &&
          backend.kind.loads(entry.engine) &&
          models.statusOf(entry.key).phase == ArtifactPhase.installed)
        entry.key,
  };

  ModelPickerView view({
    InferenceBackendConfig backend = llama,
    ModelState? models,
    List<ModelCatalogEntry>? catalog,
    List<ChatConversation> conversations = const [],
    DeviceEligibility eligibility = const DeviceEligibility(
      tier: DeviceTier.preferred,
    ),
    String? deviceRefusal,
    bool advanced = false,
    String? selectedKey,
  }) {
    // Matching what both repositories publish: a stamped active artifact, which
    // is the fake's only source for a recommendation.
    final state = models ?? stateWith(const {});
    return buildModelPickerView(
      catalog: catalog ?? modelCatalog,
      backend: backend,
      models: state,
      loadableKeys: loadable(backend, state, catalog: catalog),
      conversations: conversations,
      eligibility: eligibility,
      deviceRefusal: deviceRefusal,
      advanced: advanced,
      selectedKey: selectedKey,
    );
  }

  ModelChoice rowFor(ModelPickerView built, String key) =>
      built.choices.firstWhere((choice) => choice.entry.key == key);

  group('what the sheet lists', () {
    test('a real build lists its own engine and counts the rest', () {
      final built = view();
      expect(
        built.choices.map((choice) => choice.entry.key),
        ['gemma4-gguf', 'qwen35-2b-gguf', 'qwen35-gguf'],
        reason: 'catalog order, filtered to what llama.cpp can load',
      );
      expect(built.hiddenCount, 3);
      expect(
        built.hiddenNote,
        '3 other models are built for a different engine and are not listed. '
        'This build runs llama.cpp.',
        reason: 'absence is counted and explained, never silent (#79)',
      );
    });

    test('an installed artifact of the other engine is listed, not hidden', () {
      // The exact grievance #79 names: a user installs a model in Settings and
      // then cannot find it in chat, with nothing on screen to explain why.
      final built = view(models: stateWith({'gemma4-mlx': installed}));
      expect(
        built.choices.last.entry.key,
        'gemma4-mlx',
        reason:
            'a row kept only to explain itself sits after everything this '
            'build can run',
      );
      final row = rowFor(built, 'gemma4-mlx');
      expect(row.selectable, isFalse);
      expect(row.block, ModelBlock.otherEngine);
      expect(
        row.blockReason,
        'Installed, but this build runs llama.cpp and cannot load MLX models.',
      );
      expect(
        row.transfer,
        isNull,
        reason:
            'there is nothing useful to offer for an artifact that will '
            'never load here',
      );
      expect(built.hiddenCount, 2, reason: 'the other two MLX rows stay out');
    });

    test('the fake keeps the whole catalog and hides nothing', () {
      final built = view(backend: fake);
      expect(built.choices, hasLength(modelCatalog.length));
      expect(built.hiddenCount, 0);
      expect(built.hiddenNote, isNull);
    });

    test('an MLX build names MLX as the engine that is running', () {
      final built = view(backend: mlx);
      expect(built.hiddenNote, endsWith('This build runs MLX.'));
    });
  });

  group('naming', () {
    test('a name is only disambiguated when it is ambiguous on screen', () {
      // Both Qwen 2B entries are visible under the fake and share a name; under
      // llama.cpp only one is, and appending an engine there would be noise.
      final simulated = view(backend: fake);
      expect(rowFor(simulated, 'qwen35-2b-mlx').title, 'Qwen 3.5 2B · MLX');
      expect(rowFor(simulated, 'qwen35-2b-gguf').title, 'Qwen 3.5 2B · GGUF');
      expect(rowFor(view(), 'qwen35-2b-gguf').title, 'Qwen 3.5 2B');
    });

    test('no display name carries a quantization any more', () {
      for (final entry in modelCatalog) {
        expect(
          entry.displayName,
          isNot(anyOf(contains('QAT'), contains('Q4'), contains('bit'))),
          reason:
              'the artifact belongs on the Advanced line, not in the name '
              '(docs/decisions/0008-model-presentation.md)',
        );
        expect(entry.summary, isNotNull);
      }
    });
  });

  group('the recommendation', () {
    test('names the artifact this build resolved, with the tier reason', () {
      final built = view();
      expect(
        rowFor(built, 'gemma4-gguf').recommendation,
        'This phone has the memory for the larger model.',
      );
      expect(
        built.choices.where((choice) => choice.recommendation != null),
        hasLength(1),
      );
    });

    test('a light-tier device is told the model was sized for it', () {
      const light = InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: 'qwen35',
        artifactKey: 'qwen35-2b-gguf',
        modelPath: 'documents:models/qwen35-2b-gguf/weights.gguf',
        modelPathFromCatalog: true,
      );
      final built = view(
        backend: light,
        eligibility: const DeviceEligibility(tier: DeviceTier.light),
      );
      expect(
        rowFor(built, 'qwen35-2b-gguf').recommendation,
        'Sized to fit this phone’s memory.',
      );
      expect(rowFor(built, 'gemma4-gguf').recommendation, isNull);
    });

    test('an unread memory probe is not described as a measurement', () {
      // The light tier is also where a probe that answered nothing lands
      // (ADR 0007). Claiming the model was "sized to fit this phone" there
      // would describe a reading that never happened.
      const light = InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: 'qwen35',
        artifactKey: 'qwen35-2b-gguf',
        modelPath: 'documents:models/qwen35-2b-gguf/weights.gguf',
        modelPathFromCatalog: true,
      );
      final built = view(
        backend: light,
        eligibility: classifyDevice(
          capabilities: const DeviceCapabilities(),
          memoryFloorBytes: appleMemoryFloorBytes,
        ),
      );
      expect(
        rowFor(built, 'qwen35-2b-gguf').recommendation,
        'The lighter model, picked because this phone’s memory could not '
        'be read.',
      );
    });

    test('a simulated build claims nothing about a phone it never probed', () {
      final built = view(backend: fake);
      expect(
        rowFor(built, 'gemma4-mlx').recommendation,
        'This build’s default model.',
        reason: 'the fake falls back to the state’s active artifact',
      );
    });

    test('a refused device is recommended nothing at all', () {
      final built = view(
        eligibility: const DeviceEligibility(
          tier: DeviceTier.unsupported,
          reason: DeviceIneligibilityReason.belowMemoryFloor,
          message: 'no memory here',
        ),
        deviceRefusal: 'no memory here',
      );
      expect(
        built.choices.every((choice) => choice.recommendation == null),
        isTrue,
        reason: 'nothing is recommended on a device admitted to nothing (#27)',
      );
      expect(
        rowFor(built, 'gemma4-gguf').blockReason,
        'Not available on this device.',
      );
      expect(
        rowFor(built, 'gemma4-gguf').transfer,
        isNull,
        reason: 'the affordance is withheld, not dimmed (ADR 0007)',
      );
      expect(
        built.footnote,
        'no memory here',
        reason: 'the verdict is spelled out once, not once per row',
      );
    });
  });

  group('the detail line', () {
    test('quotes size and proven capability, and no speed by default', () {
      expect(
        rowFor(view(), 'qwen35-2b-gguf').detail,
        '1.58 GB · reads pictures',
      );
    });

    test('quotes a measured rate only once one was measured', () {
      final conversations = [
        ChatConversation(
          id: 'c1',
          title: 'measured',
          updatedAt: DateTime.utc(2026),
          modelKey: 'qwen35-2b-gguf',
          messages: [
            ChatMessage.text(
              id: 'm1',
              role: MessageRole.assistant,
              text: 'hi',
              createdAt: DateTime.utc(2026),
              metrics: const InferenceMetrics(
                promptTokensPerSecond: 13,
                decodeTokensPerSecond: 24.05,
                tokenCount: 4,
                elapsedSeconds: 0.2,
              ),
            ),
          ],
        ),
      ];
      expect(
        rowFor(view(conversations: conversations), 'qwen35-2b-gguf').detail,
        '1.58 GB · reads pictures · 24.1 tok/s on this phone',
      );
      expect(
        rowFor(
          view(backend: fake, conversations: conversations),
          'qwen35-2b-gguf',
        ).detail,
        endsWith('24.1 tok/s simulated'),
        reason:
            'the fake’s canned rate is never claimed of a phone '
            '(core/domain/model_speed.dart)',
      );
    });
  });

  group('simulated transfers', () {
    test('a simulated download says so, exactly as Settings does', () {
      var state = const ModelState(
        activeArtifactKey: 'gemma4-mlx',
        simulated: true,
      );
      state = state.withArtifact(
        'qwen35-2b-gguf',
        const ArtifactStatus(
          phase: ArtifactPhase.downloading,
          downloadedBytes: 400000000,
        ),
      );
      final built = view(backend: fake, models: state);
      final progress =
          rowFor(built, 'qwen35-2b-gguf').transfer! as ModelTransferProgress;
      expect(progress.label, 'Downloading · simulated');
      final offer =
          rowFor(built, 'qwen35-gguf').transfer! as ModelTransferOffer;
      expect(offer.label, endsWith('· simulated'));
    });

    test('a real download carries no qualifier', () {
      final built = view(
        models: stateWith({
          'qwen35-2b-gguf': const ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: 400000000,
          ),
        }),
      );
      final progress =
          rowFor(built, 'qwen35-2b-gguf').transfer! as ModelTransferProgress;
      expect(progress.label, 'Downloading');
    });
  });

  group('the artifact line', () {
    test('is absent until Advanced mode is on', () {
      expect(rowFor(view(), 'qwen35-2b-gguf').artifactLine, isNull);
      final advanced = rowFor(view(advanced: true), 'qwen35-2b-gguf');
      expect(advanced.artifactLine, startsWith('GGUF · Q4_0 · '));
      expect(
        advanced.artifactLine,
        contains(
          modelCatalog
              .firstWhere((entry) => entry.key == 'qwen35-2b-gguf')
              .repository,
        ),
      );
    });
  });

  group('download affordances', () {
    test(
      'an absent artifact offers its download and says why it is blocked',
      () {
        final row = rowFor(view(), 'qwen35-2b-gguf');
        expect(row.selectable, isFalse);
        expect(row.block, ModelBlock.notInstalled);
        expect(row.blockReason, 'Download it to use it in this chat.');
        final offer = row.transfer! as ModelTransferOffer;
        expect(offer.label, 'Download · 1.58 GB');
        expect(offer.enabled, isTrue);
        expect(offer.note, isNull);
      },
    );

    test('a running transfer reports progress and can be paused', () {
      final entry = modelCatalog.firstWhere(
        (item) => item.key == 'qwen35-2b-gguf',
      );
      final built = view(
        models: stateWith({
          'qwen35-2b-gguf': ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: entry.totalBytes ~/ 4,
          ),
        }),
      );
      final progress =
          rowFor(built, 'qwen35-2b-gguf').transfer! as ModelTransferProgress;
      expect(progress.fraction, closeTo(0.25, 0.01));
      expect(progress.label, 'Downloading');
      expect(progress.pausable, isTrue);
    });

    test('verification runs to completion and offers no pause', () {
      final built = view(
        models: stateWith({
          'qwen35-2b-gguf': const ArtifactStatus(
            phase: ArtifactPhase.verifying,
          ),
        }),
      );
      final progress =
          rowFor(built, 'qwen35-2b-gguf').transfer! as ModelTransferProgress;
      expect(progress.pausable, isFalse);
      expect(progress.label, 'Verifying files');
    });

    test('a paused transfer resumes and says how far it got', () {
      final built = view(
        models: stateWith({
          'qwen35-2b-gguf': const ArtifactStatus(
            phase: ArtifactPhase.paused,
            downloadedBytes: 500000000,
          ),
        }),
      );
      final row = rowFor(built, 'qwen35-2b-gguf');
      final offer = row.transfer! as ModelTransferOffer;
      expect(offer.label, 'Resume');
      expect(offer.note, 'Paused at 0.50 GB of 1.58 GB.');
      expect(
        row.blockReason,
        'Resume the download to use it in this chat.',
        reason: 'a half-downloaded model told to "download it" reads as a bug',
      );
    });

    test('a failed transfer retries and carries the failure it hit', () {
      final built = view(
        models: stateWith({
          'qwen35-2b-gguf': const ArtifactStatus(
            phase: ArtifactPhase.failed,
            failure: 'Needs 2.00 GB free; 0.40 GB available.',
          ),
        }),
      );
      final offer =
          rowFor(built, 'qwen35-2b-gguf').transfer! as ModelTransferOffer;
      expect(offer.label, 'Retry');
      expect(offer.note, 'Needs 2.00 GB free; 0.40 GB available.');
    });

    test('one transfer at a time, and the others say so', () {
      final built = view(
        models: stateWith({
          'gemma4-gguf': const ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: 1,
          ),
        }),
      );
      final blocked =
          rowFor(built, 'qwen35-2b-gguf').transfer! as ModelTransferOffer;
      expect(blocked.enabled, isFalse);
      expect(blocked.note, 'Another model is downloading.');
      expect(
        rowFor(built, 'gemma4-gguf').transfer,
        isA<ModelTransferProgress>(),
        reason: 'the artifact holding the slot still shows its own progress',
      );
    });

    test('an installed artifact offers no transfer', () {
      final built = view(models: stateWith({'gemma4-gguf': installed}));
      final row = rowFor(built, 'gemma4-gguf');
      expect(row.transfer, isNull);
      expect(row.selectable, isTrue);
      expect(row.blockReason, isNull);
    });
  });

  group('selection', () {
    test(
      'an installed same-engine artifact is selectable and marks itself',
      () {
        final built = view(
          models: stateWith({'gemma4-gguf': installed}),
          selectedKey: 'gemma4-gguf',
        );
        expect(rowFor(built, 'gemma4-gguf').selected, isTrue);
        expect(rowFor(built, 'qwen35-gguf').selected, isFalse);
        expect(
          built.footnote,
          'The model you pick loads with your next message.',
        );
      },
    );

    test('nothing is ticked while nothing can run', () {
      // A fresh real install: effectiveModelKey still names the artifact the
      // build would load, but it is not on disk. Ticking it beside "Download
      // it to use it in this chat" would contradict the row's own copy.
      final built = view(selectedKey: 'gemma4-gguf');
      final row = rowFor(built, 'gemma4-gguf');
      expect(row.selected, isFalse);
      expect(row.recommendation, isNotNull, reason: 'the badge still points');
      expect(row.transfer, isA<ModelTransferOffer>());
    });

    test('a refused device may not pick even an installed model', () {
      // loadableKeys asks whether an artifact is installed and of the right
      // engine — both still true on a device admitted to nothing, which is
      // reachable when a release tightens the floor under models already on
      // disk. Left selectable, the sheet would offer a model on the same
      // screen as a footnote saying the device cannot run one (#27).
      final built = view(
        models: stateWith({'gemma4-gguf': installed, 'qwen35-gguf': installed}),
        eligibility: const DeviceEligibility(
          tier: DeviceTier.unsupported,
          reason: DeviceIneligibilityReason.belowMemoryFloor,
          message: 'This device cannot run models.',
        ),
        deviceRefusal: 'This device cannot run models.',
      );
      for (final choice in built.choices) {
        expect(choice.selectable, isFalse, reason: choice.entry.key);
        expect(choice.block, ModelBlock.deviceRefused);
        expect(choice.transfer, isNull);
      }
      expect(built.footnote, 'This device cannot run models.');
    });

    test('the fake honours any row, installed or not', () {
      final built = view(backend: fake);
      expect(
        built.choices.every((choice) => choice.selectable),
        isTrue,
        reason:
            'the simulated backend loads nothing, so nothing can be promised '
            'that it would refuse',
      );
    });

    test('a sideload refuses every row and offers no download', () {
      final built = view(
        backend: sideload,
        models: stateWith({'gemma4-gguf': installed}),
      );
      for (final choice in built.choices) {
        expect(choice.selectable, isFalse);
        expect(choice.block, ModelBlock.sideload);
        expect(choice.blockReason, 'Pinned by this build.');
        expect(choice.transfer, isNull);
        expect(
          choice.recommendation,
          isNull,
          reason:
              'the policy still derives an artifactKey for a sideload, and '
              'badging that row would name a pinned artifact this build never '
              'loads',
        );
      }
      expect(
        built.footnote,
        'This build runs hand-rolled.gguf from a path it pins, so this chat '
        'cannot switch models.',
        reason: 'the sheet names the file, never the path around it',
      );
    });

    test('an installed model whose template is unknown says so', () {
      final unresolved = ModelCatalogEntry(
        key: 'custom-mystery',
        displayName: 'Mystery',
        engine: ModelEngine.gguf,
        quantization: 'custom',
        repository: 'someone/mystery',
        revision: 'abc123',
        profileKey: unresolvedProfileKey,
        files: const [ModelArtifactFile(path: 'weights.gguf', bytes: 1000)],
      );
      final catalog = [...modelCatalog, unresolved];
      final built = view(
        catalog: catalog,
        models: stateWith({'custom-mystery': installed}),
      );
      final row = rowFor(built, 'custom-mystery');
      expect(row.block, ModelBlock.unrecognizedTemplate);
      expect(
        row.blockReason,
        'Installed, but Golem does not recognize this model’s chat template, '
        'so it cannot prompt it.',
      );
      expect(
        row.summary,
        'Added by you from Hugging Face.',
        reason:
            'nobody has characterized a hand-added repository, and this '
            'project will not do it on their behalf',
      );
    });
  });

  test('every unselectable row carries copy, in every reachable state', () {
    // The invariant the whole sheet rests on, swept rather than spot-checked:
    // a blocked row with no sentence is the bug #79 was filed about.
    final states = [
      const ArtifactStatus(),
      const ArtifactStatus(phase: ArtifactPhase.downloading),
      const ArtifactStatus(phase: ArtifactPhase.paused),
      const ArtifactStatus(phase: ArtifactPhase.verifying),
      const ArtifactStatus(phase: ArtifactPhase.failed),
      installed,
    ];
    for (final backend in [llama, mlx, fake, sideload]) {
      for (final status in states) {
        for (final refusal in [null, 'refused']) {
          final models = stateWith({
            for (final entry in modelCatalog) entry.key: status,
          });
          final built = buildModelPickerView(
            catalog: modelCatalog,
            backend: backend,
            models: models,
            loadableKeys: loadable(backend, models),
            conversations: const [],
            eligibility: const DeviceEligibility(tier: DeviceTier.light),
            deviceRefusal: refusal,
            advanced: false,
          );
          for (final choice in built.choices) {
            expect(
              choice.selectable == (choice.blockReason == null),
              isTrue,
              reason:
                  '${choice.entry.key} under ${backend.kind} / '
                  '${status.phase} / refusal=$refusal',
            );
            expect(choice.detail, isNotEmpty);
            expect(choice.title, isNotEmpty);
          }
          expect((built.hiddenCount > 0) == (built.hiddenNote != null), isTrue);
        }
      }
    }
  });
}
