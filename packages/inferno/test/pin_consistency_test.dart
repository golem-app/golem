import 'dart:io';

import 'package:inferno/inferno.dart';
import 'package:test/test.dart';

/// The native pins exist in more than one place by necessity (Dart manifest,
/// build hook, C++/Swift probe strings, SwiftPM lockfile). These tests make
/// the manifest the single source of truth by failing on any drift.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('the build hook downloads the manifest llama.cpp revision', () {
    expect(read('hook/build.dart'), contains(llamaCppRevision));
  });

  test('the llama shim probe reports the manifest release', () {
    expect(
      read('native/src/llama_shim.cpp'),
      contains('llama.cpp $llamaCppRelease'),
    );
  });

  test('the MLX shim probe reports the manifest versions', () {
    final shim = read(
      'native/apple/Sources/InfernoMLXCarrier/InfernoMLXShim.swift',
    );
    expect(shim, contains(mlxSwiftLmVersion));
    expect(shim, contains(mlxSwiftVersion));
  });

  test('the SwiftPM lockfile pins the manifest MLX revisions', () {
    final resolved = read('native/apple/Package.resolved');
    expect(resolved, contains(mlxSwiftLmRevision));
    expect(resolved, contains(mlxSwiftRevision));
  });

  test('the SwiftPM manifest requests the manifest MLX revisions', () {
    // Package.swift drives resolution; the lockfile only records it. Both
    // must carry the pin or a bump to one silently drifts the other.
    final manifest = read('native/apple/Package.swift');
    expect(manifest, contains(mlxSwiftLmRevision));
    expect(manifest, contains(mlxSwiftRevision));
  });
}
