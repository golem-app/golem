import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/domain/app_state.dart';
import 'package:golem_flutter/core/domain/download_pace.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/domain/resolved_repository.dart';

void main() {
  group('value equality', () {
    test('SamplingOverrides and GenerationSettings compare by content', () {
      const a = SamplingOverrides(temperature: 0.7, topK: 40);
      const b = SamplingOverrides(temperature: 0.7, topK: 40);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const SamplingOverrides(temperature: 0.8, topK: 40)));

      final settings = const GenerationSettings().withModel('gemma4', a);
      final same = const GenerationSettings().withModel('gemma4', b);
      expect(settings, same);
      expect(settings.hashCode, same.hashCode);
      expect(settings, isNot(const GenerationSettings()));
    });

    test('GenerationSettings JSON roundtrip preserves equality', () {
      final settings = const GenerationSettings().withModel(
        'qwen35',
        const SamplingOverrides(topP: 0.9, maxTokens: 1024),
      );
      final decoded = GenerationSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(settings.encode()) as Map),
      );
      expect(decoded, settings);
    });

    test('AppPreferences compares by content, custom models included', () {
      const spec = CustomModelSpec(
        repository: 'org/model',
        engine: ModelEngine.gguf,
        resolved: ResolvedRepository(
          commitSha: 'abc123',
          files: [ModelArtifactFile(path: 'weights.gguf', bytes: 42)],
          quantization: 'Q4_0',
        ),
      );
      final a = const AppPreferences()
          .withStyle('gemma4', ResponseStyle.precise)
          .withCustomModel(spec);
      final b = const AppPreferences()
          .withStyle('gemma4', ResponseStyle.precise)
          .withCustomModel(spec);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const AppPreferences()));
      expect(a.copyWith(theme: ThemeSetting.dark), isNot(a));
    });

    test('AppPreferences JSON roundtrip preserves equality', () {
      final preferences = const AppPreferences(
        textScale: 1.2,
        advancedMode: true,
        systemPrompt: 'Be terse.',
      ).withStyle('qwen35', ResponseStyle.creative);
      final decoded = AppPreferences.fromJson(
        Map<String, Object?>.from(jsonDecode(preferences.encode()) as Map),
      );
      expect(decoded, preferences);
    });

    test('ModelState and ArtifactStatus compare by content', () {
      const status = ArtifactStatus(
        phase: ArtifactPhase.downloading,
        downloadedBytes: 512,
      );
      final a = const ModelState().withArtifact('gemma4-gguf', status);
      final b = const ModelState().withArtifact(
        'gemma4-gguf',
        const ArtifactStatus(
          phase: ArtifactPhase.downloading,
          downloadedBytes: 512,
        ),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(b.copyWith(runtime: RuntimePhase.loaded)));
      expect(status, isNot(status.copyWith(verifiedBytes: 1)));
      // The unstamped simulated/activeArtifactKey fields participate too.
      expect(a.stamp(simulated: true), isNot(a));
    });

    test('DownloadPaceSnapshot compares by content, phase included', () {
      const snapshot = DownloadPaceSnapshot(
        artifactKey: 'gemma4-mlx',
        mbPerSecond: 44.0,
        eta: Duration(seconds: 54),
      );
      expect(
        snapshot,
        const DownloadPaceSnapshot(
          artifactKey: 'gemma4-mlx',
          mbPerSecond: 44.0,
          eta: Duration(seconds: 54),
        ),
      );
      expect(snapshot.hashCode, snapshot.hashCode);
      // A verify window and a download window are different figures even
      // when they happen to share a rate, so the phase tells them apart.
      for (final other in const [
        DownloadPaceSnapshot(
          artifactKey: 'gemma4-mlx',
          mbPerSecond: 44.0,
          eta: Duration(seconds: 54),
          phase: ArtifactPhase.verifying,
        ),
        DownloadPaceSnapshot(
          artifactKey: 'gemma4-gguf',
          mbPerSecond: 44.0,
          eta: Duration(seconds: 54),
        ),
        DownloadPaceSnapshot(
          artifactKey: 'gemma4-mlx',
          mbPerSecond: 45.0,
          eta: Duration(seconds: 54),
        ),
        DownloadPaceSnapshot(artifactKey: 'gemma4-mlx', mbPerSecond: 44.0),
      ]) {
        expect(snapshot, isNot(other));
        expect(snapshot.hashCode, isNot(other.hashCode));
      }
    });

    test('ModelCatalogEntry compares by content', () {
      ModelCatalogEntry entry() => const ModelCatalogEntry(
        key: 'gemma4-gguf',
        displayName: 'Gemma 4 E2B',
        engine: ModelEngine.gguf,
        quantization: 'Q4_K_XL',
        repository: 'org/repo',
        revision: 'deadbeef',
        files: [ModelArtifactFile(path: 'weights.gguf', bytes: 7)],
        profileKey: 'gemma4',
        inputModalities: {ModelInputModality.text, ModelInputModality.image},
      );
      expect(entry(), entry());
      expect(entry().hashCode, entry().hashCode);
    });

    test('ChatFailure and InferenceMetrics compare by content', () {
      const failure = ChatFailure(
        kind: ChatFailureKind.missingModel,
        artifactKey: 'gemma4-gguf',
      );
      expect(
        failure,
        const ChatFailure(
          kind: ChatFailureKind.missingModel,
          artifactKey: 'gemma4-gguf',
        ),
      );
      const metrics = InferenceMetrics(
        promptTokensPerSecond: 10,
        decodeTokensPerSecond: 20,
        tokenCount: 30,
        elapsedSeconds: 1.5,
      );
      expect(
        metrics,
        const InferenceMetrics(
          promptTokensPerSecond: 10,
          decodeTokensPerSecond: 20,
          tokenCount: 30,
          elapsedSeconds: 1.5,
        ),
      );
      expect(
        metrics,
        isNot(
          const InferenceMetrics(
            promptTokensPerSecond: 10,
            decodeTokensPerSecond: 20,
            tokenCount: 31,
            elapsedSeconds: 1.5,
          ),
        ),
      );
      // A record measured here and now claims the current contract, and the
      // contract is part of its identity.
      expect(metrics.timingSemanticsVersion, currentTimingSemantics);
      expect(
        metrics,
        isNot(
          const InferenceMetrics(
            promptTokensPerSecond: 10,
            decodeTokensPerSecond: 20,
            tokenCount: 30,
            elapsedSeconds: 1.5,
            timingSemanticsVersion: legacyTimingSemantics,
          ),
        ),
      );
    });

    test('ChatState stays identity-equal by design', () {
      // Reassigned per streaming token: deep equality would cost
      // O(messages x text) per token and suppress nothing.
      const a = ChatState();
      const b = ChatState();
      expect(identical(a, b), isTrue); // const canonicalization
      final c = ChatState(conversations: [_conversation('one')]);
      final d = ChatState(conversations: [_conversation('one')]);
      expect(c == d, isFalse);
    });
  });

  group('collection-mutation protection', () {
    test('chat collections refuse external mutation', () {
      final conversation = _conversation('one');
      final state = ChatState(conversations: [conversation]);
      expect(
        () => state.conversations.add(conversation),
        throwsUnsupportedError,
      );
      expect(
        () => conversation.messages.add(conversation.messages.first),
        throwsUnsupportedError,
      );
      expect(
        () => conversation.messages.first.parts.add(const TextPart('x')),
        throwsUnsupportedError,
      );
      final snapshot = ChatHistorySnapshot(conversations: [conversation]);
      expect(() => snapshot.conversations.removeLast(), throwsUnsupportedError);
    });

    test('settings, preferences, and model state refuse external mutation', () {
      final settings = const GenerationSettings().withModel(
        'gemma4',
        const SamplingOverrides(topK: 20),
      );
      expect(
        () => settings.models['gemma4'] = const SamplingOverrides(),
        throwsUnsupportedError,
      );
      final preferences = const AppPreferences().withStyle(
        'gemma4',
        ResponseStyle.precise,
      );
      expect(() => preferences.responseStyles.clear(), throwsUnsupportedError);
      expect(
        () => preferences.customModels.add(
          const CustomModelSpec(
            repository: 'org/model',
            engine: ModelEngine.gguf,
          ),
        ),
        throwsUnsupportedError,
      );
      final models = const ModelState().withArtifact(
        'gemma4-gguf',
        const ArtifactStatus(),
      );
      expect(
        () => models.artifacts.remove('gemma4-gguf'),
        throwsUnsupportedError,
      );
    });

    test('catalog entries refuse external mutation', () {
      const entry = ModelCatalogEntry(
        key: 'k',
        displayName: 'd',
        engine: ModelEngine.mlx,
        quantization: 'q',
        repository: 'r',
        revision: 'v',
        files: [ModelArtifactFile(path: 'p', bytes: 1)],
        profileKey: 'gemma4',
      );
      expect(
        () => entry.files.add(const ModelArtifactFile(path: 'x', bytes: 2)),
        throwsUnsupportedError,
      );
      expect(
        () => entry.inputModalities.add(ModelInputModality.image),
        throwsUnsupportedError,
      );
    });

    test('chat history JSON roundtrip is byte-stable', () {
      final snapshot = ChatHistorySnapshot(
        conversations: [_conversation('one'), _conversation('two')],
        activeId: 'one',
      );
      final decoded = ChatHistorySnapshot.fromJson(
        Map<String, Object?>.from(jsonDecode(snapshot.encode()) as Map),
      );
      expect(decoded.encode(), snapshot.encode());
    });
  });
}

ChatConversation _conversation(String id) => ChatConversation(
  id: id,
  title: 'Chat $id',
  messages: [
    ChatMessage.text(
      id: '$id-m1',
      role: MessageRole.user,
      text: 'hello',
      createdAt: DateTime.utc(2026, 8, 2),
    ),
  ],
  updatedAt: DateTime.utc(2026, 8, 2),
);
