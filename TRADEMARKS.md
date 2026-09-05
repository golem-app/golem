# Golem name and brand assets

The code in this repository is free software under the GNU Affero General
Public License, version 3 only (`AGPL-3.0-only`, see [`LICENSE`](LICENSE)).
The things that identify Golem are not part of that grant.

## What is reserved

Copyright © 2026 Jan Slominski. All rights reserved for:

- the names **Golem**, **GOLEM**, and **GOLEM.app**, and the `golem.app`
  domain, when used as the name of this application or of a service built
  on it;
- the Golem mascot and every launcher, app-icon, Dock, splash, and in-app
  identity artwork derived from it. In the tree that is:
  - `app/assets/source/` (the 1024 px masters),
  - `app/assets/images/golem_*.png`,
  - `app/ios/Runner/Assets.xcassets/AppIcon-*.appiconset/`,
  - `app/macos/Runner/Assets.xcassets/AppIcon-*.appiconset/`,
  - the Android launcher and splash resources under
    `app/android/app/src/*/res/` (`mipmap-*` and the adaptive-icon and
    splash drawables),
  - everything `app/tool/prepare_launcher.dart`, `flutter_launcher_icons`,
    and `flutter_native_splash` generate from those masters.

These files are in the repository so that the project builds and its tests
run. They are not licensed under the AGPL or under any other open-source
license.

## What you may do

- Build, run, test, and modify Golem from this repository for yourself,
  including on your own devices, with the artwork in place.
- Contribute changes back (see [`CONTRIBUTING.md`](CONTRIBUTING.md)).
- Refer to Golem by name to say truthfully that your software is derived
  from it, is compatible with it, or was tested against it.

## What you may not do without written permission

- Distribute a modified version — through an app store, a website, a
  package, or otherwise — under the Golem name or with the Golem mascot or
  icon artwork, or in any way that suggests it is Golem or is endorsed by
  Golem's maintainer.
- Use the names or the artwork as, or as part of, the name or logo of
  another product, service, company, or domain.

A fork you distribute needs its own name and its own artwork. The identity
is declared in `app/lib/core/app_identity.dart` and in the per-flavor Xcode,
Gradle, and launcher configurations; `app/test/platform_assets_test.dart`
pins today's artwork, so a rebrand also updates those guards.

Questions and permission requests: open an issue in this repository.
