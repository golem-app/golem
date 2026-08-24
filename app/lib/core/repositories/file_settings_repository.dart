import 'dart:convert';
import 'dart:io';

import '../domain/generation_settings.dart';
import 'contracts.dart';
import 'persistence_io.dart';

/// Versioned atomic JSON persistence for user preferences, mirroring
/// FileChatHistoryRepository's write-serialization and corrupt-file
/// recovery. Store I/O failures throw [PersistenceException]; only a store
/// that reads but does not parse is quarantined and defaulted.
final class FileSettingsRepository implements SettingsRepository {
  FileSettingsRepository(this.file);
  final File file;
  Future<void> _writes = Future.value();

  static const _what = 'generation settings';

  @override
  Future<GenerationSettings> load() => loadStore(
    file,
    what: _what,
    decode: (raw) => GenerationSettings.fromJson(
      Map<String, Object?>.from(jsonDecode(raw) as Map),
    ),
    orElse: () => const GenerationSettings(),
  );

  @override
  Future<void> save(GenerationSettings settings) {
    // Saves are fire-and-forget at call sites, so serialize them: concurrent
    // writes would otherwise race on the shared temporary file and could
    // rename stale content over a newer snapshot.
    final write = _writes.then(
      (_) => writeStore(file, settings.encode(), what: _what),
    );
    _writes = write.catchError((_) {});
    return write;
  }
}
