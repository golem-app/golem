/// What a Hugging Face repository turned out to actually contain (#52).
/// `CustomModelSpec` is the user's *request*; this is the answer, pinned to one
/// immutable commit. Kept separate so an unresolved entry stays a first-class
/// state: it still lists, still deletes, and refuses activation.
library;

import 'model_catalog.dart';

final class ResolvedRepository {
  const ResolvedRepository({
    required this.commitSha,
    required this.files,
    required this.quantization,
    this.architecture,
    this.displayName,
  });

  /// The immutable commit the requested ref pointed at. Everything downstream
  /// addresses this, so a moving branch cannot change an installed model.
  final String commitSha;

  /// Exactly the files to fetch — never a whole repository by guesswork.
  final List<ModelArtifactFile> files;

  /// Display label such as `Q4_0` or `4-bit`; never a capability claim.
  final String quantization;

  /// The architecture the artifact declared: `general.architecture` for GGUF,
  /// `model_type` for an MLX snapshot. Recorded for diagnosis; the profile is
  /// decided by the chat-template fingerprint alone.
  final String? architecture;

  final String? displayName;

  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);

  /// Whether the Hub published an authoritative hash for every file. False is
  /// normal — small metadata files are not stored in LFS and carry none.
  bool get fullyHashed => files.every((file) => file.sha256 != null);

  Map<String, Object?> toJson() => {
    'commitSha': commitSha,
    'quantization': quantization,
    if (architecture != null) 'architecture': architecture,
    if (displayName != null) 'displayName': displayName,
    'files': [
      for (final file in files)
        {
          'path': file.path,
          'bytes': file.bytes,
          if (file.sha256 != null) 'sha256': file.sha256,
          if (file.role != ModelFileRole.snapshot) 'role': file.role.name,
        },
    ],
  };

  /// Throws [FormatException] so a corrupt entry drops to unresolved.
  factory ResolvedRepository.fromJson(Map<String, Object?> json) {
    final commitSha = json['commitSha'];
    if (commitSha is! String || commitSha.isEmpty) {
      throw const FormatException('resolved repository needs a commitSha');
    }
    final rawFiles = json['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw const FormatException('resolved repository needs files');
    }
    final files = <ModelArtifactFile>[];
    for (final item in rawFiles) {
      if (item is! Map) {
        throw const FormatException('resolved file must be an object');
      }
      final entry = Map<String, Object?>.from(item);
      final path = entry['path'];
      final bytes = entry['bytes'];
      if (path is! String || path.isEmpty || bytes is! int || bytes < 0) {
        throw const FormatException('resolved file needs a path and bytes');
      }
      final role = entry['role'];
      files.add(
        ModelArtifactFile(
          path: path,
          bytes: bytes,
          sha256: entry['sha256'] as String?,
          role: role is String
              ? ModelFileRole.values.firstWhere(
                  (value) => value.name == role,
                  orElse: () =>
                      throw FormatException('unknown file role "$role"'),
                )
              : ModelFileRole.snapshot,
        ),
      );
    }
    return ResolvedRepository(
      commitSha: commitSha,
      files: files,
      quantization: json['quantization'] as String? ?? 'custom',
      architecture: json['architecture'] as String?,
      displayName: json['displayName'] as String?,
    );
  }
}
