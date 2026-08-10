import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/chat/application/search_providers.dart';

import 'support/harness.dart';
import 'support/in_memory_chat_history_repository.dart';

/// The #69 lifecycle classification, observably: screen-scoped providers
/// dispose once unwatched (state resets, queries recompute), while a
/// retained listener keeps them alive.
void main() {
  test(
    'SearchQuery survives while listened and resets after disposal',
    () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      var subscription = container.listen(searchQueryProvider, (_, _) {});
      container.read(searchQueryProvider.notifier).publish('  golem  ');
      expect(container.read(searchQueryProvider), 'golem');

      // Still alive across an event-loop flush while the listener holds on.
      await container.pump();
      expect(container.read(searchQueryProvider), 'golem');

      // The last listener leaving disposes it; the next visit starts fresh.
      subscription.close();
      await container.pump();
      subscription = container.listen(searchQueryProvider, (_, _) {});
      addTearDown(subscription.close);
      expect(container.read(searchQueryProvider), '');
    },
  );

  test(
    'chatSearchResults derives while watched and dies with the screen',
    () async {
      final container = buildContainer(history: seedHistory());
      addTearDown(container.dispose);

      final query = container.listen(searchQueryProvider, (_, _) {});
      final results = container.listen(chatSearchResultsProvider, (_, _) {});
      await container.read(chatControllerProvider.future);

      container.read(searchQueryProvider.notifier).publish('weekend');
      await container.pump();
      expect(container.read(chatSearchResultsProvider), isNotEmpty);

      query.close();
      results.close();
      await container.pump();
      // Fresh subscription sees the reset query, so no stale results linger.
      final reopened = container.listen(chatSearchResultsProvider, (_, _) {});
      addTearDown(reopened.close);
      expect(container.read(chatSearchResultsProvider), isEmpty);
    },
  );

  test(
    'storageBreakdown retains its value and recomputes on invalidate',
    () async {
      // KeepAlive by deliberate classification (see the provider comment):
      // staleness is owned by invalidation, never a KeepAliveLink TTL.
      final chatHistory = InMemoryChatHistoryRepository();
      final container = buildContainer(chatHistory: chatHistory);
      addTearDown(container.dispose);

      final subscription = container.listen(
        storageBreakdownProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(storageBreakdownProvider.future);
      final baseline = chatHistory.storedBytesCalls;

      // Retained value: another flush does not recompute.
      await container.pump();
      expect(chatHistory.storedBytesCalls, baseline);

      // The cache-clear path: explicit invalidation recomputes from sources.
      container.invalidate(storageBreakdownProvider);
      await container.read(storageBreakdownProvider.future);
      expect(chatHistory.storedBytesCalls, greaterThan(baseline));
    },
  );

  test('derived catalog providers serve unlistened reads', () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    // ChatController deliberately reads these without watching; a bare read
    // must answer regardless of the providers' lifetime classification.
    expect(container.read(effectiveModelCatalogProvider), isNotEmpty);
    expect(container.read(loadableModelKeysProvider), isA<Set<String>>());
    await container.pump();
    expect(container.read(effectiveModelCatalogProvider), isNotEmpty);
  });
}
