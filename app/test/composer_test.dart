import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';

import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/services/image_intake.dart';
import 'package:golem_flutter/features/chat/widgets/attach_sheet.dart';
import 'package:golem_flutter/features/chat/widgets/message_bubble.dart';

import 'support/harness.dart';
import 'support/in_memory_attachment_repository.dart';

void main() {
  testWidgets('picking a model persists it and relabels chip and nav', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      child: const ChatScreen(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    // The default effective model labels the chip and the honest
    // subtitle (nav bar and drawer header both carry the subtitle).
    expect(find.text('Gemma 4 E2B'), findsOneWidget);
    expect(find.text('Gemma 4 E2B · simulated'), findsAtLeastNWidgets(1));

    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-picker-sheet')), findsOneWidget);
    expect(find.byKey(const Key('model-picker-manage')), findsOneWidget);

    // Six simulated rows do not fit a sheet, so the last is scrolled to.
    await tester.ensureVisible(
      find.byKey(const Key('model-picker-qwen35-gguf')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-picker-qwen35-gguf')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-picker-sheet')), findsNothing);
    final active = container.read(chatControllerProvider).requireValue.active!;
    expect(active.modelKey, 'qwen35-gguf');
    expect(find.text('Qwen 3.5 4B'), findsOneWidget);
    expect(find.text('Qwen 3.5 4B · simulated'), findsAtLeastNWidgets(1));
  });

  testWidgets('picking a model on a fresh session materializes the chat', (
    tester,
  ) async {
    await pumpWithRepositories(tester, child: const ChatScreen());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container.read(chatControllerProvider).requireValue.conversations,
      isEmpty,
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-picker-gemma4-gguf')));
    await tester.pumpAndSettle();
    final state = container.read(chatControllerProvider).requireValue;
    expect(state.conversations, hasLength(1));
    expect(state.active!.modelKey, 'gemma4-gguf');
  });

  testWidgets('a real backend offers every installed same-engine model', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.mlx,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-mlx',
        modelPath: '/models/gemma',
        modelPathFromCatalog: true,
      ),
      model: const ModelState(
        artifacts: {
          'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
          'qwen35-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
        },
      ),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    // Installed alternatives are now selectable — the point of #20.
    for (final key in ['gemma4-mlx', 'qwen35-mlx']) {
      expect(
        tester
            .widget<CupertinoButton>(find.byKey(Key('model-picker-$key')))
            .onPressed,
        isNotNull,
        reason: key,
      );
    }
    // A model that is not downloaded cannot be chosen: the chip would name
    // weights the next send would fail to load.
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const Key('model-picker-qwen35-2b-mlx')),
          )
          .onPressed,
      isNull,
    );
    // Artifacts this build's engine can never load stay hidden outright
    // (#63): no dead multi-gigabyte options.
    expect(find.byKey(const Key('model-picker-qwen35-gguf')), findsNothing);
    expect(find.byKey(const Key('model-picker-gemma4-gguf')), findsNothing);
    expect(find.textContaining('loads with your next message'), findsOneWidget);
  });

  testWidgets('a sideload refuses every row and names its own file', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.mlx,
        profileKey: 'gemma4',
        // The policy still derives a key; the sideload must not inherit it.
        artifactKey: 'gemma4-mlx',
        modelPath: '/operator/my-own-build',
      ),
      model: const ModelState(
        artifacts: {
          'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
        },
      ),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const Key('model-picker-gemma4-mlx')),
          )
          .onPressed,
      isNull,
      reason:
          'switching away from a sideload is a one-way door: there is no key '
          'to switch back to',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('model-picker-sheet')),
        matching: find.textContaining('my-own-build'),
      ),
      findsOneWidget,
      reason: 'the sheet names the file the build pins, not a pinned artifact',
    );
  });

  testWidgets('a model that is not downloaded is fetched from the sheet', (
    tester,
  ) async {
    // #79's central move: the row that used to be inert and pointed at
    // Settings now carries the download that fixes it, through the same
    // controller Settings drives. The seam is scripted rather than the real
    // simulation because that one persists to disk, and file I/O never
    // completes inside a widget test's fake clock.
    final models = _ScriptedModels();
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-gguf',
        modelPath: 'documents:models/gemma4-gguf/weights.gguf',
        modelPathFromCatalog: true,
      ),
      models: models,
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();

    expect(
      find.text('Download it to use it in this chat.'),
      findsWidgets,
      reason: 'a row that cannot be picked says what would make it pickable',
    );
    final download = find.byKey(
      const Key('model-picker-download-qwen35-2b-gguf'),
    );
    await tester.ensureVisible(download);
    await tester.pumpAndSettle();
    expect(find.text('Download · 1.58 GB'), findsOneWidget);
    await tester.tap(download);
    await tester.pumpAndSettle();
    // The sheet is the most casual of the five download entrances and offers
    // no Cancel, so it asks before it spends gigabytes, exactly as Settings,
    // first run and both banners do (#26).
    expect(find.byKey(const Key('model-download-consent')), findsOneWidget);
    expect(models.calls, isEmpty, reason: 'nothing starts before consent');
    await tester.tap(find.byKey(const Key('model-download-confirm')));
    await tester.pumpAndSettle();
    expect(models.calls, ['download:qwen35-2b-gguf']);
    // And the sheet redraws around the transfer it started.
    expect(find.text('Downloading'), findsOneWidget);
    expect(
      find.byKey(const Key('model-picker-sheet')),
      findsOneWidget,
      reason: 'the sheet stays open — watching progress is the point',
    );

    final pause = find.byKey(const Key('model-picker-pause-qwen35-2b-gguf'));
    await tester.ensureVisible(pause);
    await tester.pumpAndSettle();
    await tester.tap(pause);
    await tester.pumpAndSettle();
    expect(models.calls.last, 'pause:qwen35-2b-gguf');
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Downloading'), findsNothing);
  });

  testWidgets('a transfer in the sheet reports progress and blocks the rest', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-gguf',
        modelPath: 'documents:models/gemma4-gguf/weights.gguf',
        modelPathFromCatalog: true,
      ),
      model: const ModelState(
        artifacts: {
          'qwen35-2b-gguf': ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: 790000000,
          ),
        },
      ),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    // The one transfer slot is Settings' rule too: the others say why they
    // cannot start rather than failing when tapped.
    expect(find.text('Another model is downloading.'), findsWidgets);
    // Withheld, not dimmed: GolemButton looks identical whether or not it
    // does anything, so the blocked row loses the button and keeps the note.
    expect(
      find.byKey(const Key('model-picker-download-qwen35-gguf')),
      findsNothing,
    );
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const Key('model-picker-pause-qwen35-2b-gguf')),
          )
          .onPressed,
      isNotNull,
      reason: 'a download started here can be stopped here',
    );
  });

  testWidgets('an installed model of the other engine explains itself', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.llama,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-gguf',
        modelPath: 'documents:models/gemma4-gguf/weights.gguf',
        modelPathFromCatalog: true,
      ),
      model: const ModelState(
        artifacts: {
          'gemma4-gguf': ArtifactStatus(phase: ArtifactPhase.installed),
          'gemma4-mlx': ArtifactStatus(phase: ArtifactPhase.installed),
        },
      ),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('model-picker-gemma4-mlx')),
      findsOneWidget,
      reason:
          'a model installed in Settings and then missing from chat is the '
          'absence #79 exists to explain',
    );
    expect(
      find.text(
        'Installed, but this build runs llama.cpp and cannot load MLX models.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('are not listed'),
      findsOneWidget,
      reason: 'what stays out is still counted',
    );
  });

  testWidgets('Advanced mode reveals the exact artifact, and only then', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: markdownHistory(),
      child: const ChatScreen(),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('model-picker-artifact-gemma4-gguf')),
      findsNothing,
    );
    Navigator.of(tester.element(find.byType(ChatScreen))).pop();
    await tester.pumpAndSettle();
    await container
        .read(preferencesControllerProvider.notifier)
        .setAdvancedMode(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    final artifact = find.byKey(const Key('model-picker-artifact-gemma4-gguf'));
    await tester.ensureVisible(artifact);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(artifact).data, startsWith('GGUF · Q4_K_XL · '));
  });

  testWidgets('starter chips prefill and focus the composer', (tester) async {
    await pumpWithRepositories(tester, child: const ChatScreen());
    await tester.tap(find.byKey(const Key('starter-chip-rewrite')));
    await tester.pump();
    final field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('chat-composer')),
    );
    expect(field.controller!.text, 'Rewrite this so it reads clearly: ');
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('a text-only model disables every attach row', (tester) async {
    // Capability belongs to the injected artifact, not merely its Qwen
    // profile. Keep an explicit text-only entry in this test even though all
    // current built-ins have now passed a vision path.
    final source = modelCatalog.firstWhere(
      (entry) => entry.key == 'qwen35-gguf',
    );
    final textOnly = ModelCatalogEntry(
      key: source.key,
      displayName: source.displayName,
      engine: source.engine,
      quantization: source.quantization,
      repository: source.repository,
      revision: source.revision,
      files: source.files,
      profileKey: source.profileKey,
    );
    await pumpWithRepositories(
      tester,
      catalog: [
        for (final entry in modelCatalog)
          if (entry.key == source.key) textOnly else entry,
      ],
      history: ChatHistorySnapshot(
        activeId: 'chat',
        conversations: [
          ChatConversation(
            id: 'chat',
            title: 'Text only',
            updatedAt: DateTime.utc(2026, 8, 9),
            messages: const [],
            modelKey: 'qwen35-gguf',
          ),
        ],
      ),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('attach-sheet')), findsOneWidget);
    expect(find.textContaining('handles text only'), findsOneWidget);
    for (final key in const [
      'attach-photo-library',
      'attach-take-photo',
      'attach-files',
    ]) {
      final button = tester.widget<CupertinoButton>(find.byKey(Key(key)));
      expect(button.onPressed, isNull, reason: key);
    }
  });

  testWidgets('an image-capable model attaches, trays, and sends', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: ChatHistorySnapshot(
        activeId: 'chat',
        conversations: [
          ChatConversation(
            id: 'chat',
            title: 'Pictures',
            updatedAt: DateTime.utc(2026, 8, 9),
            messages: const [],
            // One of the exact artifacts proven image-capable (#18).
            modelKey: 'gemma4-gguf',
          ),
        ],
      ),
      child: ChatScreen(picker: _StubPicker()),
    );

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    expect(find.textContaining('can see them'), findsOneWidget);
    await tester.tap(find.byKey(const Key('attach-photo-library')));
    await tester.pumpAndSettle();

    // The picked image shows in the tray, and send is now reachable with no
    // text typed at all.
    expect(find.byKey(const Key('composer-attachments')), findsOneWidget);
    final send = tester.widget<CupertinoButton>(
      find.byKey(const Key('send-button')),
    );
    expect(send.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    final messages = container
        .read(chatControllerProvider)
        .requireValue
        .active!
        .messages;
    final user = messages.first;
    expect(user.hasImages, isTrue);
    expect(user.images.single.width, 2);
    expect(user.images.single.height, 2);
    expect(find.byKey(const Key('composer-attachments')), findsNothing);
  });

  testWidgets('a rejected image toasts and attaches nothing', (tester) async {
    await pumpWithRepositories(
      tester,
      history: ChatHistorySnapshot(
        activeId: 'chat',
        conversations: [
          ChatConversation(
            id: 'chat',
            title: 'Pictures',
            updatedAt: DateTime.utc(2026, 8, 9),
            messages: const [],
            modelKey: 'gemma4-gguf',
          ),
        ],
      ),
      child: ChatScreen(
        picker: _StubPicker(rejection: ImageRejection.unsupportedType),
      ),
    );

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-photo-library')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('golem-toast')), findsOneWidget);
    expect(find.textContaining('not supported'), findsOneWidget);
    expect(find.byKey(const Key('composer-attachments')), findsNothing);
    // Let the toast's own dismiss timer run out.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('a denied camera permission says so instead of nothing', (
    tester,
  ) async {
    // The picker is a platform channel; a denied permission is a
    // PlatformException, not an ImageRejectedException, and used to escape the
    // handler entirely — the sheet closed and nothing happened.
    await pumpWithRepositories(
      tester,
      history: _picturesChat(),
      child: ChatScreen(
        picker: _StubPicker(
          error: PlatformException(code: 'camera_access_denied'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-take-photo')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('golem-toast')), findsOneWidget);
    expect(find.textContaining('needs access'), findsOneWidget);
    expect(find.byKey(const Key('composer-attachments')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('an attachment that cannot be stored keeps the turn', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: _picturesChat(),
      attachments: _UnwritableAttachmentRepository(),
      child: ChatScreen(picker: _StubPicker()),
    );

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-photo-library')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat-composer')),
      'What is this?',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle();

    // The bytes never reached disk, so the turn was never sent. Both halves of
    // it have to come back, or the picture is gone with no way to retry.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(find.byKey(const Key('composer-attachments')), findsOneWidget);
    final field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('chat-composer')),
    );
    expect(field.controller!.text, 'What is this?');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    expect(
      container.read(chatControllerProvider).requireValue.active!.messages,
      isEmpty,
    );
  });

  testWidgets('an attached image does not follow a chat switch', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      history: ChatHistorySnapshot(
        activeId: 'chat',
        conversations: [
          ChatConversation(
            id: 'chat',
            title: 'Pictures',
            updatedAt: DateTime.utc(2026, 8, 9),
            messages: const [],
            modelKey: 'gemma4-gguf',
          ),
          ChatConversation(
            id: 'other',
            title: 'Somewhere else',
            updatedAt: DateTime.utc(2026, 8, 8),
            messages: const [],
            modelKey: 'gemma4-gguf',
          ),
        ],
      ),
      child: ChatScreen(picker: _StubPicker()),
    );

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-photo-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-attachments')), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await container
        .read(chatControllerProvider.notifier)
        .selectConversation('other');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composer-attachments')), findsNothing);
  });

  testWidgets('switching to a text-only model makes send unreachable', (
    tester,
  ) async {
    final source = modelCatalog.firstWhere(
      (entry) => entry.key == 'qwen35-gguf',
    );
    final textOnly = ModelCatalogEntry(
      key: source.key,
      displayName: source.displayName,
      engine: source.engine,
      quantization: source.quantization,
      repository: source.repository,
      revision: source.revision,
      files: source.files,
      profileKey: source.profileKey,
    );
    await pumpWithRepositories(
      tester,
      catalog: [
        for (final entry in modelCatalog)
          if (entry.key == source.key) textOnly else entry,
      ],
      history: _picturesChat(),
      child: ChatScreen(picker: _StubPicker()),
    );

    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-photo-library')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const Key('send-button')))
          .onPressed,
      isNotNull,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatScreen)),
    );
    await container
        .read(chatControllerProvider.notifier)
        .setConversationModel('chat', 'qwen35-gguf');
    await tester.pumpAndSettle();

    // The tray stays — discarding someone's picture on a model switch would be
    // worse — but the turn cannot be fired at a model that cannot read it.
    expect(find.byKey(const Key('composer-attachments')), findsOneWidget);
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const Key('send-button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a sent image stays mounted across parent rebuilds', (
    tester,
  ) async {
    setViewport(tester);
    final attachments = _CountingAttachmentRepository();
    final stored = await attachments.store(tinyPngBytes, mimeType: 'image/png');
    final container = buildContainer(attachments: attachments);
    addTearDown(container.dispose);
    final message = ChatMessage(
      id: 'image-message',
      role: MessageRole.user,
      parts: [
        ImagePart(
          attachmentId: stored.id,
          mimeType: stored.mimeType,
          width: 2,
          height: 2,
          byteCount: stored.byteCount,
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 9),
    );
    Widget subject() => UncontrolledProviderScope(
      container: container,
      child: wrapApp(
        child: MessageBubble(
          message: message,
          canRegenerate: false,
          idle: false,
        ),
      ),
    );

    await tester.pumpWidget(subject());
    await tester.pump();
    final image = find.byKey(Key('message-image-${stored.id}'));
    expect(image, findsOneWidget);
    expect(attachments.readCount, 1);

    // Streaming and other chat-state changes rebuild every bubble. The
    // attachment read and its completed frame must survive that rebuild;
    // replacing FutureBuilder's future here caused the visible double blink.
    await tester.pumpWidget(subject());
    expect(image, findsOneWidget);
    expect(attachments.readCount, 1);
  });

  testWidgets('materializing a chat under the tray keeps the picture', (
    tester,
  ) async {
    // A fresh session has no conversation, so picking a model creates one
    // and activeId flips null → id. That is this chat coming into existence,
    // not a switch away from it: the attachment must survive.
    await pumpWithRepositories(
      tester,
      child: ChatScreen(picker: _StubPicker()),
    );
    await tester.tap(find.byKey(const Key('composer-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attach-photo-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-attachments')), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-picker-gemma4-gguf')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composer-attachments')), findsOneWidget);
  });

  testWidgets('an unresolved entry mid-download shows its progress', (
    tester,
  ) async {
    // Resolution and template recognition are independent: an entry whose
    // template matched no profile still downloads. Mid-download its row must
    // say so — masking progress behind the profile notice reads as a stall.
    final source = modelCatalog.firstWhere(
      (entry) => entry.key == 'qwen35-2b-mlx',
    );
    final unresolved = ModelCatalogEntry(
      key: source.key,
      displayName: source.displayName,
      engine: source.engine,
      quantization: source.quantization,
      repository: source.repository,
      revision: source.revision,
      files: source.files,
      profileKey: unresolvedProfileKey,
    );
    await pumpWithRepositories(
      tester,
      catalog: [
        for (final entry in modelCatalog)
          if (entry.key == source.key) unresolved else entry,
      ],
      history: markdownHistory(),
      backend: const InferenceBackendConfig(
        kind: InferenceBackendKind.mlx,
        profileKey: 'gemma4',
        artifactKey: 'gemma4-mlx',
        modelPath: '/models/gemma',
        modelPathFromCatalog: true,
      ),
      model: ModelState(
        artifacts: {
          'gemma4-mlx': const ArtifactStatus(phase: ArtifactPhase.installed),
          source.key: ArtifactStatus(
            phase: ArtifactPhase.downloading,
            downloadedBytes: source.totalBytes ~/ 2,
          ),
        },
      ),
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Downloading'), findsOneWidget);
    expect(find.textContaining('Chat template not recognized'), findsNothing);
  });
}

