import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/domain/chat_search.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';

/// Full-screen search across every chat. The raw field text is
/// widget-local; a 350 ms debounce publishes the normalized query, and
/// results derive from providers (handbook §23.4).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  // Captured at init because ref is unusable in dispose; the keepAlive
  // notifier outlives this screen.
  late final SearchQuery _query;

  @override
  void initState() {
    super.initState();
    _query = ref.read(searchQueryProvider.notifier);
    // Both in-app exits clear the query before popping, so a fresh visit
    // starts empty; this fallback covers exits that bypass them (the
    // Android system back), accepting one transitional frame there.
    Future.microtask(() {
      if (mounted) _query.publish('');
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _query.publish(text);
    });
  }

  void _cancel() {
    _query.publish('');
    context.pop();
  }

  void _open(String conversationId) async {
    await ref
        .read(chatControllerProvider.notifier)
        .selectConversation(conversationId);
    if (!mounted || !context.mounted) return;
    _query.publish('');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(chatSearchResultsProvider);
    return CupertinoPageScaffold(
      backgroundColor: GolemTheme.canvas,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GolemSpace.gutter,
                GolemSpace.s2,
                GolemSpace.s2,
                GolemSpace.s2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoSearchTextField(
                      key: const Key('search-field'),
                      controller: _controller,
                      autofocus: true,
                      placeholder: 'Search chats',
                      onChanged: _onChanged,
                      onSubmitted: (text) => _query.publish(text),
                    ),
                  ),
                  CupertinoButton(
                    key: const Key('search-cancel'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: GolemSpace.s3,
                    ),
                    minimumSize: const Size(44, 44),
                    onPressed: _cancel,
                    child: Text(
                      'Cancel',
                      style: GolemText.body.copyWith(
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.accent,
                          context,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: query.isEmpty
                  ? const SizedBox.shrink()
                  : results.isEmpty
                  ? Center(
                      child: Text(
                        'No chats match your search.',
                        key: const Key('search-empty'),
                        style: GolemText.footnote.copyWith(
                          color: CupertinoDynamicColor.resolve(
                            GolemTheme.mutedInk,
                            context,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      key: const Key('search-results'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(
                        GolemSpace.gutter,
                        GolemSpace.s2,
                        GolemSpace.gutter,
                        GolemSpace.s6,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 2,
                            bottom: GolemSpace.s2,
                          ),
                          child: Text(
                            '${results.length} '
                            '${results.length == 1 ? 'CHAT' : 'CHATS'}',
                            style: GolemText.overline.copyWith(
                              color: CupertinoDynamicColor.resolve(
                                GolemTheme.mutedInk,
                                context,
                              ),
                            ),
                          ),
                        ),
                        for (final result in results)
                          _ResultCard(result: result, onTap: _open),
                        Padding(
                          padding: const EdgeInsets.only(top: GolemSpace.s4),
                          child: Text(
                            'Search runs against the local database. '
                            'No index is uploaded.',
                            textAlign: TextAlign.center,
                            style: GolemText.caption.copyWith(
                              color: CupertinoDynamicColor.resolve(
                                GolemTheme.tertiaryInk,
                                context,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onTap});
  final ChatSearchResult result;
  final ValueChanged<String> onTap;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _dateLabel(DateTime date, DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    if (!date.isBefore(startOfToday)) return 'Today';
    if (!date.isBefore(startOfToday.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return '${date.day} ${_months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    final highlight = result.matchStart >= 0 && result.matchLength > 0;
    return CupertinoButton(
      key: Key('search-result-${result.conversationId}'),
      padding: EdgeInsets.zero,
      onPressed: () => onTap(result.conversationId),
      child: Container(
        margin: const EdgeInsets.only(bottom: GolemSpace.s3),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
          borderRadius: BorderRadius.circular(GolemRadius.card),
          border: Border.all(
            color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
          ),
          boxShadow: GolemShadow.card(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.title,
              style: GolemText.bodyStrong.copyWith(
                color: CupertinoDynamicColor.resolve(GolemTheme.ink, context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text.rich(
              highlight
                  ? TextSpan(
                      children: [
                        TextSpan(
                          text: result.snippet.substring(0, result.matchStart),
                        ),
                        TextSpan(
                          text: result.snippet.substring(
                            result.matchStart,
                            result.matchStart + result.matchLength,
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: CupertinoDynamicColor.resolve(
                              GolemTheme.accent,
                              context,
                            ),
                            backgroundColor: CupertinoDynamicColor.resolve(
                              GolemTheme.accentSoft,
                              context,
                            ),
                          ),
                        ),
                        TextSpan(
                          text: result.snippet.substring(
                            result.matchStart + result.matchLength,
                          ),
                        ),
                      ],
                    )
                  : TextSpan(text: result.snippet),
              style: GolemText.footnote.copyWith(color: muted),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              '${_dateLabel(result.updatedAt, DateTime.now())} · '
              '${result.matchCount} '
              '${result.matchCount == 1 ? 'match' : 'matches'}',
              style: GolemText.caption.copyWith(
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.tertiaryInk,
                  context,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
