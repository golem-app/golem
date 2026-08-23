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

/// The Kotlin entry point, whose package moved off the retired identity in
/// #116. Named once because three assertions and the Android `am start`
/// runbook all address this exact class.
const _mainActivity = 'android/app/src/main/kotlin/app/golem/MainActivity.kt';

/// The trailing extension of [path] including its dot, or '' when it has none.
String _extension(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf(Platform.pathSeparator);
  return dot > slash ? path.substring(dot) : '';
}

num _channel(image.Pixel pixel, String channel) => switch (channel) {
  'r' => pixel.r,
  'g' => pixel.g,
  'b' => pixel.b,
  _ => throw ArgumentError.value(channel, 'channel'),
};

/// How many configurations give a pbxproj setting each value.
///
/// The count carries as much as the value: retargeting one configuration at
/// an identity that some other configuration already uses leaves the set of
/// distinct values untouched, so a set assertion would pass while a bare
/// `xcodebuild` installed the wrong app. Deleting the setting from a
/// configuration is invisible to a set as well, and leaves the flavorless
/// build with no icon and an empty CFBundleDisplayName.
Map<String, int> _settingCounts(String project, String setting) {
  final counts = <String, int>{};
  for (final match in RegExp(
    '^\\s*$setting = (.+);\$',
    multiLine: true,
  ).allMatches(project)) {
    final value = match[1]!.replaceAll('"', '');
    counts[value] = (counts[value] ?? 0) + 1;
  }
  // A value the pattern cannot read would be indistinguishable from a clean
  // project, so every occurrence has to be accounted for.
  expect(
    counts.values.fold<int>(0, (sum, count) => sum + count),
    RegExp('^\\s*$setting = ', multiLine: true).allMatches(project).length,
    reason: 'unparsed $setting occurrences',
  );
  return counts;
}

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
  test('benchmark prompts are bundled only for internal flavors', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('- path: assets/benchmark_prompts/'));
    expect(
      pubspec,
      contains(
        'assets/benchmark_prompts/\n      flavors:\n        - qa\n        - dev',
      ),
    );
  });

  test('the icon fonts the build references are declared', () async {
    // Dropping this line brings back the tree-shaker's "Expected to find
    // fonts for (…, MaterialIcons)" on every release artifact: go_router and
    // background_downloader reference codepoints the app never draws (#118).
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('uses-material-design: true'));

    // The declaration is for the dependencies' sake only. Golem's own
    // surfaces stay Cupertino: a material.dart import here would pull a
    // second design system into a single-chrome app.
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in sources) {
      expect(
        file.readAsStringSync(),
        isNot(contains('package:flutter/material.dart')),
        reason: file.path,
      );
    }
  });

  test('every shipped flavor identity is covered by these assertions', () {
    // Every identity the app can run under owns flavor resources, and a new
    // enum member has to join _flavors to acquire them.
    expect(
      _flavors.map((flavor) => flavor.identity).toSet(),
      AppIdentity.values.toSet(),
    );
  });

  test(
    'native launch screen is a solid navy storyboard with no image',
    () async {
      final storyboard = await File(
        'ios/Runner/Base.lproj/GolemLaunchScreen.storyboard',
      ).readAsString();
      expect(storyboard, contains('red="0.02352941176"'));
      expect(storyboard, contains('green="0.05098039216"'));
      expect(storyboard, contains('blue="0.1215686275"'));
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

  test('the iOS bundle declares what App Store Connect reads', () async {
    // Required-reason APIs (#154): AppDelegate reads the volume's capacity for
    // the Storage screen and the download preflight, which is the DiskSpace
    // category under reasons 85F4.1 (shown to the user) and E174.1 (checked
    // before writing). The manifest must be a Runner resource or the bundle
    // ships without it and the upload is rejected.
    final manifest = await File(
      'ios/Runner/PrivacyInfo.xcprivacy',
    ).readAsString();
    expect(manifest, contains('NSPrivacyAccessedAPICategoryDiskSpace'));
    expect(manifest, contains('<string>85F4.1</string>'));
    expect(manifest, contains('<string>E174.1</string>'));
    expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
    final project = await File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsString();
    expect(project, contains('PrivacyInfo.xcprivacy in Resources'));
    // The MLX carrier the default iOS build composes declares iOS 17
    // (packages/inferno/native/apple/Package.swift) and is dlopen'ed at the
    // launch probe, so a lower floor installs on phones that then die at
    // first use. A12 — the store gate — runs iOS 17, so no hardware is lost.
    expect('IPHONEOS_DEPLOYMENT_TARGET = 17.0;'.allMatches(project).length, 12);
    expect(project, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0')));

    final plist = await File('ios/Runner/Info.plist').readAsString();
    // HTTPS through the OS and SHA-256 integrity hashing are exempt; the key
    // spares every TestFlight upload the export-compliance prompt (ADR 0016).
    expect(
      plist,
      contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
    );
    // CFBundleName follows the flavor like CFBundleDisplayName does; the
    // pubspec package name is not an identity (#133).
    expect(plist, isNot(contains('golem_flutter')));
    expect(
      r'$(GOLEM_DISPLAY_NAME)'.allMatches(plist).length,
      2,
      reason: 'CFBundleDisplayName and CFBundleName both resolve the variable',
    );
  });

  test('native bundles declare every UI locale and RTL support', () async {
    final project = await File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsString();
    for (final locale in [
      'en',
      'pl',
      'ar',
      'es',
      'pt-BR',
      'ja',
      'id',
      'hi',
      'fr',
      'vi',
      'tr',
      'ko',
    ]) {
      expect(project, contains('$locale.lproj/InfoPlist.strings'));
      final file = File('ios/Runner/$locale.lproj/InfoPlist.strings');
      expect(file.existsSync(), isTrue, reason: locale);
      final contents = await file.readAsString();
      expect(contents, contains('NSCameraUsageDescription'), reason: locale);
      expect(
        contents,
        contains('NSPhotoLibraryUsageDescription'),
        reason: locale,
      );
    }
    expect(project, contains('name = InfoPlist.strings;'));
    final arabic = await File(
      'ios/Runner/ar.lproj/InfoPlist.strings',
    ).readAsString();
    expect(arabic, contains('NSCameraUsageDescription'));
    expect(arabic, contains('NSPhotoLibraryUsageDescription'));
    expect(arabic, matches(RegExp(r'[\u0600-\u06ff]')));
    final scriptSentinels = <String, RegExp>{
      'hi': RegExp(r'[\u0900-\u097f]'),
      'fr': RegExp('[éèà]'),
      'vi': RegExp('[ảẢ]'),
      'tr': RegExp('[ıİğş]'),
      'ko': RegExp(r'[\uac00-\ud7af]'),
    };
    for (final entry in scriptSentinels.entries) {
      final contents = await File(
        'ios/Runner/${entry.key}.lproj/InfoPlist.strings',
      ).readAsString();
      expect(contents, matches(entry.value), reason: entry.key);
    }

    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();
    expect(manifest, contains('android:supportsRtl="true"'));
    expect(
      manifest,
      contains('locale|layoutDirection|fontScale'),
      reason: 'locale changes must rebuild Flutter directionality',
    );
  });

  test('Android flavors own the application identities and labels', () async {
    final gradle = await File('android/app/build.gradle.kts').readAsString();
    // The namespace (Kotlin package / resource namespace) is deliberately
    // flavor-independent; only the applicationId varies per flavor. That it
    // equals the production applicationId is a coincidence of naming, not a
    // shared setting.
    expect(gradle, contains('namespace = "app.golem"'));
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
    // Nothing Golem stores leaves the phone (ADR 0016). allowBackup off is
    // the cloud half; some manufacturers keep device-to-device transfer on
    // regardless, so the extraction rules must exclude every domain from
    // both paths as well.
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, isNot(contains('BackupContent')));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    final rules = await File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsString();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = rules.split('<$section>')[1].split('</$section>')[0];
      for (final domain in [
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
      ]) {
        expect(
          body,
          contains('<exclude domain="$domain" path="."/>'),
          reason: '$section/$domain',
        );
      }
      expect(body, isNot(contains('<include')), reason: section);
    }

    final activity = await File(_mainActivity).readAsString();
    expect(activity, contains('package app.golem\n'));
    // The retired identity's package directory must not come back: the class
    // name is what `am start` recipes and launcher shortcuts address.
    expect(
      Directory('android/app/src/main/kotlin/app/golem/flutter').existsSync(),
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

  test('the storage platform channel is named the same on every side', () {
    // The Dart client and the three native handlers agree by inspection or
    // not at all: a missed shim is a MissingPluginException that only shows
    // up on the platform nobody re-ran. The name carries no flavor, because
    // one channel serves all three application identities.
    const expected = 'app.golem/storage';
    const sources = [
      'lib/core/services/device_storage.dart',
      'ios/Runner/AppDelegate.swift',
      'macos/Runner/MainFlutterWindow.swift',
      _mainActivity,
    ];
    final pattern = RegExp('[\'"]([\\w.]+/storage)[\'"]');
    for (final source in sources) {
      final names = pattern
          .allMatches(File(source).readAsStringSync())
          .map((match) => match[1])
          .toSet();
      expect(names, {expected}, reason: source);
    }
  });

  test('every storage channel method is answered on every side', () {
    // The name agreeing is not enough: a method the Dart client invokes and a
    // native handler never names degrades silently, because every caller
    // guards the channel and reads a refusal as "unknown". #148 added
    // isVirtualDevice by hand in three files, and a miss there would put the
    // multi-gigabyte fetch back on that platform's simulator with no error and
    // no failing test.
    final client = File(
      'lib/core/services/device_storage.dart',
    ).readAsStringSync();
    final invoked = RegExp(
      r"invokeMethod<[^>]+>\(\s*'(\w+)'",
    ).allMatches(client).map((match) => match[1]!).toSet();
    expect(invoked, isNotEmpty);
    for (final handler in const [
      'ios/Runner/AppDelegate.swift',
      'macos/Runner/MainFlutterWindow.swift',
      _mainActivity,
    ]) {
      final source = File(handler).readAsStringSync();
      // macOS answers one method fewer on purpose: there is no jetsam
      // ceiling to report, so the mobile load preflight has nothing to ask.
      final exempt = handler.startsWith('macos')
          ? const {'availableMemoryBytes'}
          : const <String>{};
      for (final method in invoked.difference(exempt)) {
        expect(source, contains("\"$method\""), reason: '$handler: $method');
      }
    }
  });

  test('no shipping surface still names the retired identity', () {
    // #116. Enumerating the files a rename touched would pass the moment the
    // string reappears somewhere nobody listed — a scheme, a second xcconfig,
    // an Info.plist — so this walks the source trees instead and reads every
    // text file in them. Generated and vendored trees are excluded: they are
    // absent on a fresh clone and rebuilt from these sources anyway.
    const retired = 'app.golem.flutter';
    const roots = [
      'lib',
      'tool',
      'integration_test',
      'android',
      'ios',
      'macos',
    ];
    const textExtensions = {
      '.dart',
      '.kt',
      '.kts',
      '.gradle',
      '.swift',
      '.xml',
      '.plist',
      '.xcconfig',
      '.pbxproj',
      '.xcscheme',
      '.entitlements',
      '.storyboard',
      '.json',
      '.yaml',
      '.sh',
      '.h',
      '.m',
    };
    const generated = {
      'build',
      'Pods',
      'ephemeral',
      '.dart_tool',
      '.symlinks',
      'DerivedData',
      '.gradle',
      '.build',
      '.swiftpm',
    };
    final sources = <String>[
      'pubspec.yaml',
      for (final root in roots)
        for (final entity in Directory(root).listSync(recursive: true))
          if (entity is File &&
              !entity.uri.pathSegments.any(generated.contains) &&
              textExtensions.contains(_extension(entity.path)))
            entity.path,
    ];
    // A walk that silently matched nothing would be a guard in name only.
    expect(sources.length, greaterThan(50));
    for (final source in sources) {
      expect(
        File(source).readAsStringSync(),
        isNot(contains(retired)),
        reason: source,
      );
    }
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

    // Nothing this project can build carries an identity outside the shipped
    // set: the flavorless Debug/Release/Profile configurations a bare
    // `xcodebuild -scheme Runner` selects resolve to qa, artwork included, so
    // no build path can install a fourth app. The shared Info.plist resolves
    // the display name through the per-configuration variable.
    expect(_settingCounts(project, 'PRODUCT_BUNDLE_IDENTIFIER'), {
      AppIdentity.production.applicationId: 3,
      // Three flavor configurations plus the three flavorless ones.
      AppIdentity.qa.applicationId: 6,
      AppIdentity.dev.applicationId: 3,
      '${AppIdentity.qa.applicationId}.RunnerTests': 12,
    });
    expect(_settingCounts(project, 'GOLEM_DISPLAY_NAME'), {
      AppIdentity.production.displayName: 3,
      AppIdentity.qa.displayName: 6,
      AppIdentity.dev.displayName: 3,
    });
    expect(_settingCounts(project, 'ASSETCATALOG_COMPILER_APPICON_NAME'), {
      'AppIcon-${AppIdentity.production.name}': 3,
      'AppIcon-${AppIdentity.qa.name}': 6,
      'AppIcon-${AppIdentity.dev.name}': 3,
    });
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

    // As on iOS, no configuration may name an identity outside the shipped
    // set. The macOS Runner target takes its fallback bundle id from
    // AppInfo.xcconfig rather than the pbxproj, so that file is the one the
    // flavorless build reads. The shared Info.plist resolves both name keys
    // through the per-configuration variable.
    expect(
      await File('macos/Runner/Configs/AppInfo.xcconfig').readAsString(),
      contains('PRODUCT_BUNDLE_IDENTIFIER = ${AppIdentity.qa.applicationId}\n'),
    );
    // The flavorless Runner configurations take their bundle id from
    // AppInfo.xcconfig, so unlike iOS the pbxproj names qa only three times.
    expect(_settingCounts(project, 'PRODUCT_BUNDLE_IDENTIFIER'), {
      AppIdentity.production.applicationId: 3,
      AppIdentity.qa.applicationId: 3,
      AppIdentity.dev.applicationId: 3,
      '${AppIdentity.qa.applicationId}.RunnerTests': 12,
    });
    expect(_settingCounts(project, 'GOLEM_DISPLAY_NAME'), {
      AppIdentity.production.displayName: 3,
      AppIdentity.qa.displayName: 6,
      AppIdentity.dev.displayName: 3,
    });
    expect(_settingCounts(project, 'ASSETCATALOG_COMPILER_APPICON_NAME'), {
      'AppIcon-${AppIdentity.production.name}': 3,
      'AppIcon-${AppIdentity.qa.name}': 6,
      'AppIcon-${AppIdentity.dev.name}': 3,
    });
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

  test('app-icon tiles have transparent corners and opaque artwork', () async {
    for (final flavor in _flavors) {
      final identity = flavor.identity;
      final tile = image.decodePng(
        await File(identity.iconAsset).readAsBytes(),
      );
      expect(tile, isNotNull, reason: identity.iconAsset);
      // 42pt at 4x: the drawer header's tile at the densest shipped scale.
      expect(tile!.width, 168);
      expect(tile.height, 168);

      // The source's opaque white corners are cut away by the same
      // superellipse the Android matte fills with navy, so an in-app surface
      // gets the masked shape iOS draws on the Home Screen.
      final corners = <image.Pixel>[
        tile.getPixel(0, 0),
        tile.getPixel(tile.width - 1, 0),
        tile.getPixel(0, tile.height - 1),
        tile.getPixel(tile.width - 1, tile.height - 1),
      ];
      for (final corner in corners) {
        expect(corner.a, 0);
      }
      expect(tile.getPixel(tile.width ~/ 2, tile.height ~/ 2).a, 255);

      // The flavor hue survives the downscale at the launcher assertions'
      // artwork sample point, scaled from 1024 to 168.
      _expectDominantChannel(tile.getPixel(84, 148), flavor.dominant);
    }
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
