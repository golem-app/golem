import 'dart:convert';
import 'dart:io';

import '../domain/app_preferences.dart';
import 'contracts.dart';

/// Versioned atomic JSON persistence for app-wide preferences, mirroring
/// FileSettingsRepository's write-serialization and corrupt-file recovery.
/// Lives in its own file (`flutter-ui-prefs-v1.json`) so the generation
/// settings store and this one can never corrupt each other.
final class FilePreferencesRepository implements PreferencesRepository {
  FilePreferencesRepository(this.file);
  final File file;
  Future<void> _writes = Future.value();

  @override
  Future<AppPreferences> load() async {
    if (!await file.exists()) return const AppPreferences();
    try {
      final value = jsonDecode(await file.readAsString());
      return AppPreferences.fromJson(Map<String, Object?>.from(value as Map));
    } catch (_) {
      // An unreadable or unknown-schema preferences file must not brick
      // startup: preserve it for inspection and fall back to defaults.
      await file.rename('${file.path}.corrupt');
      return const AppPreferences();
    }
  }

  @override
  Future<void> save(AppPreferences preferences) {
    // Saves are fire-and-forget at call sites, so serialize them: concurrent
    // writes would otherwise race on the shared temporary file and could
    // rename stale content over a newer snapshot.
    final write = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(preferences.encode(), flush: true);
      await temporary.rename(file.path);
    });
    _writes = write.catchError((_) {});
    return write;
  }
}
