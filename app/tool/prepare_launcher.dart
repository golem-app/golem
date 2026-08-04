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
    // Order matters: the background samples the artwork before the matte
    // mutates the decoded icon in place.
    _writeAdaptiveBackground(flavor, icon);
    _writeMattedLauncher(flavor, icon);
  }

  _writeAndroid12Splash();
  _writeAdaptiveForeground();
}

void _writeMattedLauncher(String flavor, image.Image icon) {
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

  File(
    'assets/images/golem_launcher_$flavor.png',
  ).writeAsBytesSync(image.encodePng(icon, level: 9));
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