ChatHistorySnapshot _picturesChat() => ChatHistorySnapshot(
  activeId: 'chat',
  conversations: [
    ChatConversation(
      id: 'chat',
      title: 'Pictures',
      updatedAt: DateTime.utc(2026, 8, 9),
      messages: const [],
      // One of the exact artifacts proven image-capable (#18).
      modelKey: 'gemma4-gguf',
    ),
  ],
);

/// A picker that never touches a plugin: it returns a 2x2 PNG, or raises the
/// rejection — or the platform failure — under test.
final class _StubPicker extends AttachmentPicker {
  const _StubPicker({this.rejection, this.error});

  final ImageRejection? rejection;
  final Object? error;

  @override
  Future<PreparedImage?> pick(AttachSource source) async {
    if (rejection != null) throw ImageRejectedException(rejection!);
    if (error != null) throw error!;
    return PreparedImage(
      bytes: tinyPngBytes,
      mimeType: 'image/png',
      width: 2,
      height: 2,
    );
  }
}

/// A store on a full disk: everything else works, writing does not.
final class _UnwritableAttachmentRepository implements AttachmentRepository {
  @override
  Future<StoredAttachment> store(
    List<int> bytes, {
    required String mimeType,
  }) async => throw const FileSystemException('No space left on device');

  @override
  Future<List<int>?> read(String attachmentId) async => null;

