import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

/// The three build flavors and their expected platform identity. `dominant`
/// selects the color channel that must lead at the artwork sample point —
/// blue production, red QA, green dev.
const _flavors = [
  (
    name: 'production',
    applicationId: 'app.golem',
    label: 'Golem',
    displaySetting: 'GOLEM_DISPLAY_NAME = Golem;',
    dominant: 'b',
  ),
  (
    name: 'qa',
    applicationId: 'app.golem.qa',
    label: 'Golem QA',
    displaySetting: 'GOLEM_DISPLAY_NAME = "Golem QA";',
    dominant: 'r',
  ),
  (
    name: 'dev',
    applicationId: 'app.golem.dev',
    label: 'Golem Dev',
    displaySetting: 'GOLEM_DISPLAY_NAME = "Golem Dev";',
    dominant: 'g',
  ),
];

num _channel(image.Pixel pixel, String channel) => switch (channel) {
  'r' => pixel.r,
  'g' => pixel.g,
  _ => pixel.b,
};

void _expectDominantChannel(image.Pixel pixel, String channel) {
  final others = {'r', 'g', 'b'}.difference({channel});
  for (final other in others) {
    expect(
      _channel(pixel, channel),
      greaterThan(_channel(pixel, other)),
      reason: 'expected $channel to lead over $other in $pixel',
    );
  }
}

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
      // screen must stay image-free. The Flutter splash draws the artwork,
      // and every flavor shares the same storyboard.
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

  test('Android flavors own the application identities and labels', () async {
    final gradle = await File('android/app/build.gradle.kts').readAsString();
    // The namespace (Kotlin package / resource namespace) is deliberately
    // flavor-independent; only the applicationId varies per flavor.
    expect(gradle, contains('namespace = "app.golem.flutter"'));
    expect(gradle, isNot(contains('applicationId = "app.golem.flutter"')));
    expect(gradle, contains('flavorDimensions += "environment"'));
    for (final flavor in _flavors) {
      expect(gradle, contains('create("${flavor.name}")'));
      expect(gradle, contains('applicationId = "${flavor.applicationId}"'));
      expect(
        gradle,
        contains('resValue("string", "app_name", "${flavor.label}")'),
      );
    }

    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));

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

  test('Android launcher resources are owned by the flavor source sets', () {
    for (final flavor in _flavors) {
      final res = 'android/app/src/${flavor.name}/res';
      expect(File('$res/mipmap-xxxhdpi/ic_launcher.png').existsSync(), isTrue);
      expect(
        File('$res/mipmap-anydpi-v26/ic_launcher.xml').existsSync(),
        isTrue,
      );
      expect(
        File('$res/drawable-xxxhdpi/ic_launcher_background.png').existsSync(),
        isTrue,
      );
      expect(
        File('$res/drawable-xxxhdpi/ic_launcher_foreground.png').existsSync(),
        isTrue,
      );
    }
    // No stale flavor-shadowed launcher art may linger in main.
    expect(
      File(
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      ).existsSync(),
      isFalse,
    );
    expect(
      Directory('android/app/src/main/res/mipmap-anydpi-v26').existsSync(),
      isFalse,
    );
  });

  test('iOS build configurations map every flavor identity', () async {
    final project = await File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsString();
    // flutter_launcher_icons once corrupted this asset-symbol setting when a
    // flavor-named xcconfig existed; it must stay YES.
    expect(
      project,
      isNot(
        contains(
          'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS '
          '= AppIcon;',
        ),
      ),
    );
    for (final flavor in _flavors) {
      for (final mode in ['Debug', 'Release', 'Profile']) {
        expect(project, contains('name = "$mode-${flavor.name}";'));
      }
      expect(
        project,
        contains('PRODUCT_BUNDLE_IDENTIFIER = ${flavor.applicationId};'),
      );
      expect(
        project,
        contains(
          'ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-${flavor.name}";',
        ),
      );
      expect(project, contains(flavor.displaySetting));

      final scheme = await File(
        'ios/Runner.xcodeproj/xcshareddata/xcschemes/${flavor.name}.xcscheme',
      ).readAsString();
      expect(scheme, contains('buildConfiguration = "Debug-${flavor.name}"'));
      expect(scheme, contains('buildConfiguration = "Profile-${flavor.name}"'));
      expect(scheme, contains('buildConfiguration = "Release-${flavor.name}"'));
      expect(scheme, contains('xcode_backend.sh&quot; prepare'));
    }

    // The flavorless legacy identity remains for RunnerTests and direct
    // xcodebuild use, and the shared Info.plist resolves its display name
    // through the per-configuration variable.
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = app.golem.flutter;'));
    expect(project, contains('GOLEM_DISPLAY_NAME = "Golem Flutter";'));
    final plist = await File('ios/Runner/Info.plist').readAsString();
    expect(plist, contains(r'<string>$(GOLEM_DISPLAY_NAME)</string>'));
  });

  test('plain flutter commands default to the dev flavor', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('default-flavor: dev'));
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
    for (final flavor in _flavors) {
      final sourceBytes = await File(
        'assets/images/golem_launcher_${flavor.name}.png',
      ).readAsBytes();
      final source = image.decodePng(sourceBytes)!;
      expect(source.width, 1024);
      expect(source.height, 1024);

      // Android's generated launcher source flattens corners outside the
      // icon squircle to Glacier navy so legacy square tiles have no white
      // corners.
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

      // Inside the squircle the artwork's silver frame survives untouched.
      final frame = source.getPixel(source.width ~/ 2, 16);
      expect(frame.b, greaterThan(200));

      // The flavor hue shows in the artwork body and in the adaptive
      // gradient background derived from it.
      _expectDominantChannel(source.getPixel(512, 900), flavor.dominant);
      final background = image.decodePng(
        await File(
          'assets/images/golem_adaptive_background_${flavor.name}.png',
        ).readAsBytes(),
      )!;
      _expectDominantChannel(background.getPixel(512, 512), flavor.dominant);

      // iOS ships the exact source artwork so the Home Screen icon keeps its
      // white matte corners, silver frame, and flavor hue.
      final generated = image.decodePng(
        await File(
          'ios/Runner/Assets.xcassets/AppIcon-${flavor.name}.appiconset/'
          'AppIcon-${flavor.name}-1024x1024@1x.png',
        ).readAsBytes(),
      )!;
      final generatedCorner = generated.getPixel(0, 0);
      expect(generatedCorner.r, greaterThan(240));
      expect(generatedCorner.g, greaterThan(240));
      expect(generatedCorner.b, greaterThan(240));
      _expectDominantChannel(generated.getPixel(512, 900), flavor.dominant);
    }
  });
}
