import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

import '../core/app_identity.dart';
import '../core/domain/app_preferences.dart';
import '../core/theme/golem_theme.dart';
import '../core/providers/app_providers.dart';
import '../features/lab/application/lab_bench_controller.dart';
import '../features/lab/lab_shell.dart';
import '../features/models/application/model_providers.dart';
import '../features/preferences/application/preferences_providers.dart';
import '../l10n/l10n.dart';
import 'launch_composition.dart';

/// The lab's provider seams: the consumer app's, with the chat session bridge
/// left for the bench controller to bind (see [launchOverrides]).
List<Override> labLaunchOverrides(LaunchDependencies dependencies) =>
    launchOverrides(dependencies, lab: true);

/// Golem Model Lab's root (ADR 0021): the macOS-only bench for the models the
/// phone flavors ship. It shares the consumer app's launch composition and
/// repositories and none of its routes — no first-run gate, no chat, no
/// settings tree — because a bench opens with nothing armed and downloads
/// nothing on its own.
///
/// What it does share with the consumer root is the lifecycle: the engine is
/// released synchronously on the way out (#124), downloads are reconciled
/// after the first frame and on every return to the foreground, and the
/// appearance follows the platform. What it deliberately does not do is
/// release the engine on memory pressure or a background transition — a
/// bench keeps its resident model, and macOS has no jetsam ceiling.
class LabApp extends ConsumerStatefulWidget {
  const LabApp({required this.identity, this.onPreferencesSettled, super.key});

  final AppIdentity identity;

  /// Called once, the first time the preferences store has answered — the
  /// bootstrap keeps the first frame deferred until then, exactly as it does
  /// for the consumer app.
  final VoidCallback? onPreferencesSettled;

  @override
  ConsumerState<LabApp> createState() => _LabAppState();
}

class _LabAppState extends ConsumerState<LabApp> with WidgetsBindingObserver {
  late final GoRouter _router;
  Timer? _reconcileDebounce;
  bool _preferencesSettled = false;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LabShell()),
      ],
    );
    WidgetsBinding.instance.addObserver(this);
    // The bench owns the session the model commands ask about (#88): bound
    // here, behind kLabBuild, so the first command — the post-frame
    // reconcile below — builds the bench before it asks.
    ref
        .read(chatSessionBridgeProvider)
        .bindEnsureOwner(() => ref.read(labBenchControllerProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileDownloads());
  }

  @override
  void dispose() {
    _reconcileDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  void _reconcileDownloads() {
    if (!mounted) return;
    ref.read(modelControllerProvider.notifier).reconcileDownloads();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      ref.read(modelControllerProvider.notifier).releaseEngineForTeardown();
    }
    if (state == AppLifecycleState.resumed) {
      _reconcileDebounce?.cancel();
      _reconcileDebounce = Timer(
        const Duration(milliseconds: 500),
        _reconcileDownloads,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferencesValue = ref.watch(preferencesControllerProvider);
    if (!_preferencesSettled &&
        (preferencesValue.hasValue || preferencesValue.hasError)) {
      _preferencesSettled = true;
      widget.onPreferencesSettled?.call();
    }
    final preferences = preferencesValue.value;
    final brightness = switch (preferences?.theme ?? ThemeSetting.system) {
      ThemeSetting.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      ThemeSetting.light => Brightness.light,
      ThemeSetting.dark => Brightness.dark,
    };
    // The same three preferences the consumer root honours, from the same
    // store: the lab has no settings tree to change them, but a container
    // that carries them is not ignored.
    final textScale = (preferences?.textScale ?? 1.0).clamp(
      minTextScale,
      maxTextScale,
    );
    return CupertinoApp.router(
      title: widget.identity.displayName,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: GolemTheme.theme(brightness),
      locale: localeForLanguage(preferences?.language ?? AppLanguage.system),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      builder: (context, child) {
        var body = child ?? const SizedBox.shrink();
        if (textScale != 1.0) {
          final media = MediaQuery.of(context);
          final systemFactor = media.textScaler.scale(100) / 100;
          body = MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(systemFactor * textScale),
            ),
            child: body,
          );
        }
        return body;
      },
    );
  }
}
