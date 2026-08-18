import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/chrome/golem_tappable.dart';
import '../../core/theme/golem_theme.dart';
import '../../l10n/bidi.dart';
import '../../l10n/l10n.dart';
import 'application/chat_providers.dart';
import 'application/search_providers.dart';
import 'dart:async';
import 'domain/chat_search.dart';

/// Full-screen search across every chat. The raw field text is
/// widget-local; a 350 ms debounce publishes the normalized query, and
/// results derive from providers (handbook v5.0 §7.3).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  // Captured at init because ref is unusable in dispose. The notifier is
  // autoDispose and lives exactly as long as this screen watches it; every
  // publish below runs while mounted, and disposal itself now provides the
  // fresh-visit reset the manual clears used to guarantee alone.
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
              padding: const EdgeInsetsDirectional.fromSTEB(
                GolemSpace.gutter,
                GolemSpace.s2,
                GolemSpace.s2,
                GolemSpace.s2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) => CupertinoTextField(
                        key: const Key('search-field'),
                        controller: _controller,
                        textDirection: contentTextDirection(
                          value.text,
                          fallback: Directionality.of(context),
                        ),
                        autofocus: true,
                        placeholder: context.l10n.searchChats,
                        textInputAction: TextInputAction.search,
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          5.5,
                          8,
                          5.5,
                          8,
                        ),
                        prefix: const Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(6, 8, 0, 8),
                          child: Icon(
                            CupertinoIcons.search,
                            key: Key('search-prefix'),
                            size: 20,
                            color: CupertinoColors.secondaryLabel,
                          ),
                        ),
                        clearButtonMode: OverlayVisibilityMode.editing,
                        clearButtonSemanticLabel: CupertinoLocalizations.of(
                          context,
                        ).clearButtonLabel,
                        decoration: BoxDecoration(
                          color: CupertinoColors.tertiarySystemFill,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        onChanged: _onChanged,
                        onSubmitted: (text) => _query.publish(text),
                      ),
                    ),
                  ),
                  GolemTappable(
                    key: const Key('search-cancel'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: GolemSpace.s3,
                    ),
                    onPressed: _cancel,
                    child: Text(
                      context.l10n.cancel,
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
                        context.l10n.noChatsMatchSearch,
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
                          padding: const EdgeInsetsDirectional.only(
                            start: 2,
                            bottom: GolemSpace.s2,
                          ),
                          child: Text(
                            context.l10n.searchResultCount(results.length),
                            style:
                                localizedLabelStyle(
                                  GolemText.overline,
                                  Localizations.localeOf(context),
                                ).copyWith(
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
                            context.l10n.localSearchPrivacy,
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

  String _dateLabel(BuildContext context, DateTime date, DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    if (!date.isBefore(startOfToday)) return context.l10n.today;
    if (!date.isBefore(startOfToday.subtract(const Duration(days: 1)))) {
      return context.l10n.yesterday;
    }
    return DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(date);
  }

  @override
  Widget build(BuildContext context) {
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    final highlight = result.matchStart >= 0 && result.matchLength > 0;
    return GolemTappable(
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
              textDirection: contentTextDirection(
                result.title,
                fallback: Directionality.of(context),
              ),
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
              textDirection: contentTextDirection(
                result.snippet,
                fallback: Directionality.of(context),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.searchMatchSummary(
                _dateLabel(context, result.updatedAt, DateTime.now()),
                result.matchCount,
              ),
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
