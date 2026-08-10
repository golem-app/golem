import '../../../core/domain/app_preferences.dart';
import '../../../core/domain/model_catalog.dart';
import '../../../core/services/custom_repository_resolver.dart';
import '../../../core/services/repository_resolver.dart';

/// The resolve half of the add-custom-repository flow, extracted from the
/// Add card so the collision derivation and the resolver's failure contract
/// are testable without pumping a widget. The persistence half stays
/// `PreferencesController.addCustomModel` — preferences have one writer.
final class CustomRepositoryWorkflow {
  const CustomRepositoryWorkflow({required this.resolver});

  final CustomRepositoryResolver resolver;

  Future<RepositoryResolution> resolve({
    required String repository,
    required ModelEngine engine,
    required String ref,
    String? weightsFile,
    required List<ModelCatalogEntry> pinned,
    required List<CustomModelSpec> custom,
  }) async {
    final existingKeys = <String>{
      for (final entry in pinned) entry.key,
      // Only entries with a recognized profile collide. Both an unresolved
      // spec and a resolved one whose template matched no known profile are
      // told by their card to add the repository again, so counting either
      // would refuse the only repair the card offers.
      ...custom.where((spec) => spec.profile != null).map((spec) => spec.key),
    };
    try {
      return await resolver.resolve(
        repository: repository,
        engine: engine,
        ref: ref,
        weightsFile: weightsFile,
        existingKeys: existingKeys,
      );
    } catch (error) {
      // A resolver that escapes its own failure contract must not strand the
      // caller on a spinner with no message and no way back.
      return RepositoryRejected(
        RepositoryRejection.malformedMetadata,
        cause: error,
      );
    }
  }
}
