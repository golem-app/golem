import 'dart:io';
import 'dart:typed_data';

/// Checks a built Android artifact against Play's native-library rules.
///
/// Play requires every 64-bit shared library in an app targeting API 35+ to
/// support 16 KB memory pages: each `PT_LOAD` segment aligned to at least
/// 16384 and, in an APK, stored uncompressed on a 16 KB boundary. Nothing in a
/// Flutter build states any of that — it falls out of NDK and AGP defaults, so
/// it needs checking rather than assuming.
///
/// Also asserts what the bundle must and must not carry: exactly the shipped
/// ABI (a stray plugin library under another ABI makes Play offer the app to
/// devices with no Flutter engine to run it), the crash-symbolication uploads
/// Play warns about when they are missing, and no model weights — those
/// download after install.
///
/// Usage: `dart run tool/check_android_packaging.dart [artifact ...]` from the
/// repo root. With no arguments it checks the production release bundle and
/// APK. Release-time and pin-bump-time, like `verify_pins.dart`; the CI-side
/// guard is `android_packaging_test.dart` over the build files themselves.
void main(List<String> arguments) {
  final artifacts = arguments.isEmpty ? _defaultArtifacts : arguments;
  final problems = <String>[];

  for (final path in artifacts) {
    final file = File(path);
    if (!file.existsSync()) {
      problems.add(
        '$path is missing. Build it first, from app/:\n'
        '  flutter build appbundle --release --flavor production\n'
        '  flutter build apk --release --flavor production',
      );
      continue;
    }
    try {
      problems.addAll(_check(file));
    } on Object catch (error) {
      // A structural surprise in one artifact must not cost the diagnostics
      // already gathered for the other.
      problems.add('$path could not be parsed: $error');
    }
  }

  if (problems.isEmpty) {
    stdout.writeln(
      '\nEvery checked artifact satisfies the Play native-library rules that '
      'apply to it.',
    );
    return;
  }
  stderr.writeln('');
  for (final problem in problems) {
    stderr.writeln(problem);
  }
  exitCode = 1;
}

const _defaultArtifacts = [
  'app/build/app/outputs/bundle/productionRelease/app-production-release.aab',
  'app/build/app/outputs/flutter-apk/app-production-release.apk',
];

/// Play's page-size rule binds on 64-bit devices only; a 32-bit library links
/// at its toolchain baseline and is reported without being enforced.
const _sixtyFourBitAbis = {'arm64-v8a', 'x86_64'};

/// What every Android build carries: `defaultConfig.ndk.abiFilters` is
/// arm64-only for all flavors, so no emulator or local build produces another
/// ABI either; the Inferno hook still knows how to cross-compile the rest and
/// nothing packages them (docs/decisions/0010-android-native-packaging.md,
/// docs/device_floor.md).
const _shippedAbis = {'arm64-v8a'};

const _pageSize = 16384;

/// Play's limit on the native debug symbols file
/// (developer.android.com/build/include-native-symbols).
const _symbolCeiling = 1600 * 1024 * 1024;

const _weightSuffixes = ['.gguf', '.safetensors'];

const _symbolPrefix = 'BUNDLE-METADATA/com.android.tools.build.debugsymbols/';
const _mappingEntry =
    'BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map';

