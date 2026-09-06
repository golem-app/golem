/// What a transfer carries about itself, and how a held task is recognized.
///
/// Split out of `artifact_downloader.dart` because it is the one part of that
/// adapter with no plugin in it: the downloader reaches a static
/// `FileDownloader` over a platform channel, so nothing there can be exercised
/// off a device, while the rule below decides correctness on its own.
library;

import 'dart:convert';

/// Identifies one artifact file's transfer, in app terms only.
///
/// Deliberately carries no task id: the plugin's identifiers are an adapter
/// concern, and a stable one would be actively harmful. [sourceUrl] is the
/// resolved `resolve/<revision>/` URL, which already accounts for a file's
/// per-file repository and revision overrides, so it identifies both the bytes
/// wanted and the commit they come from.
final class ArtifactFileRef {
  const ArtifactFileRef({
    required this.artifactKey,
    required this.sourceUrl,
    required this.directory,
    required this.filename,
    required this.expectedBytes,
  });

  final String artifactKey;
  final String sourceUrl;

  /// Relative to the app documents directory.
  final String directory;
  final String filename;
  final int expectedBytes;

  String get destination => '$directory/$filename';
}

/// What travels with the platform's task so a later run can recognize it.
String artifactTaskMetadata(ArtifactFileRef ref) => jsonEncode({
  'key': ref.artifactKey,
  'path': ref.destination,
  'url': ref.sourceUrl,
});

/// The destination [metaData] names, or null when it is not ours to read.
///
/// Never throws: the plugin hands back records written by earlier versions of
/// this app, and one unreadable record must not take down a sweep over all of
/// them.
String? artifactDestinationIn(String metaData) {
  try {
    return (jsonDecode(metaData) as Map<String, Object?>)['path'] as String?;
  } catch (_) {
    return null;
  }
}

/// Whether [metaData] describes this exact transfer — destination *and* source.
///
/// The install directory is keyed by artifact, not by commit, so the
/// destination alone is identical across revisions; matching on it would let a
/// re-pinned entry adopt a transfer of the previous commit's bytes and then
/// fail them against the new hash.
bool artifactTaskMetadataMatches(String metaData, ArtifactFileRef ref) {
  try {
    final meta = jsonDecode(metaData) as Map<String, Object?>;
    return meta['path'] == ref.destination && meta['url'] == ref.sourceUrl;
  } catch (_) {
    return false;
  }
}

/// Where a transfer lands, as the plugin's own `(baseDirectory, directory)`
/// pair: every downloader builds its tasks from this so the destination the
/// plugin resolves is the one the repository verifies (ADR 0021). `root`
/// names the plugin base directory; `subdirectory` prefixes the artifact's
/// own directory under it, empty on the phones and `Documents` for the lab.
({String base, String directory}) artifactTaskDestination({
  required ArtifactFileRef ref,
  required String root,
  required String subdirectory,
}) => (
  base: root,
  directory: subdirectory.isEmpty
      ? ref.directory
      : '$subdirectory/${ref.directory}',
);
