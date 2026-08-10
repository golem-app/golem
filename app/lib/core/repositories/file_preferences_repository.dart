import 'dart:convert';
import 'dart:io';

import '../domain/app_preferences.dart';
import 'contracts.dart';
import 'persistence_io.dart';

/// Versioned atomic JSON persistence for app-wide preferences, mirroring
/// FileSettingsRepository's write-serialization and corrupt-file recovery.
/// Lives in its own file (`flutter-ui-prefs-v1.json`) so the generation
/// settings store and this one can never corrupt each other.
final class FilePreferencesRepository implements PreferencesRepository {
  FilePreferencesRepository(this.file);
  final File file;
  Future<void> _writes = Future.value();

  static const _what = 'preferences';

  @override
  Future<AppPreferences> load() async {
    final raw = await readStore(file, what: _what);
    if (raw == null) return const AppPreferences();
    try {
      return AppPreferences.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      // Only pure decode/parse can throw here, so this is corruption by
      // definition: preserve the file for inspection, fall back to defaults.
      await quarantineStore(file, what: _what);
      return const AppPreferences();
    }
  }

  @override
  Future<void> save(AppPreferences preferences) {
    // Saves are fire-and-forget at call sites, so serialize them: concurrent
    // writes would otherwise race on the shared temporary file and could
    // rename stale content over a newer snapshot.
    final write = _writes.then(
      (_) => writeStore(file, preferences.encode(), what: _what),
    );
    _writes = write.catchError((_) {});
    return write;
  }
}
