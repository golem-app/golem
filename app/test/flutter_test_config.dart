import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Goldens are rendered and verified on macOS. Linux rasterizes text
/// differently (0.7–4% pixel drift across every snapshot), so a strict
/// comparison there only measures the font stack; other hosts skip the
/// pixel check while CI's macOS job keeps goldens fully enforced.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (!Platform.isMacOS) {
    goldenFileComparator = _SkipGoldenComparator();
  }
  await testMain();
}

class _SkipGoldenComparator extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async => true;

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {}
}
