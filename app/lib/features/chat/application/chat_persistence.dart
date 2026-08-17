import '../../../core/domain/app_state.dart';
import '../../../core/domain/models.dart';
import '../../../core/repositories/contracts.dart';
import '../../../core/services/image_intake.dart';

/// What a durable save did, for the notifier to publish as a phase.
enum ChatSaveOutcome { saved, writeFailed }

/// ChatController's history, privacy gate and attachment retention, extracted
/// (#127) so the orchestration is unit-testable without a container — the shape
/// `StorageBreakdownService` already established: collaborators are constructor
/// dependencies, and nothing here touches a Ref.
///
/// The epoch and mounted choreography stays with the notifier. That is state
/// ownership, not persistence: only the controller knows whether a newer
/// attempt has superseded this one.
final class ChatPersistence {
  // Private fields behind public names, as ChatConversation does with its
  // messages: callers still pass `history:` and `attachments:`, but nothing
  // outside can reach past this unit to one of its collaborators.
  const ChatPersistence({required this._history, required this._attachments});

  final ChatHistoryRepository _history;
  final AttachmentRepository _attachments;

  /// Hydration, so every history operation goes through this unit rather than
  /// the controller reaching past it for one of them.
  Future<ChatHistorySnapshot> load() => _history.load();

  /// The newest complete, persistence-eligible view of the live session. A
  /// streaming or failed assistant draft is intentionally absent until Stop or
  /// finalization marks it durable; the user turn and every completed turn
  /// remain included.
  static ChatHistorySnapshot snapshotOf(ChatState value) {
    final active = value.active;
    if (!value.hasUnsavedAssistant ||
        active == null ||
        active.messages.lastOrNull?.role != MessageRole.assistant) {
      return ChatHistorySnapshot(
        conversations: value.conversations,
        activeId: value.activeId,
      );
    }
    final messages = [...active.messages]..removeLast();
    return ChatHistorySnapshot(
      conversations: [
        for (final conversation in value.conversations)
          if (conversation.id == active.id)
            active.copyWith(messages: messages)
          else
            conversation,
      ],
      activeId: value.activeId,
    );
  }

  /// A write failure is reported rather than thrown so the caller can settle
  /// the recovery notice; every other persistence failure is a real fault and
  /// keeps propagating.
  Future<ChatSaveOutcome> save(ChatHistorySnapshot snapshot) async {
    try {
      await _history.save(snapshot);
    } on PersistenceException catch (error) {
      if (error.kind != PersistenceFailureKind.write) rethrow;
      return ChatSaveOutcome.writeFailed;
    }
    return ChatSaveOutcome.saved;
  }

  /// Drops attachment bytes no conversation references. Failures are swallowed:
  /// an orphan costs disk, an aborted send would cost the user their message.
  Future<void> retainReferenced(List<ChatConversation> conversations) async {
    try {
      await _attachments.retainOnly({
        for (final conversation in conversations) ...conversation.attachmentIds,
      });
    } catch (_) {
      // Deliberately broad, not just Exception: this runs from build() and
      // from inside a send, so an Error escaping would error the whole chat
      // state or abort a turn already committed — the exact costs the rule
      // above exists to avoid.
    }
  }

  /// Copies an already-validated image into the store, so the message that
  /// results references ids only and never bytes.
  Future<ImagePart> store(PreparedImage image) async {
    final stored = await _attachments.store(
      image.bytes,
      mimeType: image.mimeType,
    );
    return ImagePart(
      attachmentId: stored.id,
      mimeType: stored.mimeType,
      width: image.width,
      height: image.height,
      byteCount: stored.byteCount,
    );
  }

  /// The disk wipe behind Delete All. Directly, not through [save]: the wipe
  /// must reach disk even when the save-history gate is closed.
  Future<bool> wipe() async {
    try {
      await _history.save(const ChatHistorySnapshot(conversations: []));
    } on Exception {
      return false;
    }
    return true;
  }
}
