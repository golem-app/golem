import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

/// Reuses the native production icon exactly inside the iOS-visible squircle.
///
/// The tracked native PNG has a white matte in the otherwise-hidden square
/// corners. SpringBoard masks those pixels on the Home Screen, but briefly
/// exposes them during its launch zoom. Flattening only the pixels outside a
/// slightly inset superellipse to Glacier navy prevents that flash without
/// altering the artwork that remains visible inside the system icon mask.
void main() {
  final source = File(
    '../Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png',
  );
  final output = File('assets/images/golem_launcher.png');
  final icon = image.decodePng(source.readAsBytesSync());
  if (icon == null || icon.width != 1024 || icon.height != 1024) {
    throw StateError('Expected the tracked 1024×1024 native Golem icon.');
  }

  const exponent = 4.5;
  const matteInset = 12.0;
  const navy = (r: 15, g: 21, b: 36);
  final halfWidth = icon.width / 2;
  final halfHeight = icon.height / 2;
  final visibleRadiusX = halfWidth - matteInset;
  final visibleRadiusY = halfHeight - matteInset;
  for (var y = 0; y < icon.height; y++) {
    final normalizedY = ((y + 0.5) - halfHeight).abs() / visibleRadiusY;
    for (var x = 0; x < icon.width; x++) {
      final normalizedX = ((x + 0.5) - halfWidth).abs() / visibleRadiusX;
      final outsideSquircle =
          math.pow(normalizedX, exponent) + math.pow(normalizedY, exponent) > 1;
      if (outsideSquircle) {
        icon.setPixelRgba(x, y, navy.r, navy.g, navy.b, 255);
      }
    }
  }

  output.writeAsBytesSync(image.encodePng(icon, level: 9));
}
