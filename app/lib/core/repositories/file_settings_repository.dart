import 'dart:convert';
import 'dart:io';

import '../domain/generation_settings.dart';
import 'contracts.dart';

/// Versioned atomic JSON persistence for user preferences, mirroring
/// FileChatHistoryRepository's write-serialization and corrupt-file
/// recovery.
final class FileSettingsRepository implements SettingsRepository {
  FileSettingsRepository(this.file);
  final File file;
  Future<void> _writes = Future.value();

  @override
  Future<GenerationSettings> load() async {
    if (!await file.exists()) return const GenerationSettings();
    try {
      final value = jsonDecode(await file.readAsString());
      return GenerationSettings.fromJson(
        Map<String, Object?>.from(value as Map),
      );
    } catch (_) {
      // An unreadable or unknown-schema preferences file must not brick
      // startup: preserve it for inspection and fall back to defaults.
      await file.rename('${file.path}.corrupt');
      return const GenerationSettings();
    }
  }

  @override
  Future<void> save(GenerationSettings settings) {
    // Saves are fire-and-forget at call sites, so serialize them: concurrent
    // writes would otherwise race on the shared temporary file and could
    // rename stale content over a newer snapshot.
    final write = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(settings.encode(), flush: true);
      await temporary.rename(file.path);
    });
    _writes = write.catchError((_) {});
    return write;
  }
}