List<String> _check(File file) {
  final problems = <String>[];
  final bytes = file.readAsBytesSync();
  final entries = _centralDirectory(bytes);
  final bundle = file.path.endsWith('.aab');
  final prefix = bundle ? 'base/lib/' : 'lib/';

  stdout.writeln('\n${file.path}  (${_mib(bytes.length)} on disk)');

  for (final entry in entries) {
    if (_weightSuffixes.any(entry.name.endsWith)) {
      problems.add(
        '${file.path}: ${entry.name} packages model weights. Weights are '
        'downloaded after install; the artifact must not carry them.',
      );
    }
  }

  final libraries = entries
      .where((entry) => entry.name.startsWith(prefix))
      .where((entry) => entry.name.endsWith('.so'))
      .toList();
  if (libraries.isEmpty) {
    return [...problems, '${file.path}: no native libraries under $prefix.'];
  }

  final abis = <String>{};
  var libraryBytes = 0;
  for (final entry in libraries) {
    final abi = entry.name.substring(prefix.length).split('/').first;
    abis.add(abi);
    libraryBytes += entry.size;
    final enforced = _sixtyFourBitAbis.contains(abi);

    final worst = _loadAlignments(
      _inflate(bytes, entry),
    ).reduce((a, b) => a < b ? a : b);
    final aligned = worst >= _pageSize;

    // An APK's libraries are mapped straight out of the archive, so the zip
    // offset has to be page-aligned too. A bundle's entries are compressed and
    // Play re-packs them; BundleConfig below governs what it emits.
    final stored = bundle || entry.method == 0;
    final offsetAligned = bundle || _dataOffset(bytes, entry) % _pageSize == 0;

    final ok = !enforced || (aligned && stored && offsetAligned);
    stdout.writeln(
      '  ${ok ? "ok  " : "FAIL"} ${entry.name.padRight(38)}'
      ' LOAD align 2**${_log2(worst)}${enforced ? "" : "  (32-bit, exempt)"}',
    );

    if (!enforced) continue;
    if (!aligned) {
      problems.add(
        '${file.path}: ${entry.name} has a PT_LOAD segment aligned to $worst, '
        'below the $_pageSize Play requires on 64-bit devices.',
      );
    }
    if (!stored) {
      problems.add(
        '${file.path}: ${entry.name} is compressed in the archive. '
        'useLegacyPackaging must stay false so it is stored and page-aligned.',
      );
    }
    if (!offsetAligned) {
      problems.add(
        '${file.path}: ${entry.name} starts at a zip offset that is not a '
        'multiple of $_pageSize.',
      );
    }
  }

  // Uncompressed bytes of the libraries themselves — deliberately not called a
  // download size, which Play computes over the compressed split it generates.
  stdout.writeln(
    '  ABIs: ${_sorted(abis)}  (${_mib(libraryBytes)} of uncompressed .so)',
  );

  // The ABI set is declared in defaultConfig, so it is the same for every
  // flavor and both artifact kinds are held to it.
  if (!_setsEqual(abis, _shippedAbis)) {
    problems.add(
      '${file.path} carries ABIs ${_sorted(abis)}; Android builds carry '
      '${_sorted(_shippedAbis)}. An ABI present without a Flutter engine '
      'makes Play offer the app to devices that cannot start it.',
    );
  }

  if (!bundle) {
    // BundleConfig and the symbolication uploads exist only in the bundle
    // Play receives; an APK is a sideload artifact and is not held to them.
    stdout.writeln('  (APK: alignment, packaging and ABI set only)');
    return problems;
  }
  problems.addAll(_checkBundleConfig(file, bytes, entries));
  problems.addAll(_checkSymbolUploads(file, entries, abis));
  return problems;
}

/// Play regenerates the delivered APKs from the bundle, so the bundle's own
/// declared page alignment — not just the libraries inside it — decides what
/// lands on the device.
List<String> _checkBundleConfig(
  File file,
  Uint8List bytes,
  List<_Entry> entries,
) {
  final config = entries.where((entry) => entry.name == 'BundleConfig.pb');
  if (config.isEmpty) return ['${file.path}: BundleConfig.pb is missing.'];

  // BundleConfig.optimizations = 2, Optimizations.uncompress_native_libraries
  // = 2, UncompressNativeLibraries { enabled = 1; PageAlignment alignment = 2 }
  // with PAGE_ALIGNMENT_16K = 2 — bundletool's config.proto.
  final optimizations = _message(_inflate(bytes, config.first), 2);
  final uncompress = optimizations == null ? null : _message(optimizations, 2);
  if (uncompress == null) {
    return [
      '${file.path}: BundleConfig.pb declares no uncompressed-native-library '
          'optimization, so Play would compress and 4 KB-align the libraries.',
    ];
  }
  final enabled = _varintField(uncompress, 1) == 1;
  final alignment = _varintField(uncompress, 2);
  stdout.writeln(
    '  BundleConfig: uncompressed=$enabled alignment='
    '${alignment == 2 ? "PAGE_ALIGNMENT_16K" : alignment}',
  );
  if (enabled && alignment == 2) return const [];
  return [
    '${file.path}: BundleConfig.pb must declare uncompressed native libraries '
        'at PAGE_ALIGNMENT_16K; it declares enabled=$enabled '
        'alignment=$alignment.',
  ];
}

