import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/app_preferences.dart';
import '../../core/providers/app_providers.dart';
import 'domain/onboarding_policy.dart';
import 'first_run_screen.dart';
import '../chat/application/chat_providers.dart';

class FirstRunGate extends ConsumerStatefulWidget {
  const FirstRunGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends ConsumerState<FirstRunGate> {
  bool? _initialShowFirstRun;
  bool _classificationScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleInitialClassification();
  }

  void _scheduleInitialClassification() {
    if (_classificationScheduled || _initialShowFirstRun != null) return;
    _classificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _classificationScheduled = false;
      if (mounted) _classifyInitialStateIfReady();
    });
  }

  void _classifyInitialStateIfReady() {
    if (_initialShowFirstRun != null) return;
    final preferences = ref.read(preferencesControllerProvider);
    final chats = ref.read(chatControllerProvider);
    final models = ref.read(modelControllerProvider);
    if (!preferences.hasValue || !chats.hasValue || !models.hasValue) return;
    final value = preferences.requireValue;
    final show = shouldShowFirstRun(
      preferences: value,
      chats: chats.requireValue,
      models: models.requireValue,
      backend: ref.read(inferenceBackendProvider),
    );
    setState(() => _initialShowFirstRun = show);
    if (show || value.onboardingVersion >= currentOnboardingVersion) return;
    ref.read(preferencesControllerProvider.notifier).completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    // Any store may be the last to settle. Listener-driven effects keep the
    // frame-sensitive build path free of persistence and provider mutations.
    ref.listen(
      preferencesControllerProvider,
      (_, _) => _scheduleInitialClassification(),
    );
    ref.listen(
      chatControllerProvider,
      (_, _) => _scheduleInitialClassification(),
    );
    ref.listen(
      modelControllerProvider,
      (_, _) => _scheduleInitialClassification(),
    );
    final preferences = ref.watch(preferencesControllerProvider);
    final chats = ref.watch(chatControllerProvider);
    final models = ref.watch(modelControllerProvider);
    if (preferences.isLoading || chats.isLoading || models.isLoading) {
      return const CupertinoPageScaffold(
        key: Key('first-run-loading'),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    // A store's own surface owns its read failure. First run must never turn a
    // recoverable chat/model/preferences error into a root-level dead end.
    if (!preferences.hasValue || !chats.hasValue || !models.hasValue) {
      return widget.child;
    }
    final value = preferences.requireValue;
    if (value.onboardingVersion >= currentOnboardingVersion) {
      return widget.child;
    }
    // Freeze the fresh-vs-legacy decision from the stores as first loaded.
    // A download is expected to mutate model state while first run is open;
    // that must not reclassify the user as a legacy install mid-flow.
    final show =
        _initialShowFirstRun ??
        shouldShowFirstRun(
          preferences: value,
          chats: chats.requireValue,
          models: models.requireValue,
          backend: ref.watch(inferenceBackendProvider),
        );
    if (show) return const FirstRunScreen();

    return widget.child;
  }
}
