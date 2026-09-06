import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/services/artifact_task_metadata.dart';

/// The recognition rule the downloader adapter runs on.
///
/// Nothing else could reach it: `BackgroundArtifactDownloader` talks to a
/// static `FileDownloader` over a platform channel, so the whole adapter sits
/// at 5% coverage and this rule — the one part of it that decides anything —
/// was inside that shadow.
void main() {
  const ref = ArtifactFileRef(
    artifactKey: 'qwen35-2b-gguf',
    sourceUrl: 'https://huggingface.co/org/repo/resolve/deadbeef/model.gguf',
    directory: 'models/qwen35-2b-gguf',
    filename: 'model.gguf',
    expectedBytes: 1234,
  );

  test('the destination pair follows the root and its subdirectory', () {
    // The phones: the artifact's own directory under documents.
    expect(
      artifactTaskDestination(ref: ref, root: 'documents', subdirectory: ''),
      (base: 'documents', directory: 'models/qwen35-2b-gguf'),
    );
    // The lab: under application support, inside its own Documents (ADR
    // 0021) — the pair every downloader, bench harness included, builds
    // its tasks from, so the plugin lands files where the repository looks.
    expect(
      artifactTaskDestination(
        ref: ref,
        root: 'applicationSupport',
        subdirectory: 'Documents',
      ),
      (
        base: 'applicationSupport',
        directory: 'Documents/models/qwen35-2b-gguf',
      ),
    );
  });

  test('a transfer carries its key, destination and source', () {
    final meta = jsonDecode(artifactTaskMetadata(ref)) as Map<String, Object?>;

    expect(meta, {
      'key': 'qwen35-2b-gguf',
      'path': 'models/qwen35-2b-gguf/model.gguf',
      'url': ref.sourceUrl,
    });
  });

  test('the destination reads back out', () {
    expect(
      artifactDestinationIn(artifactTaskMetadata(ref)),
      'models/qwen35-2b-gguf/model.gguf',
    );
  });

  test('its own metadata matches it', () {
    expect(artifactTaskMetadataMatches(artifactTaskMetadata(ref), ref), isTrue);
  });

  // The rule this exists for: the install directory is keyed by artifact, not
  // by commit, so a re-pinned entry has the identical destination. Matching on
  // that alone would adopt the previous commit's bytes and then fail them
  // against the new hash.
  test('the same destination from another commit is not this transfer', () {
    const repinned = ArtifactFileRef(
      artifactKey: 'qwen35-2b-gguf',
      sourceUrl: 'https://huggingface.co/org/repo/resolve/feedface/model.gguf',
      directory: 'models/qwen35-2b-gguf',
      filename: 'model.gguf',
      expectedBytes: 1234,
    );

    expect(repinned.destination, ref.destination);
    expect(
      artifactTaskMetadataMatches(artifactTaskMetadata(ref), repinned),
      isFalse,
    );
  });

  test('the same source to another destination is not this transfer', () {
    final elsewhere = ArtifactFileRef(
      artifactKey: 'qwen35-2b-gguf',
      sourceUrl: ref.sourceUrl,
      directory: 'models/other',
      filename: 'model.gguf',
      expectedBytes: 1234,
    );

    expect(
      artifactTaskMetadataMatches(artifactTaskMetadata(ref), elsewhere),
      isFalse,
    );
  });

  // The plugin hands back records written by earlier versions of this app; one
  // unreadable record must not take down a sweep over all of them.
  group('a record this app cannot read', () {
    for (final metaData in ['', 'not json', '[]', '{}', '{"path": 7}']) {
      test('${metaData.isEmpty ? '<empty>' : metaData} is nobody\'s', () {
        expect(artifactTaskMetadataMatches(metaData, ref), isFalse);
        expect(artifactDestinationIn(metaData), isNull);
      });
    }
  });
}
