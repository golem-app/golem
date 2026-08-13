import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_button.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/domain/model_admission.dart';
import '../../core/domain/models.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../l10n/l10n.dart';
import '../chat/application/chat_providers.dart';
import '../models/application/model_providers.dart';
import '../settings/application/preferences_providers.dart';
import 'application/onboarding_controller.dart';
import 'domain/onboarding_policy.dart';
import 'first_run_screen.dart';

/// The consumer shell's single access boundary. The router stays mounted for
/// recovery and dialogs, while its all-routes shell keeps route content,
/// semantics, and keyboard actions unavailable until this policy admits the
/// process.
class FirstRunGate extends ConsumerStatefulWidget {
  const FirstRunGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends ConsumerState<FirstRunGate> {
  bool? _pristineAtLaunch;
  Future<void>? _sideloadValidation;
  Object? _sideloadFailure;
  bool _sideloadValidated = false;
  bool _migrationScheduled = false;

  void _validateSideload() {
    if (_sideloadValidated || _sideloadValidation != null) return;
    setState(() {
      _sideloadFailure = null;
      _sideloadValidation = ref
          .read(inferenceRepositoryProvider)
          .prepare()
          .then((_) {
            if (!mounted) return;
            setState(() => _sideloadValidated = true);
          })
          .catchError((Object error) {
            if (!mounted) return;
            setState(() => _sideloadFailure = error);
          })
          .whenComplete(() {
            if (!mounted) return;
            setState(() => _sideloadValidation = null);
          });
    });
  }

  void _completeLegacyMigration() {
    if (_migrationScheduled) return;
    _migrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref
          .read(preferencesControllerProvider.notifier)
          .completeOnboarding();
    });
  }

  void _retryStores() {
    _pristineAtLaunch = null;
    ref.invalidate(preferencesControllerProvider);
    ref.invalidate(chatControllerProvider);
    ref.invalidate(modelControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(inferenceBackendProvider);
    final refusal = ref.watch(deviceRefusalProvider);
    if (refusal != null) {
      return const FirstRunScreen(initialStep: FirstRunStep.unsupported);
    }

    if (backend.sideloaded) {
      if (_sideloadValidated) return widget.child;
      if (_sideloadValidation == null && _sideloadFailure == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _validateSideload();
        });
      }
      if (_sideloadFailure != null) {
        return _BlockingFailure(
          key: const Key('sideload-validation-failure'),
          onRetry: _validateSideload,
        );
      }
      return const _BlockingProgress(key: Key('sideload-validating'));
    }

    final preferences = ref.watch(preferencesControllerProvider);
    final chats = ref.watch(chatControllerProvider);
    final models = ref.watch(modelControllerProvider);
    if (preferences.isLoading || chats.isLoading || models.isLoading) {
      return const _BlockingProgress(key: Key('first-run-loading'));
    }
    if (!preferences.hasValue || !chats.hasValue || !models.hasValue) {
      return _BlockingFailure(
        key: const Key('first-run-read-failure'),
        onRetry: _retryStores,
      );
    }

    _pristineAtLaunch ??= shouldShowFirstRun(
      preferences: preferences.requireValue,
      chats: chats.requireValue,
      models: models.requireValue,
      backend: backend,
    );
    final onboardingComplete =
        preferences.requireValue.onboardingVersion >= currentOnboardingVersion;
    final hasUsableModel = ref.watch(loadableModelKeysProvider).isNotEmpty;
    if (hasUsableModel && (onboardingComplete || !_pristineAtLaunch!)) {
      if (!onboardingComplete) _completeLegacyMigration();
      return widget.child;
    }

    // Inspect the same admitted key FirstRunScreen will render. An upgrade can
    // carry an interrupted artifact for the other platform engine (for
    // example GGUF from the old iOS auto policy); its bytes must not send the
    // compatible, untouched MLX recommendation to an unactionable resume UI.
    final selectedKey = recommendedAdmittedModelKey(
      catalog: ref.watch(modelCatalogEntriesProvider),
      backend: backend,
      eligibility: ref.watch(deviceEligibilityProvider),
      selectedKey: preferences.requireValue.onboardingModelKey,
    );
    final selectedStatus = selectedKey == null
        ? const ArtifactStatus()
        : models.requireValue.statusOf(selectedKey);
    final interrupted =
        selectedStatus.phase != ArtifactPhase.notDownloaded ||
        selectedStatus.downloadedBytes > 0;
    return FirstRunScreen(
      initialStep: _pristineAtLaunch!
          ? null
          : interrupted
          ? FirstRunStep.download
          : FirstRunStep.model,
    );
  }
}

class _BlockingProgress extends StatelessWidget {
  const _BlockingProgress({super.key});

  @override
  Widget build(BuildContext context) => const CupertinoPageScaffold(
    child: Center(child: CupertinoActivityIndicator()),
  );
}

class _BlockingFailure extends StatelessWidget {
  const _BlockingFailure({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.startupCouldNotFinish,
                textAlign: TextAlign.center,
                style: GolemText.display,
              ),
              const SizedBox(height: 20),
              GolemButton.filled(
                key: const Key('startup-gate-retry'),
                label: context.l10n.tryAgain,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
