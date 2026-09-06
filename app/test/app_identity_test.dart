import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/app_identity.dart';

void main() {
  test('flavors map to their shipped identities', () {
    expect(AppIdentity.forFlavor('production'), AppIdentity.production);
    expect(AppIdentity.forFlavor('qa'), AppIdentity.qa);
    expect(AppIdentity.forFlavor('dev'), AppIdentity.dev);
    expect(AppIdentity.forFlavor('lab'), AppIdentity.lab);

    expect(AppIdentity.production.displayName, 'Golem');
    expect(AppIdentity.production.applicationId, 'app.golem');
    expect(AppIdentity.qa.displayName, 'Golem QA');
    expect(AppIdentity.qa.applicationId, 'app.golem.qa');
    expect(AppIdentity.dev.displayName, 'Golem Dev');
    expect(AppIdentity.dev.applicationId, 'app.golem.dev');
    expect(AppIdentity.lab.displayName, 'Golem Model Lab');
    expect(AppIdentity.lab.applicationId, 'app.golem.lab');
  });

  test('every identity names a bundled app-icon tile', () {
    expect(
      AppIdentity.production.iconAsset,
      'assets/images/golem_app_icon_production.png',
    );
    expect(AppIdentity.qa.iconAsset, 'assets/images/golem_app_icon_qa.png');
    expect(AppIdentity.dev.iconAsset, 'assets/images/golem_app_icon_dev.png');
    expect(AppIdentity.lab.iconAsset, 'assets/images/golem_app_icon_lab.png');
  });

  test('flavorless and unknown builds resolve to qa', () {
    // The bundle ids and artwork a flavorless build carries are qa's, so the
    // wiring has to be qa's too, or the app would contradict its own label.
    expect(AppIdentity.forFlavor(null), AppIdentity.qa);
    expect(AppIdentity.forFlavor('unknown'), AppIdentity.qa);
    // Host-side flutter test runs inherit the pubspec default flavor.
    expect(AppIdentity.current, AppIdentity.dev);
  });

  test('only the internal identities enable internal tools', () {
    expect(AppIdentity.dev.internalToolsEnabled, isTrue);
    expect(AppIdentity.qa.internalToolsEnabled, isTrue);
    expect(AppIdentity.lab.internalToolsEnabled, isTrue);
    expect(AppIdentity.production.internalToolsEnabled, isFalse);
  });

  test('the lab is the only lab identity, and host tests are not it', () {
    // kLabBuild is what keeps the bench out of every store build: it must be
    // a compile-time false everywhere but a `--flavor lab` build, and host
    // tests run as dev.
    expect(AppIdentity.lab.isLab, isTrue);
    for (final identity in AppIdentity.values.where(
      (i) => i != AppIdentity.lab,
    )) {
      expect(identity.isLab, isFalse, reason: identity.name);
    }
    expect(kLabBuild, isFalse);
    expect(AppIdentity.current.isLab, isFalse);
  });
}
