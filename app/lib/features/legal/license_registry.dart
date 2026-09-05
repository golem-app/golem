import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A native artifact whose license is not discovered by Flutter's Dart-package
/// license collector.
final class BundledLicenseDeclaration {
  const BundledLicenseDeclaration({
    required this.identity,
    required this.displayName,
    required this.revision,
    required this.kind,
    required this.assetPaths,
  });

  final String identity;
  final String displayName;

  /// The pinned upstream commit, mirrored from `Package.resolved` or the
  /// llama.cpp pin.
  final String revision;

  /// The SPDX expression, authored here rather than read back out of the
  /// text. These are known at pin time, and sniffing gets them wrong: two are
  /// dual-licensed and six carry the Swift runtime exception.
  /// `legal_surfaces_test.dart` holds each one to its own asset.
  final String kind;

  final List<String> assetPaths;
}

/// True when this build can link the MLX engine at all. It mirrors both halves
/// of the carrier's build condition in `hook/build.dart`: Apple **and** arm64.
/// MLX Swift is Apple-silicon-only, so an Intel Mac or an x64 simulator slice
/// links no carrier and must disclose no Swift graph.
///
/// `dart:io`'s [Platform] is the host truth; `defaultTargetPlatform` is not —
/// the golden harness overrides it through `TargetPlatformVariant`, so an
/// Android golden runs on a macOS host and would answer the wrong question.
bool get runningOnApplePlatform =>
    (Platform.isIOS || Platform.isMacOS) && _isAppleSilicon;

/// Dart exposes no target-architecture constant, so this reads the ABI token
/// [Platform.version] ends with — `on "macos_arm64"`. Rosetta reports the
/// emulated architecture, which is the right answer here: the x64 slice is
/// what was linked, and it carries no MLX carrier.
bool get _isAppleSilicon =>
    RegExp(r'on "\w+_arm64"').hasMatch(Platform.version);

