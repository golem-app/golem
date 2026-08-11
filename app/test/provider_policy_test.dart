import 'package:flutter_riverpod/flutter_riverpod.dart';
// ProviderOrFamily is exported only by the secondary misc.dart entrypoint.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/benchmark/application/benchmark_providers.dart';
import 'package:golem_flutter/features/chat/application/search_providers.dart';
import 'package:golem_flutter/core/providers/retry.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

/// Every generated provider, so a new annotation missing `retry: noRetry`
/// fails here instead of silently inheriting the ten-retry default.
final _allProviders = <String, ProviderOrFamily>{
  'chatHistoryRepository': chatHistoryRepositoryProvider,
  'inferenceRepository': inferenceRepositoryProvider,
  'modelManagementRepository': modelManagementRepositoryProvider,
  'benchmarkRepository': benchmarkRepositoryProvider,
  'modelCatalogEntries': modelCatalogEntriesProvider,
  'customRepositoryResolver': customRepositoryResolverProvider,
  'settingsRepository': settingsRepositoryProvider,
  'preferencesRepository': preferencesRepositoryProvider,
  'attachmentRepository': attachmentRepositoryProvider,
  'cacheProbe': cacheProbeProvider,
  'diskFreeSpaceProbe': diskFreeSpaceProbeProvider,
  'inferenceBackend': inferenceBackendProvider,
  'deviceEligibility': deviceEligibilityProvider,
  'residentModelKey': residentModelKeyProvider,
  'deviceCapacityProbe': deviceCapacityProbeProvider,
  'documentsPath': documentsPathProvider,
  'chatStorageSignature': chatStorageSignatureProvider,
  'storageBreakdown': storageBreakdownProvider,
  'effectiveModelCatalog': effectiveModelCatalogProvider,
  'loadableModelKeys': loadableModelKeysProvider,
  'searchQuery': searchQueryProvider,
  'chatSearchResults': chatSearchResultsProvider,
  'settingsController': settingsControllerProvider,
  'preferencesController': preferencesControllerProvider,
  'chatController': chatControllerProvider,
  'modelController': modelControllerProvider,
  'startupController': startupControllerProvider,
  'benchmarkController': benchmarkControllerProvider,
};

final class _FailingSettingsRepository implements SettingsRepository {
  @override
  Future<GenerationSettings> load() async =>
      throw Exception('injected read failure');

  @override
  Future<void> save(GenerationSettings settings) async {}
}

void main() {
  test('every provider declares the project no-retry policy', () {
    for (final entry in _allProviders.entries) {
      expect(
        entry.value.retry,
        same(noRetry),
        reason:
            '${entry.key}Provider must declare retry: noRetry '
            '(handbook v5.0 §4.5) instead of inheriting defaultRetry.',
      );
    }
  });

  test(
    'a failing build surfaces at once instead of retrying for ~38 s',
    () async {
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FailingSettingsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        settingsControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await expectLater(
        container.read(settingsControllerProvider.future),
        throwsA(isA<Exception>()),
      );
      final value = container.read(settingsControllerProvider);
      // Under defaultRetry this state would be AsyncLoading(retrying: true) —
      // hasError and isLoading both true — for the whole backoff schedule.
      expect(value.hasError, isTrue);
      expect(value.isLoading, isFalse);
    },
  );
}
