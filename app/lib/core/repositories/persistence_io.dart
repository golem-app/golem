import 'dart:convert';
import 'dart:io';

import 'contracts.dart';

/// Shared store I/O for the file repositories, structured so the
/// corruption/I-O split is positional rather than an exception-type
/// allowlist: OS-level work translates [FileSystemException] to a typed
/// [PersistenceException], while decode and parse failures are corruption
/// and take the quarantine path.

Future<T> _guardIo<T>(
  Future<T> Function() run, {
  required PersistenceFailureKind kind,
  required String message,
}) async {
  try {
    return await run();
  } on FileSystemException catch (error, stackTrace) {
    Error.throwWithStackTrace(
      PersistenceException(kind, message, cause: error),
      stackTrace,
    );
  }
}

/// Loads a versioned store: absent → [orElse]; unreadable → typed read
/// failure; undecodable or unparsable → quarantined to `.corrupt`, then
/// [onCorrupt], which defaults to [orElse] for a store whose caller need not
/// tell a fresh install from a lost one. The read fetches raw bytes so
/// byte-level corruption (invalid UTF-8) lands on the corruption path —
/// `readAsString` reports a decode failure as [FileSystemException], which
/// would masquerade as I/O and skip the quarantine forever.
Future<T> loadStore<T>(
  File file, {
  required String what,
  required T Function(String raw) decode,
  required T Function() orElse,
  T Function()? onCorrupt,
}) async {
  final bytes = await _guardIo(
    () async => await file.exists() ? file.readAsBytes() : null,
    kind: PersistenceFailureKind.read,
    message: 'Could not read the stored $what.',
  );
  if (bytes == null) return orElse();
  try {
    return decode(utf8.decode(bytes));
  } catch (_) {
    // Only pure decode/parse can throw here — corruption by definition:
    // preserve the file for inspection, fall back to defaults.
    await quarantineStore(file, what: what);
    return (onCorrupt ?? orElse)();
  }
}

/// Preserves a corrupt store beside the live path for inspection. Its own
/// failure is I/O and propagates — a permission problem must not be recorded
/// as successful corruption recovery.
Future<void> quarantineStore(File file, {required String what}) => _guardIo(
  () => file.rename('${file.path}.corrupt'),
  kind: PersistenceFailureKind.read,
  message: 'Could not quarantine the corrupt $what store.',
);

/// The atomic write every store uses: parent directory, `.tmp`, rename.
Future<void> writeStore(File file, String content, {required String what}) =>
    _guardIo(
      () async {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(content, flush: true);
        await temporary.rename(file.path);
      },
      kind: PersistenceFailureKind.write,
      message: 'Could not save the $what.',
    );

/// On-disk size (0 when nothing is stored), classified like any other read.
Future<int> storeBytes(File file, {required String what}) => _guardIo(
  () async => await file.exists() ? file.length() : 0,
  kind: PersistenceFailureKind.read,
  message: 'Could not read the stored $what.',
);
