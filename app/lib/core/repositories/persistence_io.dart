import 'dart:io';

import 'contracts.dart';

/// Shared store I/O for the file repositories, structured so the
/// corruption/I-O split is positional rather than an exception-type allowlist:
/// everything here is I/O and translates [FileSystemException] to a typed
/// [PersistenceException]; only pure decode/parse belongs inside a caller's
/// corruption `catch`.

/// The store's content, or null when no store exists yet.
Future<String?> readStore(File file, {required String what}) async {
  try {
    if (!await file.exists()) return null;
    return await file.readAsString();
  } on FileSystemException catch (error, stackTrace) {
    Error.throwWithStackTrace(
      PersistenceException(
        PersistenceFailureKind.read,
        'Could not read the stored $what.',
        cause: error,
      ),
      stackTrace,
    );
  }
}

/// Preserves a corrupt store beside the live path for inspection. Its own
/// failure is I/O and propagates — a permission problem must not be recorded
/// as successful corruption recovery.
Future<void> quarantineStore(File file, {required String what}) async {
  try {
    await file.rename('${file.path}.corrupt');
  } on FileSystemException catch (error, stackTrace) {
    Error.throwWithStackTrace(
      PersistenceException(
        PersistenceFailureKind.read,
        'Could not read the stored $what.',
        cause: error,
      ),
      stackTrace,
    );
  }
}

/// The atomic write every store uses: parent directory, `.tmp`, rename.
Future<void> writeStore(
  File file,
  String content, {
  required String what,
}) async {
  try {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
  } on FileSystemException catch (error, stackTrace) {
    Error.throwWithStackTrace(
      PersistenceException(
        PersistenceFailureKind.write,
        'Could not save the $what.',
        cause: error,
      ),
      stackTrace,
    );
  }
}
