import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _llamaRevision = '9bd4c09ea571a9020f30eeef169b552625b5b5a4';
const _llamaArchiveSha256 =
    '1833544741959404b16b4f9cc407be5bbf3abbebb6b97e6fff516fe3dc2513d5';
const _androidNdkVersion = '29.0.14206865';

Future<void> main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final config = input.config.code;
    if (![OS.android, OS.iOS, OS.linux, OS.macOS].contains(config.targetOS)) {
      throw UnsupportedError(
        'Inferno does not support ${config.targetOS} code assets.',
      );
    }

    final source = await _llamaSource(input.outputDirectoryShared);
    // CMake keeps the compiler it first cached and will not swap it inside an
    // existing build directory, so the toolchain has to be part of the key or
    // an NDK bump silently relinks the previous compiler's objects.
    final targetKey = [
      config.targetOS,
      config.targetArchitecture,
      if (config.targetOS == OS.iOS) config.iOS.targetSdk,
      if (config.targetOS == OS.android) 'ndk$_androidNdkVersion',
    ].join('-');
    final buildDirectory = Directory.fromUri(
      input.outputDirectoryShared.resolve('llama-build-$targetKey/'),
    );
    final outputDirectory = Directory.fromUri(input.outputDirectory);
    await buildDirectory.create(recursive: true);
    await outputDirectory.create(recursive: true);

    final cmakeArguments = <String>[
      '-S',
      input.packageRoot.resolve('native/llama/').toFilePath(),
      '-B',
      buildDirectory.path,
      '-DLLAMA_SOURCE_DIR=${source.path}',
      '-DINFERNO_OUTPUT_DIR=${outputDirectory.path}',
      '-DCMAKE_BUILD_TYPE=Release',
      ...await _targetCmakeArguments(config),
    ];
    await _run('cmake', cmakeArguments);
    await _run('cmake', [
      '--build',
      buildDirectory.path,
      '--config',
      'Release',
      '--target',
      'inferno',
      // A bare --parallel forwards an unbounded -j to the native tool;
      // llama.cpp's heaviest translation units then OOM small CI runners.
      '--parallel',
      '${Platform.numberOfProcessors}',
    ]);

    final library = File(
      '${outputDirectory.path}/${config.targetOS.libraryFileName('inferno', DynamicLoadingBundled())}',
    );
    if (!await library.exists()) {
      throw StateError('CMake did not produce ${library.path}.');
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'inferno.dart',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
    // MLX Swift is Apple-silicon-only. Flutter still runs the hook for x64
    // simulator slices, so skip the carrier there instead of failing; app
    // projects exclude those slices from linking (EXCLUDED_ARCHS) and no
    // supported Apple device runs Inferno on x64.
    if ((config.targetOS == OS.iOS || config.targetOS == OS.macOS) &&
        config.targetArchitecture == Architecture.arm64) {
      final mlxLibrary = await _buildMlxCarrier(
        input.packageRoot,
        input.outputDirectoryShared,
        outputDirectory,
        config,
      );
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'inferno_mlx.dart',
          linkMode: DynamicLoadingBundled(),
          file: mlxLibrary.uri,
        ),
      );
    }
    output.dependencies.addAll([
      input.packageRoot.resolve('native/llama/CMakeLists.txt'),
      input.packageRoot.resolve('native/src/llama_shim.cpp'),
      input.packageRoot.resolve('native/include/inferno.h'),
      input.packageRoot.resolve('native/apple/Package.swift'),
      input.packageRoot.resolve('native/apple/Package.resolved'),
      input.packageRoot.resolve(
        'native/apple/Sources/InfernoMLXCarrier/InfernoMLXShim.swift',
      ),
    ]);
  });
}

