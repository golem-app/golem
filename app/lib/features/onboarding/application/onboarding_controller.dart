import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../domain/onboarding_policy.dart';

part 'onboarding_controller.g.dart';

enum FirstRunStep { welcome, model, catalog, download, unsupported, complete }

final class FirstRunState {
  const FirstRunState({required this.step, this.failure});

  final FirstRunStep step;
  final String? failure;

  FirstRunState copyWith({
    FirstRunStep? step,
    String? failure,
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
    final options = onboardingModelOptions(
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
        failure: 'Your model choice could not be saved. Try again.',
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
        : state.copyWith(failure: 'Golem could not save setup. Try again.');
    return saved;
  }
}
