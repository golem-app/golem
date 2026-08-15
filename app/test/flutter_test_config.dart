import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Goldens are rendered and verified on macOS. Linux rasterizes text
/// differently (0.7–4% pixel drift across every snapshot), so a strict
/// comparison there only measures the font stack; other hosts skip the
/// pixel check while CI's macOS job keeps goldens fully enforced.
///
/// Set `GOLEM_GOLDEN_MANIFEST` to have every compared golden appended to that
/// file. Golden names are interpolated (`'goldens/chat-light${chromeSuffix()}'`),
/// so running the suite is the only way to learn which files a run reaches —
/// which is what `tool/check_goldens.dart` needs to find orphans.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (!Platform.isMacOS) {
    goldenFileComparator = _SkipGoldenComparator();
  }
  final manifest = Platform.environment['GOLEM_GOLDEN_MANIFEST'];
  if (manifest != null && manifest.isNotEmpty) {
    goldenFileComparator = _RecordingGoldenComparator(
      goldenFileComparator,
      File(manifest),
    );
  }
  await testMain();
}

class _SkipGoldenComparator extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {}
}

/// Delegates every decision and records the name on the way through, so the
/// manifest is identical whether the run compares, skips, or updates.
class _RecordingGoldenComparator extends GoldenFileComparator {
  _RecordingGoldenComparator(this._inner, this._manifest);

  final GoldenFileComparator _inner;
  final File _manifest;
  final Set<String> _seen = {};

  void _record(Uri golden) {
    // Each test file is its own process appending to one manifest; deduping
    // here keeps every write short enough for O_APPEND to stay atomic.
    if (_seen.add(golden.path)) {
      _manifest.writeAsStringSync(
        '${golden.path}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) {
    _record(golden);
    return _inner.compare(imageBytes, golden);
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) {
    _record(golden);
    return _inner.update(golden, imageBytes);
  }

  @override
  Uri getTestUri(Uri key, int? version) => _inner.getTestUri(key, version);
}
