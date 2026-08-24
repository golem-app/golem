import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

/// Produces the ANDROID launcher sources for every build flavor from the
/// tracked copies of the native icons (assets/source/), flattening the pixels
/// outside a slightly inset superellipse to Glacier navy so the square
/// legacy-launcher tiles have no white corners.
///
/// iOS deliberately ships the unmodified native artwork instead
/// (`image_path_ios` in the `flutter_launcher_icons-<flavor>.yaml` files):
/// frame-by-frame recording of the iOS 26 launch zoom confirmed the
/// solid-navy launch storyboard — not icon matting — is what prevents the
/// historical white flash, and the navy matte is wider than Apple's real icon
/// mask, so it showed as a dark ring around the framed artwork on the Home
/// Screen.
const flavors = ['production', 'qa', 'dev'];

void main() {
  for (final flavor in flavors) {
    final source = File('assets/source/golem_icon_${flavor}_1024.png');
    final icon = image.decodePng(source.readAsBytesSync());
    if (icon == null || icon.width != 1024 || icon.height != 1024) {
      throw StateError('Expected the tracked 1024×1024 $flavor Golem icon.');
    }
    // Order matters: the background, tile, and macOS writers sample the
    // artwork before the matte mutates the decoded icon in place.
    _writeAdaptiveBackground(flavor, icon);
    _writeAppIconTile(flavor, icon);
    _writeMacIconset('AppIcon-$flavor', icon);
    _writeMattedLauncher(flavor, icon);
  }

  _writeAndroid12Splash();
  _writeAdaptiveForeground();
}

/// The squircle both maskers cut to, as a superellipse exponent and an inset
/// (in source pixels, at the tracked 1024×1024 scale). They are shared so
/// that retuning the Android matte cannot silently desync the in-app tile.
const _squircleExponent = 4.5;
const _squircleInset = 12.0;
const _sourceSize = 1024;

void _writeMattedLauncher(String flavor, image.Image icon) {
  const exponent = _squircleExponent;
  const matteInset = _squircleInset;
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

  File(
    'assets/images/golem_launcher_$flavor.png',
  ).writeAsBytesSync(image.encodePng(icon, level: 9));
}

/// The shipped app icon as an in-app tile, cut to the same superellipse the
/// Android matte uses — but expressed as alpha instead of a navy fill.
///
/// The tracked sources are opaque RGB with white corners on purpose: iOS
/// applies its own icon mask at display time, so the corners never reach the
/// Home Screen. Nothing masks a Flutter surface, so a widget that draws the
/// source directly (the drawer header) would show those white corners around
/// the framed artwork. This derivative bakes a mask into the alpha channel
/// instead, leaving the artwork itself untouched. 168×168 is the 42pt header
/// tile at 4x, the densest scale any shipped device asks for.
///
/// The curve is this project's squircle, not a reproduction of Apple's mask:
/// as the file header notes, this inset runs slightly wider than the real one,
/// which is why iOS ships the unmodified artwork. At a 42pt tile the
/// difference is a fraction of a point, and using one curve for both maskers
/// is worth more than matching the Home Screen to the pixel.
void _writeAppIconTile(String flavor, image.Image icon) {
  const size = 168;
  const exponent = _squircleExponent;
  const matteInset = _squircleInset * size / _sourceSize;
  // A single center sample per pixel leaves a visibly stepped rim at this
  // size; coverage from a 4×4 sub-sample grid anti-aliases it.
  const samples = 4;
  // Resize first, while the artwork is still opaque: a cubic filter run over
  // pre-masked pixels would drag the transparent corners into the frame.
  final resized = image.copyResize(
    icon,
    width: size,
    height: size,
    interpolation: image.Interpolation.cubic,
  );
  final canvas = image.Image(width: size, height: size, numChannels: 4);
  const half = size / 2;
  const visibleRadius = half - matteInset;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var covered = 0;
      for (var sy = 0; sy < samples; sy++) {
        final normalizedY =
            ((y + (sy + 0.5) / samples) - half).abs() / visibleRadius;
        final poweredY = math.pow(normalizedY, exponent);
        for (var sx = 0; sx < samples; sx++) {
          final normalizedX =
              ((x + (sx + 0.5) / samples) - half).abs() / visibleRadius;
          if (poweredY + math.pow(normalizedX, exponent) <= 1) covered++;
        }
      }
      if (covered == 0) continue;
      final pixel = resized.getPixel(x, y);
      canvas.setPixelRgba(
        x,
        y,
        pixel.r,
        pixel.g,
        pixel.b,
        (255 * covered / (samples * samples)).round(),
      );
    }
  }

  File(
    'assets/images/golem_app_icon_$flavor.png',
  ).writeAsBytesSync(image.encodePng(canvas, level: 9));
}

/// Android 12+ always reserves a centered icon slot on its system splash and
/// the app cannot reposition it, so any artwork there visibly jumps against
/// the Flutter splash tile (which sits above center as part of the centered
/// tile/wordmark/progress composition). A fully transparent drawable
/// suppresses the system icon on every device, leaving the same solid-navy
/// first frame iOS shows before the Flutter splash takes over.
void _writeAndroid12Splash() {
  final canvas = image.Image(width: 1152, height: 1152, numChannels: 4);
  File(
    'assets/images/golem_android12_splash.png',
  ).writeAsBytesSync(image.encodePng(canvas, level: 9));
}

