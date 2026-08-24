import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/services/image_intake.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('canonicalizes orientation and strips source metadata', (
    tester,
  ) async {
    final source = img.Image(width: 2, height: 1)
      ..setPixelRgba(0, 0, 255, 0, 0, 255)
      ..setPixelRgba(1, 0, 0, 0, 255, 255)
      ..exif.imageIfd.orientation = 6;

    final prepared = await tester.runAsync(
      () => const ImageIntake().prepare(
        Uint8List.fromList(img.encodeJpg(source, quality: 100)),
        mimeType: 'image/jpeg',
      ),
    );

    expect(prepared, isNotNull);
    final image = prepared!;
    expect(image.mimeType, 'image/png');
    expect((image.width, image.height), (1, 2));
    final decoded = img.decodePng(image.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.exif.imageIfd.hasOrientation, isFalse);
  });

  testWidgets('keeps a large image inside the longest-edge bound', (
    tester,
  ) async {
    final source = img.Image(width: 2050, height: 2);

    final prepared = await tester.runAsync(
      () => const ImageIntake().prepare(
        Uint8List.fromList(img.encodePng(source)),
        mimeType: 'image/png',
      ),
    );

    expect(prepared, isNotNull);
    expect(prepared!.mimeType, 'image/png');
    expect(prepared.width, ImageIntake.maxDimension);
    expect(prepared.height, greaterThan(0));
  });

  testWidgets('keeps an ordinary phone aspect ratio under one megapixel', (
    tester,
  ) async {
    final source = img.Image(width: 1600, height: 1200);

    final prepared = await tester.runAsync(
      () => const ImageIntake().prepare(
        Uint8List.fromList(img.encodePng(source)),
        mimeType: 'image/png',
      ),
    );

    expect(prepared, isNotNull);
    expect(prepared!.width * prepared.height, lessThanOrEqualTo(1024 * 1024));
    expect(prepared.width / prepared.height, closeTo(4 / 3, 0.01));
  });
}
