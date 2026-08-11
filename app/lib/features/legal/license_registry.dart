import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A native or model artifact whose license is not discovered by Flutter's
/// Dart-package license collector.
final class BundledLicenseDeclaration {
  const BundledLicenseDeclaration({
    required this.identity,
    required this.displayName,
    required this.revision,
    required this.assetPaths,
  });

  final String identity;
  final String displayName;
  final String revision;
  final List<String> assetPaths;
}

const swiftPackageLicenseDeclarations = <BundledLicenseDeclaration>[
  BundledLicenseDeclaration(
    identity: 'eventsource',
    displayName: 'EventSource',
    revision: 'a3a85a85214caf642abaa96ae664e4c772a59f6e',
    assetPaths: ['assets/licenses/eventsource-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'mlx-swift',
    displayName: 'mlx-swift',
    revision: '0bb916c67f4b9e5c682cbe02a42c701c93ab5021',
    assetPaths: ['assets/licenses/mlx-swift-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'mlx-swift-lm',
    displayName: 'mlx-swift-lm',
    revision: '60bd0d7880c82980f9481f8be78862e9b63c58a3',
    assetPaths: ['assets/licenses/mlx-swift-lm-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-argument-parser',
    displayName: 'swift-argument-parser',
    revision: '6a52f3251125d74daf04fcbd5e6f08a75d074382',
    assetPaths: ['assets/licenses/swift-argument-parser-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-asn1',
    displayName: 'swift-asn1',
    revision: 'a9a5efd40eaf558a2bcd48d64b1d1646be686008',
    assetPaths: [
      'assets/licenses/swift-asn1-license.txt',
      'assets/licenses/swift-asn1-notice.txt',
    ],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-atomics',
    displayName: 'swift-atomics',
    revision: '0442cb5a3f98ab802acb777929fdb446bda11a34',
    assetPaths: ['assets/licenses/swift-atomics-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-collections',
    displayName: 'swift-collections',
    revision: 'a0cb0954ecb21e4e31b0070e6ed5674e8556685a',
    assetPaths: ['assets/licenses/swift-collections-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-crypto',
    displayName: 'swift-crypto',
    revision: '47d3869a7291f085c1fb9fb1e6d3b97a793f45c6',
    assetPaths: [
      'assets/licenses/swift-crypto-license.txt',
      'assets/licenses/swift-crypto-notice.txt',
    ],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-huggingface',
    displayName: 'swift-huggingface',
    revision: 'b721959445b617d0bf03910b2b4aced345fd93bf',
    assetPaths: ['assets/licenses/swift-huggingface-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-jinja',
    displayName: 'swift-jinja',
    revision: '7d0b8880ef8e567dd4e0089f8b99fb354129017c',
    assetPaths: ['assets/licenses/swift-jinja-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-nio',
    displayName: 'swift-nio',
    revision: '0b18836bd8b0162e7e17a995a3fbee20ed8f3b2b',
    assetPaths: [
      'assets/licenses/swift-nio-license.txt',
      'assets/licenses/swift-nio-notice.txt',
    ],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-numerics',
    displayName: 'swift-numerics',
    revision: '0c0290ff6b24942dadb83a929ffaaa1481df04a2',
    assetPaths: ['assets/licenses/swift-numerics-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-syntax',
    displayName: 'swift-syntax',
    revision: '79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1',
    assetPaths: ['assets/licenses/swift-syntax-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-system',
    displayName: 'swift-system',
    revision: '50688cacbd41d547e9eb9f7a213542340b7c442b',
    assetPaths: ['assets/licenses/swift-system-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'swift-transformers',
    displayName: 'swift-transformers',
    revision: '2fa33e1f5e7131a7fc64c28e6d161dcec0d24820',
    assetPaths: ['assets/licenses/swift-transformers-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'yyjson',
    displayName: 'yyjson',
    revision: '8b4a38dc994a110abaec8a400615567bd996105f',
    assetPaths: ['assets/licenses/yyjson-license.txt'],
  ),
];

const llamaCppRevision = '9bd4c09ea571a9020f30eeef169b552625b5b5a4';

const llamaLicenseDeclarations = <BundledLicenseDeclaration>[
  BundledLicenseDeclaration(
    identity: 'llama.cpp',
    displayName: 'llama.cpp',
    revision: llamaCppRevision,
    assetPaths: ['assets/licenses/llama-cpp-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'nlohmann-json',
    displayName: 'nlohmann/json',
    revision: llamaCppRevision,
    assetPaths: ['assets/licenses/nlohmann-json-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'stb',
    displayName: 'stb_image',
    revision: llamaCppRevision,
    assetPaths: ['assets/licenses/stb-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'miniaudio',
    displayName: 'miniaudio',
    revision: llamaCppRevision,
    assetPaths: ['assets/licenses/miniaudio-license.txt'],
  ),
];

const modelLicenseDeclarations = <BundledLicenseDeclaration>[
  BundledLicenseDeclaration(
    identity: 'gemma-4-e2b',
    displayName: 'Gemma 4 E2B model',
    revision: 'Apache-2.0',
    assetPaths: ['assets/licenses/model-apache-2.0-license.txt'],
  ),
  BundledLicenseDeclaration(
    identity: 'qwen-3.5',
    displayName: 'Qwen 3.5 models',
    revision: 'Apache-2.0',
    assetPaths: ['assets/licenses/model-apache-2.0-license.txt'],
  ),
];

const bundledLicenseDeclarations = <BundledLicenseDeclaration>[
  ...swiftPackageLicenseDeclarations,
  ...llamaLicenseDeclarations,
  ...modelLicenseDeclarations,
];

/// Adds only the licenses Flutter cannot discover from pub packages. The
/// callback remains lazy: bundled text is loaded only if the user opens the
/// licenses screen.
void registerGolemLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final declaration in bundledLicenseDeclarations) {
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
