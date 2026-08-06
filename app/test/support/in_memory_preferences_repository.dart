import 'package:golem_flutter/core/domain/app_preferences.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

final class InMemoryPreferencesRepository implements PreferencesRepository {
  InMemoryPreferencesRepository([this.preferences = const AppPreferences()]);
  AppPreferences preferences;
  int saves = 0;

  @override
  Future<AppPreferences> load() async => preferences;

  @override
  Future<void> save(AppPreferences value) async {
    preferences = value;
    saves += 1;
  }
}
