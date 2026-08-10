import 'package:golem_flutter/core/repositories/contracts.dart';

/// Deterministic in-memory attachment store.
///
/// Preserves the real contract's observable behavior: ids are unique and
/// opaque, unsupported types are refused, a missing attachment reads as null,
/// and [retainOnly] is the only thing that removes bytes.
final class InMemoryAttachmentRepository implements AttachmentRepository {
  final Map<String, List<int>> items = {};
  final Map<String, String> mimeTypes = {};

  /// Every id ever handed out, so a test can assert what was collected.
  final List<String> issued = [];

  int _next = 0;

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
    final id = 'attachment-${_next++}.$extension';
    items[id] = List<int>.unmodifiable(bytes);
    mimeTypes[id] = mimeType;
    issued.add(id);
    return StoredAttachment(
      id: id,
      mimeType: mimeType,
      byteCount: bytes.length,
    );
  }

  @override
  Future<List<int>?> read(String attachmentId) async => items[attachmentId];

  @override
  Future<void> retainOnly(Set<String> attachmentIds) async {
    items.removeWhere((id, _) => !attachmentIds.contains(id));
    mimeTypes.removeWhere((id, _) => !attachmentIds.contains(id));
  }

  @override
  Future<int> storedBytes() async =>
      items.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
}
