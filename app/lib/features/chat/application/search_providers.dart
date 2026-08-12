import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/retry.dart';
import '../domain/chat_search.dart';
import 'chat_providers.dart';

part 'search_providers.g.dart';

/// The raw field text stays widget-local in the search screen (debounced
/// 350 ms); only the normalized query lands here, so results derive reactively.
/// AutoDispose: screen-scoped — the search screen watches it for its whole
/// life, and disposal on pop resets the query for the next visit.
@Riverpod(retry: noRetry)
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void publish(String raw) => state = raw.trim();
}

/// AutoDispose: derives from the query and lives exactly as long as the
/// search screen watches it.
@Riverpod(retry: noRetry)
List<ChatSearchResult> chatSearchResults(Ref ref) {
  final query = ref.watch(searchQueryProvider);
  final conversations = ref.watch(chatControllerProvider).value?.conversations;
  return searchConversations(conversations ?? const [], query);
}