const swiftPackageLicenseDeclarations = <BundledLicenseDeclaration>[
  BundledLicenseDeclaration(
    identity: 'eventsource',
    kind: 'MIT',
    displayName: 'EventSource',
    revision: 'a3a85a85214caf642abaa96ae664e4c772a59f6e',
    assetPaths: ['assets/licenses/eventsource-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'mlx-swift',
    kind: 'MIT',
    displayName: 'mlx-swift',
    revision: '0bb916c67f4b9e5c682cbe02a42c701c93ab5021',
    assetPaths: ['assets/licenses/mlx-swift-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'mlx-swift-lm',
    kind: 'MIT',
    displayName: 'mlx-swift-lm',
    revision: '60bd0d7880c82980f9481f8be78862e9b63c58a3',
    assetPaths: ['assets/licenses/mlx-swift-lm-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-argument-parser',
    kind: 'Apache-2.0 WITH Swift-exception',
    displayName: 'swift-argument-parser',
    revision: '6a52f3251125d74daf04fcbd5e6f08a75d074382',
    assetPaths: ['assets/licenses/swift-argument-parser-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-asn1',
    kind: 'Apache-2.0',
    displayName: 'swift-asn1',
    revision: 'a9a5efd40eaf558a2bcd48d64b1d1646be686008',
    assetPaths: [
      'assets/licenses/swift-asn1-license.txt',
      'assets/licenses/swift-asn1-notice.txt',
    ],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-atomics',
    kind: 'Apache-2.0 WITH Swift-exception',
    displayName: 'swift-atomics',
    revision: '0442cb5a3f98ab802acb777929fdb446bda11a34',
    assetPaths: ['assets/licenses/swift-atomics-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-collections',
    kind: 'Apache-2.0 WITH Swift-exception',
    displayName: 'swift-collections',
    revision: 'a0cb0954ecb21e4e31b0070e6ed5674e8556685a',
    assetPaths: ['assets/licenses/swift-collections-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-crypto',
    kind: 'Apache-2.0',
    displayName: 'swift-crypto',
    revision: '47d3869a7291f085c1fb9fb1e6d3b97a793f45c6',
    assetPaths: [
      'assets/licenses/swift-crypto-license.txt',
      'assets/licenses/swift-crypto-notice.txt',
    ],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-huggingface',
    kind: 'Apache-2.0',
    displayName: 'swift-huggingface',
    revision: 'b721959445b617d0bf03910b2b4aced345fd93bf',
    assetPaths: ['assets/licenses/swift-huggingface-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-jinja',
    kind: 'Apache-2.0',
    displayName: 'swift-jinja',
    revision: '7d0b8880ef8e567dd4e0089f8b99fb354129017c',
    assetPaths: ['assets/licenses/swift-jinja-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-nio',
    kind: 'Apache-2.0',
    displayName: 'swift-nio',
    revision: '0b18836bd8b0162e7e17a995a3fbee20ed8f3b2b',
    assetPaths: [
      'assets/licenses/swift-nio-license.txt',
      'assets/licenses/swift-nio-notice.txt',
    ],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-numerics',
    kind: 'Apache-2.0 WITH Swift-exception',
    displayName: 'swift-numerics',
    revision: '0c0290ff6b24942dadb83a929ffaaa1481df04a2',
    assetPaths: ['assets/licenses/swift-numerics-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-syntax',
    kind: 'Apache-2.0 WITH Swift-exception',
    displayName: 'swift-syntax',
    revision: '79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1',
    assetPaths: ['assets/licenses/swift-syntax-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-system',
    kind: 'Apache-2.0 WITH Swift-exception',
    displayName: 'swift-system',
    revision: '50688cacbd41d547e9eb9f7a213542340b7c442b',
    assetPaths: ['assets/licenses/swift-system-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-transformers',
    kind: 'Apache-2.0',
    displayName: 'swift-transformers',
    revision: '2fa33e1f5e7131a7fc64c28e6d161dcec0d24820',
    assetPaths: ['assets/licenses/swift-transformers-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'yyjson',
    kind: 'MIT',
    displayName: 'yyjson',
    revision: '8b4a38dc994a110abaec8a400615567bd996105f',
    assetPaths: ['assets/licenses/yyjson-license.txt'],
  ),
];

const llamaCppRevision = '9bd4c09ea571a9020f30eeef169b552625b5b5a4';

const llamaLicenseDeclarations = <BundledLicenseDeclaration>[
  BundledLicenseDeclaration(
    identity: 'llama.cpp',
    kind: 'MIT',
    displayName: 'llama.cpp',
    revision: llamaCppRevision,
    assetPaths: ['assets/licenses/llama-cpp-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'nlohmann-json',
    kind: 'MIT',
    displayName: 'nlohmann/json',
    revision: llamaCppRevision,
    assetPaths: ['assets/licenses/nlohmann-json-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'stb',
    kind: 'MIT OR Unlicense',
    displayName: 'stb_image',
    revision: llamaCppRevision,
    assetPaths: ['assets/licenses/stb-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'miniaudio',
    kind: 'Unlicense OR MIT-0',
    displayName: 'miniaudio',
    revision: llamaCppRevision,
    assetPaths: ['assets/licenses/miniaudio-license.txt'],
  ),
];

/// The declarations a build for this platform actually links, in reading
/// order. llama.cpp is compiled for every target; the Swift graph exists only
/// where `hook/build.dart` builds the MLX carrier, which is Apple-silicon-only
/// — an APK carries `libinferno.so` and nothing from that graph, so disclosing
/// it elsewhere would name software that is not there (#144).
///
/// `apple: true` is also the full inventory, which is what the drift tests and
/// the asset guards iterate. Model weights are deliberately absent: they are
/// downloaded from Hugging Face after consent rather than redistributed, so no
/// bundled-notice obligation attaches to them, and the Model attribution
/// screen names their license and links the canonical text (ADR 0009).
List<BundledLicenseDeclaration> bundledLicenseDeclarationsFor({
  required bool apple,
}) => List.unmodifiable([
  ...llamaLicenseDeclarations,
  if (apple) ...swiftPackageLicenseDeclarations,
]);

/// Adds only the licenses Flutter cannot discover from pub packages. The
/// callback remains lazy: bundled text is loaded only if the user opens the
/// licenses screen.
void registerGolemLicenses({bool? apple}) {
  final declarations = bundledLicenseDeclarationsFor(
    apple: apple ?? runningOnApplePlatform,
  );
  LicenseRegistry.addLicense(() async* {
    for (final declaration in declarations) {
      final documents = <String>[];
      for (final assetPath in declaration.assetPaths) {
        documents.add(await rootBundle.loadString(assetPath));
      }
      yield LicenseEntryWithLineBreaks(<String>[
        declaration.displayName,
      ], documents.join('\n\n'));
    }
  });
}

/// Direct runtime dependencies of `app/pubspec.yaml`, the packages a reader
/// looks for by name. Two manifest entries are absent on purpose: `inferno`
/// is first-party — its AGPL text is the repository's, not a third-party
/// notice this screen discloses — and `flutter_localizations` is an SDK
/// package whose notice Flutter's collector files under `flutter`, so no
/// registry entry could fill that name.
/// `legal_surfaces_test.dart` holds this list to the manifest, so a new
/// dependency has to be placed here deliberately.
const directRuntimeLicensePackages = <String>[
  'flutter',
  'intl',
  'cupertino_icons',
  'flutter_riverpod',
  'riverpod_annotation',
  'go_router',
  'path_provider',
  'share_plus',
  'background_downloader',
  'crypto',
  'url_launcher',
  'markdown',
  'highlight',
  'image_picker',
  'file_selector',
];

/// Everything the licenses screen discloses on this platform, in reading
/// order: the engine Golem runs, the Swift graph the MLX engine links where
/// it exists, then the packages the app itself declares. Assembled from the
/// explicit manifests and nothing else — Flutter's collector also sweeps the
/// engine's `third_party` tree and every dev-time package in the graph, and
/// none of that is software Golem chose (#144).
List<String> declaredLicensePackagesFor({required bool apple}) =>
    List.unmodifiable([
      for (final declaration in bundledLicenseDeclarationsFor(apple: apple))
        declaration.displayName,
      ...directRuntimeLicensePackages,
    ]);
