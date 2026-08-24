import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

final class InMemoryPreferencesRepository implements PreferencesRepository {
  InMemoryPreferencesRepository([this.preferences = const AppPreferences()]);
  AppPreferences preferences;
  int saves = 0;

  /// While > 0, each save throws a typed write failure and decrements —
  /// the fault-injection hook for rollback tests.
  int failingSaves = 0;

  /// While > 0, each load throws a typed read failure and decrements.
  int failingLoads = 0;

  @override
  Future<AppPreferences> load() async {
    if (failingLoads > 0) {
      failingLoads--;
      throw const PersistenceException(
        PersistenceFailureKind.read,
        'Could not read the stored preferences.',
      );
    }
    return preferences;
  }

  @override
  Future<void> save(AppPreferences value) async {
    if (failingSaves > 0) {
      failingSaves--;
      throw const PersistenceException(
        PersistenceFailureKind.write,
        'Could not save the preferences.',
      );
    }
    preferences = value;
    saves += 1;
  }
}
