#!/usr/bin/env bash
# Build, sign and install one Golem flavor on a physical device — the only
# sanctioned way to do it. Every step is gated: a failed xcodebuild, a stale
# Runner.app left over from an earlier build, or a bundle id that does not
# match the flavor stops the run before anything reaches the phone (a masked
# failure once installed a morning-old binary for QA, #143). The git commit
# is stamped into the build and shown in Settings ▸ About.
#
#   tool/device_install.sh ios     <qa|dev|production> <devicectl-UUID> [--dart-define=...]...
#   tool/device_install.sh android <qa|dev|production> <adb-serial>     [--dart-define=...]...
#
# Run from the repo root. Signing reads DEVELOPMENT_TEAM from
# ../ios/Configuration/LocalSigning.xcconfig (gitignored) unless GOLEM_TEAM is set.
set -euo pipefail

platform=${1:?ios|android}; flavor=${2:?qa|dev|production}; device=${3:?device id}; shift 3
case "$flavor" in
  qa) bundle=app.golem.qa ;; dev) bundle=app.golem.dev ;; production) bundle=app.golem ;;
  *) echo "unknown flavor: $flavor" >&2; exit 2 ;;
esac
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/app"
stamp="$(git rev-parse --short HEAD)$(git diff --quiet || echo '+')"
defines=(--dart-define=GOLEM_BUILD_STAMP="$stamp" "$@")
started=$(date +%s)

fresh() { # fail unless $1 exists and was written after this run began
  [ -e "$1" ] || { echo "missing artifact: $1" >&2; exit 1; }
  [ "$(stat -f %m "$1")" -ge "$started" ] || { echo "stale artifact (older than this run): $1" >&2; exit 1; }
}

case "$platform" in
  ios)
    team=${GOLEM_TEAM:-$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$root/../ios/Configuration/LocalSigning.xcconfig")}
    [ -n "$team" ] || { echo "no DEVELOPMENT_TEAM" >&2; exit 1; }
    products="build/DerivedData-Device/Build/Products/Release-$flavor-iphoneos"
    rm -rf "$products"   # a previous build can never be what gets installed
    fvm flutter build ios --release --no-codesign --flavor "$flavor" "${defines[@]}"
    build() {
      xcodebuild -workspace ios/Runner.xcworkspace -scheme "$flavor" \
        -configuration "Release-$flavor" -destination "platform=iOS,id=$device" \
        -derivedDataPath build/DerivedData-Device -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic COMPILER_INDEX_STORE_ENABLE=NO \
        build 2>&1 | tee build/device_install_xcodebuild.log | grep -E '^\*\* BUILD|error:' || true
      grep -q '^\*\* BUILD SUCCEEDED' build/device_install_xcodebuild.log
    }
    if ! build; then
      if grep -q 'has been modified since the module file' build/device_install_xcodebuild.log; then
        echo "stale precompiled modules after an SDK change — clearing and rebuilding once"
        rm -rf build/DerivedData-Device/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules
        build
      else
        exit 1
      fi
    fi
    app="$products/Runner.app"
    fresh "$app/Runner"
    actual=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
    [ "$actual" = "$bundle" ] || { echo "bundle id $actual is not $bundle — not installing" >&2; exit 1; }
    xcrun devicectl device install app --device "$device" "$app"
    ;;
  android)
    apk="build/app/outputs/flutter-apk/app-$flavor-release.apk"
    rm -f "$apk"
    fvm flutter build apk --release --flavor "$flavor" "${defines[@]}"
    fresh "$apk"
    actual=$(unzip -p "$apk" AndroidManifest.xml 2>/dev/null | strings | grep -m1 -o 'app\.golem[a-z.]*' || true)
    adb -s "$device" install -r "$apk"
    adb -s "$device" shell pm list packages | grep -qx "package:$bundle" || { echo "$bundle not installed" >&2; exit 1; }
    ;;
  *) echo "unknown platform: $platform" >&2; exit 2 ;;
esac
echo "installed $bundle ($flavor) on $device — build stamp $stamp"
