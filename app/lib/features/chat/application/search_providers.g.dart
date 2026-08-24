// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The raw field text stays widget-local in the search screen (debounced
/// 350 ms); only the normalized query lands here, so results derive reactively.
/// AutoDispose: screen-scoped — the search screen watches it for its whole
/// life, and disposal on pop resets the query for the next visit.

@ProviderFor(SearchQuery)
final searchQueryProvider = SearchQueryProvider._();

/// The raw field text stays widget-local in the search screen (debounced
/// 350 ms); only the normalized query lands here, so results derive reactively.
/// AutoDispose: screen-scoped — the search screen watches it for its whole
/// life, and disposal on pop resets the query for the next visit.
final class SearchQueryProvider extends $NotifierProvider<SearchQuery, String> {
  /// The raw field text stays widget-local in the search screen (debounced
  /// 350 ms); only the normalized query lands here, so results derive reactively.
  /// AutoDispose: screen-scoped — the search screen watches it for its whole
  /// life, and disposal on pop resets the query for the next visit.
  SearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'searchQueryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchQueryHash();

  @$internal
  @override
  SearchQuery create() => SearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$searchQueryHash() => r'b66c0cf584e4aa1d4971c87c725f89c4a7cda04a';

/// The raw field text stays widget-local in the search screen (debounced
/// 350 ms); only the normalized query lands here, so results derive reactively.
/// AutoDispose: screen-scoped — the search screen watches it for its whole
/// life, and disposal on pop resets the query for the next visit.

abstract class _$SearchQuery extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// AutoDispose: derives from the query and lives exactly as long as the
/// search screen watches it.

@ProviderFor(chatSearchResults)
final chatSearchResultsProvider = ChatSearchResultsProvider._();

/// AutoDispose: derives from the query and lives exactly as long as the
/// search screen watches it.

final class ChatSearchResultsProvider
    extends
        $FunctionalProvider<
          List<ChatSearchResult>,
          List<ChatSearchResult>,
          List<ChatSearchResult>
        >
    with $Provider<List<ChatSearchResult>> {
  /// AutoDispose: derives from the query and lives exactly as long as the
  /// search screen watches it.
  ChatSearchResultsProvider._()
    : super(
        from: null,
        argument: null,
        retry: noRetry,
        name: r'chatSearchResultsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatSearchResultsHash();

  @$internal
  @override
  $ProviderElement<List<ChatSearchResult>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<ChatSearchResult> create(Ref ref) {
    return chatSearchResults(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ChatSearchResult> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ChatSearchResult>>(value),
    );
  }
}

String _$chatSearchResultsHash() => r'728143a70700911ba5fc875b23e66f1fcee101ef';
