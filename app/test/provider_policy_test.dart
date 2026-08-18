import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ProviderOrFamily is exported only by the secondary misc.dart entrypoint.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/providers/retry.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/features/benchmark/application/benchmark_providers.dart';
import 'package:golem_flutter/features/chat/application/chat_providers.dart';
import 'package:golem_flutter/features/chat/application/search_providers.dart';
import 'package:golem_flutter/features/models/application/download_note_providers.dart';
import 'package:golem_flutter/features/models/application/download_pace_providers.dart';
import 'package:golem_flutter/features/models/application/model_providers.dart';
import 'package:golem_flutter/features/onboarding/application/onboarding_controller.dart';
import 'package:golem_flutter/features/onboarding/application/startup_gate_controller.dart';
import 'package:golem_flutter/features/preferences/application/preferences_providers.dart';
import 'package:golem_flutter/features/preferences/application/generation_settings_providers.dart';
import 'package:golem_flutter/features/settings/application/storage_providers.dart';
import 'package:golem_flutter/features/splash/application/startup_providers.dart';

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
  'deviceRefusal': deviceRefusalProvider,
  'inferenceResidency': inferenceResidencyProvider,
  'residentModelKey': residentModelKeyProvider,
  'chatSessionBridge': chatSessionBridgeProvider,
  'modelSessionBridge': modelSessionBridgeProvider,
  'deviceCapacityProbe': deviceCapacityProbeProvider,
  'documentsPath': documentsPathProvider,
  'chatStorageSignature': chatStorageSignatureProvider,
  'storageBreakdown': storageBreakdownProvider,
  'effectiveModelCatalog': effectiveModelCatalogProvider,
  'loadableModelKeys': loadableModelKeysProvider,
  'startupModelKey': startupModelKeyProvider,
  'downloadableModelKeys': downloadableModelKeysProvider,
  'paceClock': paceClockProvider,
  'downloadPace': downloadPaceProvider,
  'downloadNoteDismissal': downloadNoteDismissalProvider,
  'downloadNoteFigures': downloadNoteFiguresProvider,
  'downloadNoteVisible': downloadNoteVisibleProvider,
  'searchQuery': searchQueryProvider,
  'chatSearchResults': chatSearchResultsProvider,
  'settingsController': settingsControllerProvider,
  'preferencesController': preferencesControllerProvider,
  'chatController': chatControllerProvider,
  'modelController': modelControllerProvider,
  'startupController': startupControllerProvider,
  'benchmarkController': benchmarkControllerProvider,
  'firstRunController': firstRunControllerProvider,
  'startupGateController': startupGateControllerProvider,
};

final class _FailingSettingsRepository implements SettingsRepository {
  @override
  Future<GenerationSettings> load() async =>
      throw Exception('injected read failure');

  @override
  Future<void> save(GenerationSettings settings) async {}
}

void main() {
  test('the registry names every generated provider', () {
    // The registry above is hand-maintained and has rotted before (#88 had
    // to add three providers that already existed). This scan keeps it
    // complete: every @ProviderFor in a committed .g.dart must appear.
    final generated = <String>{};
    final pattern = RegExp(r'@ProviderFor\((\w+)\)');
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.g.dart'));
    for (final file in files) {
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        final name = match.group(1)!;
        generated.add(name[0].toLowerCase() + name.substring(1));
      }
    }
    expect(generated, isNotEmpty, reason: 'run from app/ so lib/ is visible');
    expect(
      generated.difference(_allProviders.keys.toSet()),
      isEmpty,
      reason:
          'add the missing provider(s) to _allProviders with retry: noRetry',
    );
  });

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
