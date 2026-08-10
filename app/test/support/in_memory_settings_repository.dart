import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

final class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this.settings = const GenerationSettings()]);
  GenerationSettings settings;
  int saves = 0;

  /// While > 0, each save throws a typed write failure and decrements —
  /// the fault-injection hook for rollback tests.
  int failingSaves = 0;

  @override
  Future<GenerationSettings> load() async => settings;

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
