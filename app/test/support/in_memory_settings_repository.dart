import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

final class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this.settings = const GenerationSettings()]);
  GenerationSettings settings;
  int saves = 0;

  /// While > 0, each save throws a typed write failure and decrements —
  /// the fault-injection hook for rollback tests.
  int failingSaves = 0;

  /// While > 0, each load throws a typed read failure and decrements.
  int failingLoads = 0;

  @override
  Future<GenerationSettings> load() async {
    if (failingLoads > 0) {
      failingLoads--;
      throw const PersistenceException(
        PersistenceFailureKind.read,
        'Could not read the stored generation settings.',
      );
    }
    return settings;
  }

  @override
  Future<void> save(GenerationSettings value) async {
    if (failingSaves > 0) {
      failingSaves--;
      throw const PersistenceException(
        PersistenceFailureKind.write,
        'Could not save the generation settings.',
      );
    }
    settings = value;
    saves++;
  }
}
