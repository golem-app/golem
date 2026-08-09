import 'package:flutter/cupertino.dart';
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

  testWidgets('a real backend keeps other model rows disabled', (tester) async {
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
      child: const ChatScreen(),
    );
    await tester.tap(find.byKey(const Key('composer-model-chip')));
    await tester.pumpAndSettle();
    // Only the running artifact stays tappable until #20; the footnote
    // explains the constraint honestly.
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const Key('model-picker-gemma4-mlx')),
          )
          .onPressed,
      isNotNull,
    );
    // Same-engine alternatives render but stay disabled…
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const Key('model-picker-qwen35-mlx')),
          )
          .onPressed,
      isNull,
    );
    // …while artifacts this build's engine can never load are hidden
    // outright (#63): no dead multi-gigabyte options.
    expect(find.byKey(const Key('model-picker-qwen35-gguf')), findsNothing);
    expect(find.byKey(const Key('model-picker-gemma4-gguf')), findsNothing);
    expect(find.textContaining('Golem is running Gemma 4 E2B'), findsOneWidget);
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
}

/// A picker that never touches a plugin: it returns a 2x2 PNG, or raises the
/// rejection under test.
final class _StubPicker extends AttachmentPicker {
  const _StubPicker({this.rejection});

  final ImageRejection? rejection;

  @override
  Future<PreparedImage?> pick(AttachSource source) async {
    if (rejection != null) throw ImageRejectedException(rejection!);
    return PreparedImage(
      bytes: tinyPngBytes,
      mimeType: 'image/png',
      width: 2,
      height: 2,
    );
  }
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
