import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:image/image.dart' as image;

/// The three build flavors, keyed by the in-app [AppIdentity] so the strings
/// the platforms ship are asserted against the single Dart-side source of
/// truth. `displaySetting` spells out the pbxproj quoting; `dominant` selects
/// the color channel that must lead at the artwork sample point — blue
/// production, red QA, green dev.
const _flavors = [
  (
    identity: AppIdentity.production,
    displaySetting: 'GOLEM_DISPLAY_NAME = Golem;',
    dominant: 'b',
  ),
  (
    identity: AppIdentity.qa,
    displaySetting: 'GOLEM_DISPLAY_NAME = "Golem QA";',
    dominant: 'r',
  ),
  (
    identity: AppIdentity.dev,
    displaySetting: 'GOLEM_DISPLAY_NAME = "Golem Dev";',
    dominant: 'g',
  ),
];

num _channel(image.Pixel pixel, String channel) => switch (channel) {
  'r' => pixel.r,
  'g' => pixel.g,
  'b' => pixel.b,
  _ => throw ArgumentError.value(channel, 'channel'),
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
  test('every shipped flavor identity is covered by these assertions', () {
    // AppIdentity also carries the flavorless legacy identity, which owns no
    // flavor resources — hence its exclusion. A new enum member must either
    // join _flavors or be exempted here deliberately.
    expect(
      _flavors.map((flavor) => flavor.identity).toSet(),
      AppIdentity.values.toSet().difference({AppIdentity.flutter}),
    );
  });

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
      expect(gradle, contains('create("${flavor.identity.name}")'));
      expect(
        gradle,
        contains('applicationId = "${flavor.identity.applicationId}"'),
      );
      expect(
        gradle,
        contains(
          'resValue("string", "app_name", "${flavor.identity.displayName}")',
        ),
      );
    }

    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    // Release builds download models; without the main-manifest INTERNET
    // permission only debug/profile builds would have network access.
    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    // Downloaded models are re-fetchable and must stay out of backups and
    // device transfers on every rules surface.
    for (final rules in [
      'android/app/src/main/res/xml/backup_rules.xml',
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ]) {
      expect(
        await File(rules).readAsString(),
        contains('<exclude domain="root" path="app_flutter/models"/>'),
        reason: rules,
      );
    }

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
      final res = 'android/app/src/${flavor.identity.name}/res';
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
      final name = flavor.identity.name;
      for (final mode in ['Debug', 'Release', 'Profile']) {
        expect(project, contains('name = "$mode-$name";'));
      }
      expect(
        project,
        contains(
          'PRODUCT_BUNDLE_IDENTIFIER = ${flavor.identity.applicationId};',
        ),
      );
      expect(
        project,
        contains('ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-$name";'),
      );
      expect(project, contains(flavor.displaySetting));

      final scheme = await File(
        'ios/Runner.xcodeproj/xcshareddata/xcschemes/$name.xcscheme',
      ).readAsString();
      expect(scheme, contains('buildConfiguration = "Debug-$name"'));
      expect(scheme, contains('buildConfiguration = "Profile-$name"'));
      expect(scheme, contains('buildConfiguration = "Release-$name"'));
      expect(scheme, contains('xcode_backend.sh&quot; prepare'));
    }

    // The flavorless legacy identity remains for RunnerTests and direct
    // xcodebuild use, and the shared Info.plist resolves its display name
    // through the per-configuration variable.
    expect(
      project,
      contains(
        'PRODUCT_BUNDLE_IDENTIFIER = ${AppIdentity.flutter.applicationId};',
      ),
    );
    expect(
      project,
      contains('GOLEM_DISPLAY_NAME = "${AppIdentity.flutter.displayName}";'),
    );
    final plist = await File('ios/Runner/Info.plist').readAsString();
    expect(plist, contains(r'<string>$(GOLEM_DISPLAY_NAME)</string>'));
  });

  test('macOS build configurations map every flavor identity', () async {
    final project = await File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsString();
    for (final flavor in _flavors) {
      final name = flavor.identity.name;
      for (final mode in ['Debug', 'Release', 'Profile']) {
        expect(project, contains('name = "$mode-$name";'));
      }
      expect(
        project,
        contains(
          'PRODUCT_BUNDLE_IDENTIFIER = ${flavor.identity.applicationId};',
        ),
      );
      expect(
        project,
        contains('ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-$name";'),
      );
      expect(project, contains(flavor.displaySetting));

      final scheme = await File(
        'macos/Runner.xcodeproj/xcshareddata/xcschemes/$name.xcscheme',
      ).readAsString();
      expect(scheme, contains('buildConfiguration = "Debug-$name"'));
      expect(scheme, contains('buildConfiguration = "Profile-$name"'));
      expect(scheme, contains('buildConfiguration = "Release-$name"'));
      expect(scheme, contains('macos_assemble.sh prepare'));
    }

    // The MLX Swift package declares macOS 14 and Apple silicon only; all
    // twelve project-level configurations must hold both — a value-set
    // assertion alone would pass with a single surviving occurrence, and the
    // line anchor keeps EXCLUDED_ARCHS-style settings out of the match.
    final deploymentTargets = RegExp(
      r'^\s*MACOSX_DEPLOYMENT_TARGET = ([\d.]+);$',
      multiLine: true,
    ).allMatches(project).map((match) => match[1]).toList();
    expect(deploymentTargets.toSet(), {'14.0'});
    expect(deploymentTargets, hasLength(12));

    final architectures = RegExp(
      r'^\s*ARCHS = (\S+);$',
      multiLine: true,
    ).allMatches(project).map((match) => match[1]).toList();
    expect(architectures.toSet(), {'arm64'});
    expect(architectures, hasLength(12));

    // The staging phase feeds the MLX shader/tokenizer bundles into the app;
    // without it MLX fails to resolve default.metallib at runtime.
    expect(project, contains('/* Stage Inferno Apple Resources */'));
    expect(
      project,
      contains(
        'shellScript = '
        '"\\"\${SRCROOT}/Flutter/stage_inferno_apple_resources.sh\\"\\n";',
      ),
    );
    expect(
      File('macos/Flutter/stage_inferno_apple_resources.sh').existsSync(),
      isTrue,
    );

    // The flavorless legacy identity lives in AppInfo.xcconfig and stays for
    // RunnerTests and direct xcodebuild use; the shared Info.plist resolves
    // both name keys through the per-configuration variable.
    expect(
      await File('macos/Runner/Configs/AppInfo.xcconfig').readAsString(),
      contains(
        'PRODUCT_BUNDLE_IDENTIFIER = ${AppIdentity.flutter.applicationId}',
      ),
    );
    expect(
      project,
      contains('GOLEM_DISPLAY_NAME = "${AppIdentity.flutter.displayName}";'),
    );
    final plist = await File('macos/Runner/Info.plist').readAsString();
    expect(
      RegExp(
        r'<string>\$\(GOLEM_DISPLAY_NAME\)</string>',
      ).allMatches(plist).length,
      2,
      reason: 'CFBundleDisplayName and CFBundleName both resolve the variable',
    );
  });

  test('the macOS app sandbox is deliberately disabled', () async {
    // A development target must read model files from arbitrary local paths;
    // distribution hardening re-enables this later, deliberately.
    for (final file in ['DebugProfile', 'Release']) {
      final entitlements = await File(
        'macos/Runner/$file.entitlements',
      ).readAsString();
      expect(
        entitlements,
        contains('<key>com.apple.security.app-sandbox</key>\n\t<false/>'),
        reason: '$file.entitlements',
      );
    }
  });

  test(
    'the macOS window opens iPad-shaped, resizable, with a minimum',
    () async {
      final window = await File(
        'macos/Runner/MainFlutterWindow.swift',
      ).readAsString();
      expect(window, contains('NSSize(width: 834, height: 1194)'));
      expect(window, contains('minimumContentSize'));
      expect(window, contains('setFrameAutosaveName'));
    },
  );

  test('macOS Dock iconsets carry the flavor artwork with Apple margins', () {
    final catalogs = [
      for (final flavor in _flavors)
        (flavor: flavor, name: 'AppIcon-${flavor.identity.name}'),
      // The flavorless catalog keeps real Golem artwork (production hue).
      (flavor: _flavors.first, name: 'AppIcon'),
    ];
    for (final entry in catalogs) {
      final path = 'macos/Runner/Assets.xcassets/${entry.name}.appiconset';
      final icon = image.decodePng(
        File('$path/app_icon_1024.png').readAsBytesSync(),
      )!;
      expect(icon.width, 1024);

      // Transparent Apple margin outside the rounded square...
      for (final corner in [
        icon.getPixel(0, 0),
        icon.getPixel(1023, 0),
        icon.getPixel(0, 1023),
        icon.getPixel(1023, 1023),
        icon.getPixel(512, 40),
      ]) {
        expect(corner.a, 0);
      }
      // ...opaque artwork inside it, with the flavor hue leading.
      expect(icon.getPixel(512, 512).a, 255);
      _expectDominantChannel(icon.getPixel(512, 860), entry.flavor.dominant);
      expect(
        File('$path/Contents.json').readAsStringSync(),
        contains('"filename" : "app_icon_512.png"'),
      );
    }
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
        'assets/images/golem_launcher_${flavor.identity.name}.png',
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
          'assets/images/golem_adaptive_background_${flavor.identity.name}.png',
        ).readAsBytes(),
      )!;
      _expectDominantChannel(background.getPixel(512, 512), flavor.dominant);

      // iOS ships the exact source artwork so the Home Screen icon keeps its
      // white matte corners, silver frame, and flavor hue.
      final generated = image.decodePng(
        await File(
          'ios/Runner/Assets.xcassets/AppIcon-${flavor.identity.name}.appiconset/'
          'AppIcon-${flavor.identity.name}-1024x1024@1x.png',
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