/// Native crash symbolication and R8 deobfuscation are AGP defaults, and Play
/// warns on a release that arrives without them.
List<String> _checkSymbolUploads(
  File file,
  List<_Entry> entries,
  Set<String> abis,
) {
  final problems = <String>[];
  final symbols = entries.where(
    (entry) => entry.name.startsWith(_symbolPrefix),
  );
  // Compressed, because the ceiling applies to the bytes Play receives; the
  // uncompressed total is roughly 2.5x that and would fail a valid release.
  final total = symbols.fold(0, (sum, entry) => sum + entry.compressedSize);
  final covered = symbols.map(
    (e) => e.name.substring(_symbolPrefix.length).split('/').first,
  );

  for (final abi in abis) {
    if (!covered.contains(abi)) {
      problems.add('${file.path}: no native debug symbols for $abi.');
    }
  }
  if (total > _symbolCeiling) {
    problems.add(
      '${file.path}: native debug symbols total ${_mib(total)}, above the '
      '${_mib(_symbolCeiling)} Play accepts. Keep debugSymbolLevel at '
      'SYMBOL_TABLE rather than FULL.',
    );
  }
  if (!entries.any((entry) => entry.name == _mappingEntry)) {
    problems.add('${file.path}: no R8 mapping file ($_mappingEntry).');
  }
  stdout.writeln(
    '  Symbolication: ${_mib(total)} of debug symbols, '
    'R8 mapping ${entries.any((e) => e.name == _mappingEntry) ? "present" : "MISSING"}',
  );
  return problems;
}

typedef _Entry = ({
  String name,
  int method,
  int compressedSize,
  int size,
  int headerOffset,
});

