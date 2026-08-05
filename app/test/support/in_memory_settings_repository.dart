import 'package:golem_flutter/core/domain/generation_settings.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';

final class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this.settings = const GenerationSettings()]);
  GenerationSettings settings;
  int saves = 0;

  @override
  Future<GenerationSettings> load() async => settings;

  @override
  Future<void> save(GenerationSettings value) async {
    settings = value;
    saves++;
  }
}