  @override
  Future<void> retainOnly(Set<String> attachmentIds) async {}

  @override
  Future<int> storedBytes() async => 0;
}

final class _CountingAttachmentRepository implements AttachmentRepository {
  final InMemoryAttachmentRepository _delegate = InMemoryAttachmentRepository();
  int readCount = 0;

  @override
  Future<StoredAttachment> store(List<int> bytes, {required String mimeType}) =>
      _delegate.store(bytes, mimeType: mimeType);

  @override
  Future<List<int>?> read(String attachmentId) {
    readCount++;
    return _delegate.read(attachmentId);
  }

  @override
  Future<void> retainOnly(Set<String> attachmentIds) =>
      _delegate.retainOnly(attachmentIds);

  @override
  Future<int> storedBytes() => _delegate.storedBytes();
}

/// A model-management seam that records what the picker asked for and answers
/// synchronously. The shipped fake persists every snapshot to disk, and real
/// file I/O never completes inside a widget test's fake clock.
final class _ScriptedModels implements ModelManagementRepository {
  ModelState _state = const ModelState(
    activeArtifactKey: 'gemma4-gguf',
    artifacts: {'gemma4-gguf': ArtifactStatus(phase: ArtifactPhase.installed)},
  );

  final List<String> calls = [];

  @override
  Future<ModelState> load() async => _state;

  @override
  Stream<ModelState> download(String artifactKey) {
    calls.add('download:$artifactKey');
    _state = _state.withArtifact(
      artifactKey,
      const ArtifactStatus(
        phase: ArtifactPhase.downloading,
        downloadedBytes: 400000000,
      ),
    );
    return Stream.value(_state);
  }

  @override
  Future<ModelState> pause(String artifactKey) async {
    calls.add('pause:$artifactKey');
    _state = _state.withArtifact(
      artifactKey,
      _state.statusOf(artifactKey).copyWith(phase: ArtifactPhase.paused),
    );
    return _state;
  }

  @override
  Future<ModelState> cancel(String artifactKey) async {
    calls.add('cancel:$artifactKey');
    return _state;
  }

  @override
  Future<ModelState> delete(String artifactKey) async {
    calls.add('delete:$artifactKey');
    return _state;
  }

  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    String? failure,
  }) async => _state;

  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => _state;
}