/// Adaptive-icon foreground: the mascot sized deliberately beyond the strict
/// ~61% safe-zone guarantee for a bolder icon, accepting that spec-strict
/// launcher masks may clip a couple of dp of the rounded head and feet tips
/// (see the sizing comment below). The native icon's frame is deliberately
/// absent — frames do not survive Android's adaptive masks. The mascot is
/// shared by every flavor; only the gradient background differs.
void _writeAdaptiveForeground() {
  final mascot = image.decodePng(
    File('assets/images/golem_mascot.png').readAsBytesSync(),
  )!;
  const canvasSize = 1024;
  // 730 (~71%): the mascot's width stays inside the ~72dp window that
  // spec-strict launchers crop to; only a couple of dp of the rounded head
  // and feet tips would clip there. Launchers that scale the full canvas
  // into their mask (e.g. OnePlus) show it uncropped and pleasantly bold.
  const safeBox = 730;
  final scale = safeBox / math.max(mascot.width, mascot.height);
  final width = (mascot.width * scale).round();
  final height = (mascot.height * scale).round();
  final canvas = image.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  final resized = image.copyResize(
    mascot,
    width: width,
    height: height,
    interpolation: image.Interpolation.cubic,
  );
  image.compositeImage(
    canvas,
    resized,
    dstX: (canvasSize - width) ~/ 2,
    dstY: (canvasSize - height) ~/ 2,
  );
  File(
    'assets/images/golem_adaptive_foreground.png',
  ).writeAsBytesSync(image.encodePng(canvas, level: 9));
}

/// macOS Dock iconsets, generated here because flutter_launcher_icons can
/// only write one fixed AppIcon.appiconset for macOS (no per-flavor naming).
/// Apple's Big Sur convention: the artwork scaled to 824×824, masked by a
/// rounded rectangle, centered on a transparent 1024 canvas so the Dock
/// renders the standard margin. The per-flavor catalogs are selected by
/// `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-<flavor>` in the pbxproj.
void _writeMacIconset(String name, image.Image icon) {
  const canvasSize = 1024;
  const artworkSize = 824;
  // Apple's macOS icon grid rounds corners at ~22.5% of the artwork edge.
  const cornerRadius = artworkSize * 0.225;
  final scaled = image.copyResize(
    icon,
    width: artworkSize,
    height: artworkSize,
    interpolation: image.Interpolation.cubic,
  );
  final canvas = image.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  const offset = (canvasSize - artworkSize) ~/ 2;
  const half = artworkSize / 2;
  const boxHalf = half - cornerRadius;
  for (var y = 0; y < artworkSize; y++) {
    final dy = math.max(((y + 0.5) - half).abs() - boxHalf, 0.0);
    for (var x = 0; x < artworkSize; x++) {
      final dx = math.max(((x + 0.5) - half).abs() - boxHalf, 0.0);
      // Signed distance to the rounded-rect edge; one-pixel smoothstep for
      // an anti-aliased rim.
      final distance = math.sqrt(dx * dx + dy * dy) - cornerRadius;
      final coverage = (0.5 - distance).clamp(0.0, 1.0);
      if (coverage == 0) continue;
      final pixel = scaled.getPixel(x, y);
      canvas.setPixelRgba(
        offset + x,
        offset + y,
        pixel.r,
        pixel.g,
        pixel.b,
        (coverage * 255).round(),
      );
    }
  }

  final directory = Directory('macos/Runner/Assets.xcassets/$name.appiconset')
    ..createSync(recursive: true);
  for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
    final resized = size == canvasSize
        ? canvas
        : image.copyResize(
            canvas,
            width: size,
            height: size,
            interpolation: image.Interpolation.cubic,
          );
    File(
      '${directory.path}/app_icon_$size.png',
    ).writeAsBytesSync(image.encodePng(resized, level: 9));
  }
  final entries = [
    for (final size in [16, 32, 128, 256, 512])
      for (final scale in [1, 2])
        '    {\n'
            '      "size" : "${size}x$size",\n'
            '      "idiom" : "mac",\n'
            '      "filename" : "app_icon_${size * scale}.png",\n'
            '      "scale" : "${scale}x"\n'
            '    }',
  ];
  File('${directory.path}/Contents.json').writeAsStringSync(
    '{\n'
    '  "images" : [\n'
    '${entries.join(',\n')}\n'
    '  ],\n'
    '  "info" : {\n'
    '    "version" : 1,\n'
    '    "author" : "xcode"\n'
    '  }\n'
    '}\n',
  );
}

/// Adaptive-icon background: the flavor icon's vertical gradient, sampled
/// from the artwork itself so each flavor keeps its native hue without a
/// hand-maintained palette. The sample column is the icon's center; the
/// sample rows sit inside the frame border yet clear of the mascot in all
/// three sources.
void _writeAdaptiveBackground(String flavor, image.Image icon) {
  final top = icon.getPixel(512, 96);
  final bottom = icon.getPixel(512, 928);
  const size = 1024;
  final canvas = image.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    final t = y / (size - 1);
    final r = (top.r + (bottom.r - top.r) * t).round();
    final g = (top.g + (bottom.g - top.g) * t).round();
    final b = (top.b + (bottom.b - top.b) * t).round();
    for (var x = 0; x < size; x++) {
      canvas.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  File(
    'assets/images/golem_adaptive_background_$flavor.png',
  ).writeAsBytesSync(image.encodePng(canvas, level: 9));
}
