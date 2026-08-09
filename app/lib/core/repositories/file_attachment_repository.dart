import 'dart:io';

import '../domain/models.dart' show newId;
import 'contracts.dart';

/// Attachments on disk, one file per image, under a directory this app owns.
/// Deliberately *not* excluded from backup, unlike model weights: a model is
/// re-fetchable from Hugging Face, a user's photo is not.
final class FileAttachmentRepository implements AttachmentRepository {
  FileAttachmentRepository(this.directory);

  final Directory directory;

  /// Serialized so a save and a cascade delete cannot interleave.
  Future<void> _writes = Future.value();

  static const _extensions = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/heic': 'heic',
  };

  @override
  Future<StoredAttachment> store(
    List<int> bytes, {
    required String mimeType,
  }) async {
    final extension = _extensions[mimeType];
    if (extension == null) {
      throw ArgumentError.value(mimeType, 'mimeType', 'Unsupported image type');
    }
    final id = '${newId()}.$extension';
    final write = _writes.then((_) async {
      await directory.create(recursive: true);
      final temporary = File('${directory.path}/$id.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename('${directory.path}/$id');
    });
    _writes = write.catchError((_) {});
    await write;
    return StoredAttachment(
      id: id,
      mimeType: mimeType,
      byteCount: bytes.length,
    );
  }

  @override
  Future<List<int>?> read(String attachmentId) async {
    final file = _resolve(attachmentId);
    if (file == null || !await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> retainOnly(Set<String> attachmentIds) {
    final write = _writes.then((_) async {
      if (!await directory.exists()) return;
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        // A crashed write leaves a .tmp behind; it is never referenced.
        if (attachmentIds.contains(name) && !name.endsWith('.tmp')) continue;
        try {
          await entity.delete();
        } on FileSystemException {
          // A file that cannot be removed must not abort the cascade.
        }
      }
    });
    _writes = write.catchError((_) {});
    return write;
  }

  @override
  Future<int> storedBytes() async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } on FileSystemException {
        // Skip anything that vanished mid-walk.
      }
    }
    return total;
  }

  /// An id addresses one file here; one trying to escape is treated as missing.
  File? _resolve(String attachmentId) {
    if (attachmentId.isEmpty ||
        attachmentId.contains('/') ||
        attachmentId.contains(r'\') ||
        attachmentId.contains('..')) {
      return null;
    }
    return File('${directory.path}/$attachmentId');
  }
}
