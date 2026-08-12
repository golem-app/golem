import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/model_admission.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../settings/application/preferences_providers.dart';

part 'onboarding_controller.g.dart';

enum FirstRunStep { welcome, model, catalog, download, unsupported, complete }

enum FirstRunFailure { modelChoiceSave, setupSave }

final class FirstRunState {
  const FirstRunState({required this.step, this.failure});

  final FirstRunStep step;
  final FirstRunFailure? failure;

  FirstRunState copyWith({
    FirstRunStep? step,
    FirstRunFailure? failure,
    bool clearFailure = false,
  }) => FirstRunState(
    step: step ?? this.step,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

@Riverpod(retry: noRetry)
class FirstRunController extends _$FirstRunController {
  @override
  FirstRunState build() => const FirstRunState(step: FirstRunStep.welcome);

  void continueFromWelcome() {
    state = state.copyWith(
      step: ref.read(deviceRefusalProvider) == null
          ? FirstRunStep.model
          : FirstRunStep.unsupported,
      clearFailure: true,
    );
  }

  void showCatalog() =>
      state = state.copyWith(step: FirstRunStep.catalog, clearFailure: true);

  void showModel() =>
      state = state.copyWith(step: FirstRunStep.model, clearFailure: true);

  void showDownload() =>
      state = state.copyWith(step: FirstRunStep.download, clearFailure: true);

  Future<bool> selectModel(String key) async {
    final options = modelAdmissionOptions(
      catalog: ref.read(modelCatalogEntriesProvider),
      backend: ref.read(inferenceBackendProvider),
      eligibility: ref.read(deviceEligibilityProvider),
    );
    if (!options.any((option) => option.entry.key == key && option.enabled)) {
      return false;
    }
    state = state.copyWith(clearFailure: true);
    final saved = await ref
        .read(preferencesControllerProvider.notifier)
        .setOnboardingModel(key);
    if (!ref.mounted) return saved;
    if (!saved) {
      state = FirstRunState(
        step: state.step,
        failure: FirstRunFailure.modelChoiceSave,
      );
    }
    return saved;
  }

  Future<bool> complete({bool keepSelection = true}) async {
    final saved = await ref
        .read(preferencesControllerProvider.notifier)
        .completeOnboarding(
          modelKey: keepSelection
              ? ref
                    .read(preferencesControllerProvider)
                    .value
                    ?.onboardingModelKey
              : null,
          clearModel: !keepSelection,
        );
    if (!ref.mounted) return saved;
    state = saved
        ? state.copyWith(step: FirstRunStep.complete, clearFailure: true)
        : state.copyWith(failure: FirstRunFailure.setupSave);
    return saved;
  }
}
