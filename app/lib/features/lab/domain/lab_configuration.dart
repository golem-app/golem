import '../../../core/domain/model_catalog.dart';

/// The bench's initial catalog (#58): Gemma 4 E2B and Qwen 3.5 4B, each on
/// llama.cpp/GGUF and MLX. Named keys, not a count, so the bench derives how
/// many configurations it has from the catalog rather than assuming four —
/// a later addition joins by adding a key here and nothing else.
const labConfigurationKeys = <String>{
  'gemma4-gguf',
  'gemma4-mlx',
  'qwen35-gguf',
  'qwen35-mlx',
};

/// One thing the bench can arm: a pinned artifact on its engine.
final class LabConfiguration {
  const LabConfiguration(this.entry);

  final ModelCatalogEntry entry;

  String get key => entry.key;
  String get displayName => entry.displayName;
  ModelEngine get engine => entry.engine;
  String get profileKey => entry.profileKey;

  @override
  bool operator ==(Object other) =>
      other is LabConfiguration && other.entry == entry;

  @override
  int get hashCode => entry.hashCode;
}

/// The configurations the bench offers, in catalog order.
List<LabConfiguration> labConfigurations(List<ModelCatalogEntry> catalog) => [
  for (final entry in catalog)
    if (labConfigurationKeys.contains(entry.key)) LabConfiguration(entry),
];

/// The model families the bench offers — one row per display name, in
/// catalog order — each with the engines it ships on.
List<LabModelFamily> labModelFamiliesOf(List<LabConfiguration> configurations) {
  final families = <String, List<LabConfiguration>>{};
  for (final configuration in configurations) {
    families
        .putIfAbsent(configuration.displayName, () => [])
        .add(configuration);
  }
  return [
    for (final entry in families.entries)
      LabModelFamily(displayName: entry.key, configurations: entry.value),
  ];
}

final class LabModelFamily {
  const LabModelFamily({
    required this.displayName,
    required this.configurations,
  });

  final String displayName;
  final List<LabConfiguration> configurations;

  /// A stable handle for keys and menus: the profile every engine of the
  /// family shares, independent of catalog order.
  String get id => configurations.first.profileKey;

  /// The same family on [engine], or null when it does not ship on it.
  LabConfiguration? on(ModelEngine engine) =>
      configurations.where((c) => c.engine == engine).firstOrNull;
}