/// Reads the zip central directory. Deliberately hand-rolled rather than
/// shelling out: `zipalign` cannot read a bundle, `bundletool` is not a
/// checkout dependency, and neither exposes the entry offsets one of the
/// checks needs.
List<_Entry> _centralDirectory(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  // The record sits at the end, displaced by a comment of at most 64 KiB.
  final floor = bytes.length - 22 - 0xffff;
  var eocd = bytes.length - 22;
  while (eocd >= 0 &&
      eocd >= floor &&
      data.getUint32(eocd, Endian.little) != 0x06054b50) {
    eocd--;
  }
  if (eocd < 0 || eocd < floor) {
    throw StateError('No zip end-of-central-directory record.');
  }
  if (eocd >= 20 && data.getUint32(eocd - 20, Endian.little) == 0x07064b50) {
    throw StateError('Zip64 archives are not supported by this check.');
  }

  final count = data.getUint16(eocd + 10, Endian.little);
  var offset = data.getUint32(eocd + 16, Endian.little);
  final entries = <_Entry>[];
  for (var i = 0; i < count; i++) {
    if (data.getUint32(offset, Endian.little) != 0x02014b50) {
      throw StateError('Corrupt central directory entry at $offset.');
    }
    final nameLength = data.getUint16(offset + 28, Endian.little);
    final extraLength = data.getUint16(offset + 30, Endian.little);
    final commentLength = data.getUint16(offset + 32, Endian.little);
    entries.add((
      name: String.fromCharCodes(
        bytes.sublist(offset + 46, offset + 46 + nameLength),
      ),
      method: data.getUint16(offset + 10, Endian.little),
      compressedSize: data.getUint32(offset + 20, Endian.little),
      size: data.getUint32(offset + 24, Endian.little),
      headerOffset: data.getUint32(offset + 42, Endian.little),
    ));
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

/// The local header carries its own extra field, and that is where the aligner
/// inserts its padding — the central directory's extra field stays empty, so
/// the data offset can only be read here.
int _dataOffset(Uint8List bytes, _Entry entry) {
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(entry.headerOffset, Endian.little) != 0x04034b50) {
    throw StateError('Corrupt local header for ${entry.name}.');
  }
  return entry.headerOffset +
      30 +
      data.getUint16(entry.headerOffset + 26, Endian.little) +
      data.getUint16(entry.headerOffset + 28, Endian.little);
}

Uint8List _inflate(Uint8List bytes, _Entry entry) {
  final start = _dataOffset(bytes, entry);
  final raw = Uint8List.sublistView(bytes, start, start + entry.compressedSize);
  if (entry.method == 0) return raw;
  if (entry.method != 8) {
    throw StateError(
      '${entry.name} uses unsupported zip method '
      '${entry.method}.',
    );
  }
  return Uint8List.fromList(ZLibCodec(raw: true).decode(raw));
}

/// Alignment of every `PT_LOAD` program header — what the loader maps, and so
/// what the page-size rule constrains.
List<int> _loadAlignments(Uint8List elf) {
  final data = ByteData.sublistView(elf);
  if (data.getUint32(0, Endian.big) != 0x7f454c46) {
    throw StateError('Not an ELF file.');
  }
  final elf64 = elf[4] == 2;
  if (elf[5] != 1) {
    throw StateError('Only little-endian ELF files are supported.');
  }
  final headerOffset = elf64
      ? data.getUint64(0x20, Endian.little)
      : data.getUint32(0x1c, Endian.little);
  final entrySize = data.getUint16(elf64 ? 0x36 : 0x2a, Endian.little);
  final count = data.getUint16(elf64 ? 0x38 : 0x2c, Endian.little);

  final alignments = <int>[];
  for (var i = 0; i < count; i++) {
    final header = headerOffset + i * entrySize;
    if (data.getUint32(header, Endian.little) != 1) continue; // PT_LOAD
    alignments.add(
      elf64
          ? data.getUint64(header + 48, Endian.little)
          : data.getUint32(header + 28, Endian.little),
    );
  }
  if (alignments.isEmpty) throw StateError('ELF file has no PT_LOAD segments.');
  return alignments;
}

/// Minimal protobuf reads. Two nested field lookups do not justify a protobuf
/// dependency, but an unexpected wire type must fail loudly rather than read
/// as "aligned" — a bundletool schema change has to be visible.
Uint8List? _message(Uint8List bytes, int field) {
  final found = _seek(bytes, field, wireType: 2);
  return found == null ? null : bytes.sublist(found.start, found.end);
}

int? _varintField(Uint8List bytes, int field) =>
    _seek(bytes, field, wireType: 0)?.value;

({int start, int end, int value})? _seek(
  Uint8List bytes,
  int field, {
  required int wireType,
}) {
  var offset = 0;
  while (offset < bytes.length) {
    final key = _varint(bytes, offset);
    offset = key.end;
    final tag = key.value >> 3;
    final wire = key.value & 7;
    if (tag == field && wire != wireType) {
      throw StateError(
        'BundleConfig field $field has wire type $wire, expected $wireType.',
      );
    }
    switch (wire) {
      case 0:
        final value = _varint(bytes, offset);
        offset = value.end;
        if (tag == field) return (start: 0, end: 0, value: value.value);
      case 2:
        final length = _varint(bytes, offset);
        final start = length.end;
        offset = start + length.value;
        if (tag == field) return (start: start, end: offset, value: 0);
      case 5:
        offset += 4;
      case 1:
        offset += 8;
      default:
        throw StateError('Unsupported protobuf wire type $wire.');
    }
  }
  return null;
}

({int end, int value}) _varint(Uint8List bytes, int offset) {
  var value = 0;
  var shift = 0;
  while (true) {
    final byte = bytes[offset++];
    value |= (byte & 0x7f) << shift;
    shift += 7;
    if (byte & 0x80 == 0) return (end: offset, value: value);
  }
}

int _log2(int value) {
  var bits = 0;
  while (value > 1) {
    value >>= 1;
    bits++;
  }
  return bits;
}

bool _setsEqual(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

String _sorted(Set<String> values) => (values.toList()..sort()).join(', ');

String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
