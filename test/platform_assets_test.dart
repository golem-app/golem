import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test(
    'native launch screen is a solid navy storyboard with no image',
    () async {
      final storyboard = await File(
        'ios/Runner/Base.lproj/GolemLaunchScreen.storyboard',
      ).readAsString();
      expect(storyboard, contains('red="0.05882352941"'));
      expect(storyboard, contains('green="0.08235294118"'));
      expect(storyboard, contains('blue="0.1411764706"'));
      // The iOS 26 launch-snapshot renderer mishandles storyboard launch
      // images (wrong scale, alpha flattened to white), so the native launch
      // screen must stay image-free. The Flutter splash draws the artwork.
      expect(storyboard, isNot(contains('<imageView')));
      expect(
        await File('ios/Runner/Info.plist').readAsString(),
        contains('<string>GolemLaunchScreen</string>'),
      );
      expect(
        File('ios/Runner/Base.lproj/LaunchScreen.storyboard').existsSync(),
        isFalse,
      );
      expect(
        Directory(
          'ios/Runner/Assets.xcassets/LaunchImage.imageset',
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          'ios/Runner/Assets.xcassets/LaunchBackground.imageset',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('splash tile has transparent corners and opaque artwork', () async {
    final bytes = await File(
      'assets/images/golem_splash_icon.png',
    ).readAsBytes();
    expect(bytes[25], 6);

    final splashIcon = image.decodePng(bytes);
    expect(splashIcon, isNotNull);
    final corners = <image.Pixel>[
      splashIcon!.getPixel(0, 0),
      splashIcon.getPixel(splashIcon.width - 1, 0),
      splashIcon.getPixel(0, splashIcon.height - 1),
      splashIcon.getPixel(splashIcon.width - 1, splashIcon.height - 1),
    ];
    for (final corner in corners) {
      expect(corner.a, 0);
    }
    expect(
      splashIcon.getPixel(splashIcon.width ~/ 2, splashIcon.height ~/ 2).a,
      255,
    );
  });

  test('iOS launcher is opaque, square, and full bleed', () async {
    final sourceBytes = await File(
      'assets/images/golem_launcher_ios.png',
    ).readAsBytes();
    final source = image.decodePng(sourceBytes)!;
    expect(source.width, 1024);
    expect(source.height, 1024);
    expect(sourceBytes[25], 2);

    final corners = <image.Pixel>[
      source.getPixel(0, 0),
      source.getPixel(source.width - 1, 0),
      source.getPixel(0, source.height - 1),
      source.getPixel(source.width - 1, source.height - 1),
    ];
    for (final corner in corners) {
      expect(corner.a, 255);
      expect(corner.b, greaterThan(corner.r));
    }

    final generated = await File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    ).readAsBytes();
    expect(generated[25], 2);
  });
}
