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

  test('iOS targets portrait iPhone only', () async {
    final plist = await File('ios/Runner/Info.plist').readAsString();
    expect(plist, isNot(contains('Landscape')));
    expect(plist, isNot(contains('UISupportedInterfaceOrientations~ipad')));

    final project = await File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsString();
    expect(project, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
    expect(project, contains('TARGETED_DEVICE_FAMILY = 1;'));
  });

  test('Android launcher activity matches the application namespace', () async {
    final gradle = await File('android/app/build.gradle.kts').readAsString();
    expect(gradle, contains('namespace = "app.golem.flutter"'));
    expect(gradle, contains('applicationId = "app.golem.flutter"'));

    final activity = await File(
      'android/app/src/main/kotlin/app/golem/flutter/MainActivity.kt',
    ).readAsString();
    expect(activity, contains('package app.golem.flutter'));
    expect(
      File(
        'android/app/src/main/kotlin/app/golem/golem_flutter/MainActivity.kt',
      ).existsSync(),
      isFalse,
    );
  });

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

  test('platform launchers use their configured native artwork', () async {
    final sourceBytes = await File(
      'assets/images/golem_launcher.png',
    ).readAsBytes();
    final source = image.decodePng(sourceBytes)!;
    expect(source.width, 1024);
    expect(source.height, 1024);

    // Android's generated launcher source flattens corners outside the icon
    // squircle to Glacier navy so legacy square tiles have no white corners.
    final corners = <image.Pixel>[
      source.getPixel(0, 0),
      source.getPixel(source.width - 1, 0),
      source.getPixel(0, source.height - 1),
      source.getPixel(source.width - 1, source.height - 1),
    ];
    for (final corner in corners) {
      expect(corner.a, 255);
      expect(corner.r, 15);
      expect(corner.g, 21);
      expect(corner.b, 36);
    }

    // Inside the squircle the native silver frame survives untouched.
    final frame = source.getPixel(source.width ~/ 2, 16);
    expect(frame.b, greaterThan(200));

    // iOS ships the exact native artwork so the Home Screen icon is
    // pixel-identical to native Golem: white matte corners, silver frame.
    final generatedBytes = await File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    ).readAsBytes();
    final generated = image.decodePng(generatedBytes)!;
    final generatedCorner = generated.getPixel(0, 0);
    expect(generatedCorner.r, greaterThan(240));
    expect(generatedCorner.g, greaterThan(240));
    expect(generatedCorner.b, greaterThan(240));
  });
}
