import 'dart:io';

/// Guards the hand-owned iOS launch screen.
///
/// `flutter_native_splash` runs with `ios: false` because the iOS 26
/// launch-snapshot renderer draws storyboard launch images at the wrong scale
/// and flattens their transparency to white. The native launch screen is the
/// solid Golem-navy `GolemLaunchScreen.storyboard`, committed and never
/// generated. This tool deletes any stray generated `LaunchScreen.storyboard`
/// and verifies the hand-owned storyboard and `Info.plist` wiring.
void main() {
  final generated = File('ios/Runner/Base.lproj/LaunchScreen.storyboard');
  if (generated.existsSync()) {
    generated.deleteSync();
  }

  final launchScreen = File(
    'ios/Runner/Base.lproj/GolemLaunchScreen.storyboard',
  );
  if (!launchScreen.existsSync()) {
    throw StateError('GolemLaunchScreen.storyboard is missing.');
  }
  final storyboard = launchScreen.readAsStringSync();
  if (!storyboard.contains('red="0.02352941176"') ||
      storyboard.contains('<imageView')) {
    throw StateError(
      'GolemLaunchScreen.storyboard must stay a solid Golem-navy screen '
      'with no launch image.',
    );
  }

  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  if (!plist.contains(
    '<key>UILaunchStoryboardName</key>\n\t\t<string>GolemLaunchScreen</string>',
  )) {
    throw StateError('Info.plist must select GolemLaunchScreen.');
  }
}
