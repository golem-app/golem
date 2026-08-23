import '../../../core/domain/app_state.dart';
import '../../../core/domain/models.dart';

/// The pure half of ChatController's conversation commands (#127). Each of
/// these was inline in the notifier, reachable only by driving a container; the
/// rules they carry — which chat becomes active after a delete, what a recovery
/// action removes, what an edit truncates — are decisions worth naming.
///
/// The two shapes are deliberately different. [withActiveConversation] copies
/// the state, so a standing failure and the unsaved-assistant flag survive;
/// [withNewConversation] and [withoutConversation] build a fresh one, which
/// clears both — a chat the user just created or deleted carries no verdict
/// from the turn before it.

/// [conversation] moves to the front and becomes active, keeping everything
/// else about the session.
ChatState withActiveConversation(
  ChatState value,
  ChatConversation conversation,
) => value.copyWith(
  conversations: [
    conversation,
    for (final item in value.conversations)
      if (item.id != conversation.id) item,
  ],
  activeId: conversation.id,
);

/// A newly created or branched chat, at the front and active.
ChatState withNewConversation(ChatState value, ChatConversation conversation) =>
    ChatState(
      conversations: [conversation, ...value.conversations],
      activeId: conversation.id,
      persistencePhase: value.persistencePhase,
      historyRecovered: value.historyRecovered,
    );

/// Removing the active chat falls through to whatever is now first, which is
/// the most recently touched one; removing any other leaves the selection be.
ChatState withoutConversation(ChatState value, String id) {
  final remaining = value.conversations
      .where((item) => item.id != id)
      .toList(growable: false);
  return ChatState(
    conversations: remaining,
    activeId: value.activeId == id ? remaining.firstOrNull?.id : value.activeId,
    persistencePhase: value.persistencePhase,
    historyRecovered: value.historyRecovered,
  );
}

/// [edit] applied to [id] in place — order and selection are untouched, which
/// is what keeps metadata-only changes safe while a generation streams.
ChatState withEditedConversation(
  ChatState value,
  String id,
  ChatConversation Function(ChatConversation) edit,
) => value.copyWith(
  conversations: [
    for (final item in value.conversations)
      if (item.id == id) edit(item) else item,
  ],
);

/// The shared shape of the three recovery actions. The failed assistant draft
/// always goes; [alsoUser] additionally drops the user turn beneath it, for the
/// turns that deterministically cannot be replayed — one whose attachment
/// disappeared, say. Ordinary Discard keeps the user's message.
ChatConversation withTrailingTurnsDropped(
  ChatConversation conversation, {
  bool alsoUser = false,
}) {
  final messages = [...conversation.messages];
  if (messages.lastOrNull?.role == MessageRole.assistant) {
    messages.removeLast();
  }
  if (alsoUser && messages.lastOrNull?.role == MessageRole.user) {
    messages.removeLast();
  }
  return conversation.copyWith(messages: messages);
}

/// The conversation after the user rewrites [messageId] and everything after it
/// is dropped, or null when [messageId] is not a user turn of this chat.
///
/// [ChatMessage.withText] rather than a fresh text message: a re-run of an
/// image turn is still an image turn, and dropping the part would unlink its
/// bytes on the next save. Editing the first turn renames the chat with it.
ChatConversation? withEditedAndTruncated(
  ChatConversation conversation,
  String messageId,
  String text, {
  required DateTime now,
}) {
  final index = conversation.messages.indexWhere(
    (item) => item.id == messageId,
  );
  if (index < 0 || conversation.messages[index].role != MessageRole.user) {
    return null;
  }
  return conversation.copyWith(
    messages: [
      ...conversation.messages.take(index),
      conversation.messages[index].withText(text),
    ],
    title: index == 0 ? normalizeTitle(text) : conversation.title,
    updatedAt: now,
  );
}

/// The streaming draft settled: no longer streaming, and dropped entirely when
/// it never produced anything a user would want to keep.
ChatConversation withStreamingSettled(ChatConversation conversation) {
  final messages = [...conversation.messages];
  if (messages.isEmpty || !messages.last.isStreaming) return conversation;
  if (messages.last.text.isEmpty &&
      (messages.last.reasoning?.isEmpty ?? true)) {
    messages.removeLast();
  } else {
    messages[messages.length - 1] = messages.last.copyWith(isStreaming: false);
  }
  return conversation.copyWith(messages: messages);
}