Future<File> _buildMlxCarrier(
  Uri packageRoot,
  Uri sharedOutput,
  Directory outputDirectory,
  CodeConfig config,
) async {
  // MLX Swift runs on Apple silicon only; an Intel slice can never link the
  // carrier. Fail with intent instead of a deep SwiftPM macro error — app
  // projects must exclude x86_64 simulator slices (EXCLUDED_ARCHS).
  final architecture = switch (config.targetArchitecture) {
    Architecture.arm64 => 'arm64',
    final unsupported => throw UnsupportedError(
      'MLX requires Apple silicon; cannot build the carrier for $unsupported.',
    ),
  };
  final sdk = config.targetOS == OS.iOS
      ? config.iOS.targetSdk.toString()
      : 'macosx';
  final destination = switch (sdk) {
    'iphoneos' => 'generic/platform=iOS',
    'iphonesimulator' => 'generic/platform=iOS Simulator',
    _ => 'generic/platform=macOS',
  };
  final derivedData = Directory.fromUri(
    sharedOutput.resolve('mlx-build-$sdk-$architecture/'),
  );
  await derivedData.create(recursive: true);
  await _run(
    'xcodebuild',
    [
      'build',
      '-quiet',
      '-scheme',
      'InfernoMLXCarrier',
      '-configuration',
      'Release',
      '-destination',
      destination,
      '-derivedDataPath',
      derivedData.path,
      '-skipPackagePluginValidation',
      '-skipMacroValidation',
      'CODE_SIGNING_ALLOWED=NO',
      'BUILD_LIBRARY_FOR_DISTRIBUTION=NO',
      'ARCHS=$architecture',
      'ONLY_ACTIVE_ARCH=YES',
    ],
    workingDirectory: Directory.fromUri(packageRoot.resolve('native/apple/')),
  );

  final configurationDirectory = sdk == 'macosx' ? 'Release' : 'Release-$sdk';
  final products = Directory(
    '${derivedData.path}/Build/Products/$configurationDirectory',
  );
  final frameworkBinary = File(
    '${products.path}/PackageFrameworks/'
    'InfernoMLXCarrier.framework/InfernoMLXCarrier',
  );
  if (!await frameworkBinary.exists()) {
    throw StateError('Xcode did not produce ${frameworkBinary.path}.');
  }
  final library = File('${outputDirectory.path}/libinferno_mlx.dylib');
  await frameworkBinary.copy(library.path);

  // MLX's SwiftPM build resolves its Metal library and tokenizer defaults
  // from resource bundles beside the application. The Flutter Xcode target
  // stages these deterministic build products after native assets are copied.
  final stagedResources = Directory.fromUri(
    packageRoot.resolve('build/apple-resources/$sdk/'),
  );
  if (await stagedResources.exists()) {
    await stagedResources.delete(recursive: true);
  }
  await stagedResources.create(recursive: true);
  await for (final entity in products.list()) {
    if (entity is Directory && entity.path.endsWith('.bundle')) {
      await _copyDirectory(
        entity,
        Directory(
          '${stagedResources.path}/${entity.uri.pathSegments.where((part) => part.isNotEmpty).last}',
        ),
      );
    }
  }
  return library;
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list()) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (entity is Directory) {
      await _copyDirectory(entity, Directory('${destination.path}/$name'));
    } else if (entity is File) {
      await entity.copy('${destination.path}/$name');
    }
  }
}

Future<Directory> _llamaSource(Uri sharedOutput) async {
  final destination = Directory.fromUri(
    sharedOutput.resolve('llama.cpp-$_llamaRevision/'),
  );
  if (await destination.exists()) return destination;

  final nonce = '$pid-${DateTime.now().microsecondsSinceEpoch}';
  final archive = File.fromUri(sharedOutput.resolve('llama-$nonce.tar.gz'));
  final extraction = Directory.fromUri(sharedOutput.resolve('extract-$nonce/'));
  await extraction.create(recursive: true);
  try {
    final request = await HttpClient().getUrl(
      Uri.parse(
        'https://github.com/ggml-org/llama.cpp/archive/$_llamaRevision.tar.gz',
      ),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'llama.cpp archive returned HTTP ${response.statusCode}.',
      );
    }
    final sink = archive.openWrite();
    await response.pipe(sink);
    final digest = await sha256.bind(archive.openRead()).first;
    if (digest.toString() != _llamaArchiveSha256) {
      throw StateError('llama.cpp archive SHA-256 mismatch.');
    }
    await _run('tar', ['-xzf', archive.path, '-C', extraction.path]);
    final extracted = Directory('${extraction.path}/llama.cpp-$_llamaRevision');
    try {
      await extracted.rename(destination.path);
    } on FileSystemException {
      if (!await destination.exists()) rethrow;
    }
    return destination;
  } finally {
    if (await archive.exists()) await archive.delete();
    if (await extraction.exists()) await extraction.delete(recursive: true);
  }
}

