import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/app_identity.dart';

void main() {
  test('flavors map to their shipped identities', () {
    expect(AppIdentity.forFlavor('production'), AppIdentity.production);
    expect(AppIdentity.forFlavor('qa'), AppIdentity.qa);
    expect(AppIdentity.forFlavor('dev'), AppIdentity.dev);

    expect(AppIdentity.production.displayName, 'Golem');
    expect(AppIdentity.production.applicationId, 'app.golem');
    expect(AppIdentity.qa.displayName, 'Golem QA');
    expect(AppIdentity.qa.applicationId, 'app.golem.qa');
    expect(AppIdentity.dev.displayName, 'Golem Dev');
    expect(AppIdentity.dev.applicationId, 'app.golem.dev');
  });

  test('every identity names a bundled app-icon tile', () {
    expect(
      AppIdentity.production.iconAsset,
      'assets/images/golem_app_icon_production.png',
    );
    expect(AppIdentity.qa.iconAsset, 'assets/images/golem_app_icon_qa.png');
    expect(AppIdentity.dev.iconAsset, 'assets/images/golem_app_icon_dev.png');
    // No tile is generated for the flavorless identity; it shows the
    // production artwork, as its macOS catalog does.
    expect(
      AppIdentity.flutter.iconAsset,
      'assets/images/golem_app_icon_production.png',
    );
  });

  test('flavorless and unknown builds resolve to the legacy identity', () {
    expect(AppIdentity.forFlavor(null), AppIdentity.flutter);
    expect(AppIdentity.forFlavor('unknown'), AppIdentity.flutter);
    expect(AppIdentity.flutter.displayName, 'Golem Flutter');
    expect(AppIdentity.flutter.applicationId, 'app.golem.flutter');
    // Host-side flutter test runs inherit the pubspec default flavor.
    expect(AppIdentity.current, AppIdentity.dev);
  });
}
