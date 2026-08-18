import '../../../core/domain/app_state.dart';
import '../../../core/domain/device_eligibility.dart';
import '../../../core/domain/inference_backend.dart';
import '../../../core/domain/model_activation.dart';
import '../../../core/domain/model_catalog.dart';

/// Whether a send may reach the engine, and with which artifact.
sealed class GenerationTarget {
  const GenerationTarget();
}

/// The turn may proceed. [key] is the artifact to prepare and generate with —
/// null only for a sideloaded build, where the operator's own file is the model
/// and no catalog entry describes it. [entry] is that key's catalog entry when
/// the catalog carries one, which is what the installed check needs.
final class GenerationReady extends GenerationTarget {
  const GenerationReady({this.key, this.entry});

  final String? key;
  final ModelCatalogEntry? entry;
}

/// The turn stops here and the banner shows [failure] instead.
final class GenerationRefused extends GenerationTarget {
  const GenerationRefused(this.failure);

  final ChatFailure failure;
}

/// The pre-flight decision a send makes before touching the engine (#127).
///
/// [deviceRefusal] is checked first and on its own: a device outside every
/// supported tier stops here (#27) because prepare() could only fail, and the
/// missing-model refusal below would otherwise offer a multi-gigabyte download
/// whose weights this device can never load. The sideload exemption does not
/// apply — an operator's own file needs the same memory and instruction set.
///
/// A real engine with no loadable artifact fails fast into the banner's
/// download CTA rather than waiting for prepare()'s cryptic missing-file error
/// after a hang-like pause. The conversation's own choice decides which
/// artifact that is (#20).
GenerationTarget resolveGenerationTarget({
  required InferenceBackendConfig backend,
  required DeviceIneligibilityReason? deviceRefusal,
  required List<ModelCatalogEntry> catalog,
  required String? conversationModelKey,
  required String? residentModelKey,
  required Set<String> loadableKeys,
}) {
  if (deviceRefusal != null) {
    return const GenerationRefused(
      ChatFailure(kind: ChatFailureKind.unsupportedDevice),
    );
  }
  final target = effectiveModelKey(
    backend: backend,
    catalog: catalog,
    modelKey: conversationModelKey,
    residentModelKey: residentModelKey,
    loadableKeys: loadableKeys,
  );
  if (target == null && !backend.simulatedInference && !backend.sideloaded) {
    return GenerationRefused(notInstalledFailure(backend.artifactKey));
  }
  return GenerationReady(
    key: target,
    entry: target == null
        ? null
        : catalog.where((item) => item.key == target).firstOrNull,
  );
}

/// The one statement of "this turn has no weights to run". Reachable on its own
/// because the installed check is asynchronous repository I/O the caller runs
/// after [resolveGenerationTarget] has already decided everything else.
ChatFailure notInstalledFailure(String? key) =>
    ChatFailure(kind: ChatFailureKind.missingModel, artifactKey: key);