/// Flutter resolves the Android NDK by taking the newest one installed, so
/// without a pin the compiler behind every shipped ggml kernel changes with
/// whatever the machine happens to have — and before r28 the shipped library
/// silently loses the 16 KB page alignment Play requires. Refuse rather than
/// build something unverified.
void _requirePinnedNdk(String ndk) {
  final properties = File('$ndk/source.properties');
  if (!properties.existsSync()) {
    throw StateError('The Android NDK at $ndk has no source.properties.');
  }
  final revision = RegExp(
    r'^Pkg\.Revision\s*=\s*(.+)$',
    multiLine: true,
  ).firstMatch(properties.readAsStringSync())?.group(1)?.trim();
  if (revision == _androidNdkVersion) return;
  throw StateError(
    'Inferno pins Android NDK $_androidNdkVersion, but Flutter selected '
    '$revision at $ndk. Install the pinned revision with '
    '`sdkmanager "ndk;$_androidNdkVersion"`, or select it explicitly with '
    'ANDROID_NDK_HOME.',
  );
}

Future<List<String>> _targetCmakeArguments(CodeConfig config) async {
  final architecture = switch (config.targetArchitecture) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x86_64',
    Architecture.arm => 'armv7',
    final unsupported => throw UnsupportedError(
      'Unsupported Inferno architecture $unsupported.',
    ),
  };
  if (config.targetOS == OS.android) {
    final compiler = config.cCompiler?.compiler.toFilePath();
    if (compiler == null || !compiler.contains('/toolchains/')) {
      throw StateError('The Android NDK compiler configuration is missing.');
    }
    final ndk = compiler.substring(0, compiler.indexOf('/toolchains/'));
    _requirePinnedNdk(ndk);
    final abi = switch (config.targetArchitecture) {
      Architecture.arm64 => 'arm64-v8a',
      Architecture.x64 => 'x86_64',
      Architecture.arm => 'armeabi-v7a',
      final unsupported => throw UnsupportedError(
        'Unsupported Android architecture $unsupported.',
      ),
    };
    return [
      '-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake',
      '-DANDROID_ABI=$abi',
      '-DANDROID_PLATFORM=android-${config.android.targetNdkApi}',
      // Inferno is emitted as one native asset. Linking the NDK runtime
      // statically avoids a second, unregistered code asset dependency.
      '-DANDROID_STL=c++_static',
      // With GGML_NATIVE off (cross-compile), ggml only emits dotprod
      // kernels when the arch says so; the toolchain baseline (armv8-a)
      // leaves them off. Exactly one extension over that baseline, because
      // ggml picks ARM kernels at compile time and this build ships as a
      // single static asset — every instruction here is a hard requirement
      // on every device that installs the APK, enforced at load by the
      // shim's HWCAP check (docs/device_floor.md). i8mm is deliberately
      // not enabled: it would emit SMMLA and raise the floor to armv8.6,
      // excluding armv8.2 parts (Snapdragon 855/865/888-class) that are
      // squarely inside the supported 8 GB tier. Neither is the armv8.2-a
      // baseline itself, whose mandatory LSE atomics land in ggml_barrier
      // and would trap on armv8.0 devices.
      if (config.targetArchitecture == Architecture.arm64)
        '-DGGML_CPU_ARM_ARCH=armv8-a+dotprod',
    ];
  }
  if (config.targetOS == OS.iOS) {
    final sdk = config.iOS.targetSdk.toString();
    final result = await Process.run('xcrun', [
      '--sdk',
      sdk,
      '--show-sdk-path',
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'xcrun',
        [],
        result.stderr as String,
        result.exitCode,
      );
    }
    return [
      '-DCMAKE_SYSTEM_NAME=iOS',
      '-DCMAKE_OSX_SYSROOT=${(result.stdout as String).trim()}',
      '-DCMAKE_OSX_ARCHITECTURES=$architecture',
      '-DCMAKE_OSX_DEPLOYMENT_TARGET=${config.iOS.targetVersion}.0',
      '-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO',
    ];
  }
  if (config.targetOS == OS.macOS) {
    return [
      '-DCMAKE_OSX_ARCHITECTURES=$architecture',
      '-DCMAKE_OSX_DEPLOYMENT_TARGET=${config.macOS.targetVersion}.0',
    ];
  }
  final compiler = config.cCompiler;
  if (compiler == null) return const [];
  final cCompiler = compiler.compiler.toFilePath();
  final cxxCompiler = cCompiler.endsWith('clang')
      ? '$cCompiler++'
      : cCompiler.endsWith('gcc')
      ? '${cCompiler.substring(0, cCompiler.length - 3)}g++'
      : cCompiler;
  return [
    '-DCMAKE_C_COMPILER=$cCompiler',
    '-DCMAKE_CXX_COMPILER=$cxxCompiler',
    '-DCMAKE_AR=${compiler.archiver.toFilePath()}',
  ];
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  Directory? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory?.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(executable, arguments, 'Command failed.', exitCode);
  }
}
