import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_identity.dart';
import '../core/domain/app_preferences.dart';
import '../core/theme/golem_theme.dart';
import '../features/benchmark/benchmark_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/search_screen.dart';
import '../features/chat/widgets/attach_sheet.dart';
import '../features/legal/model_attribution_screen.dart';
import '../features/legal/open_source_licenses_screen.dart';
import '../features/models/application/model_providers.dart';
import '../features/onboarding/first_run_gate.dart';
import '../features/preferences/application/preferences_providers.dart';
import '../features/settings/appearance_screen.dart';
import '../features/settings/language_screen.dart';
import '../features/settings/models_screen.dart';
import '../features/settings/privacy_screen.dart';
import '../features/settings/response_style_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/storage_screen.dart';
import '../features/settings/system_prompt_screen.dart';
import '../l10n/l10n.dart';

/// Creates the route table for one app identity. Production omits internal
/// routes entirely rather than relying on a hidden navigation affordance.
GoRouter createAppRouter({
  required AttachmentPicker picker,
  required AppIdentity identity,
}) => GoRouter(
  routes: [
    ShellRoute(
      // The model invariant owns every route, while remaining below the root
      // Navigator so setup consent and recovery dialogs have valid route
      // context. A deep link cannot bypass this shell.
      builder: (context, state, child) => FirstRunGate(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => ChatScreen(picker: picker),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => SettingsScreen(identity: identity),
        ),
        GoRoute(
          path: '/settings/models',
          builder: (context, state) => const ModelsScreen(),
        ),
        GoRoute(
          path: '/settings/response-style',
          builder: (context, state) => const ResponseStyleScreen(),
        ),
        GoRoute(
          path: '/settings/system-prompt',
          builder: (context, state) => const SystemPromptScreen(),
        ),
        GoRoute(
          path: '/settings/appearance',
          builder: (context, state) => const AppearanceScreen(),
        ),
        GoRoute(
          path: '/settings/language',
          builder: (context, state) => const LanguageScreen(),
        ),
        GoRoute(
          path: '/settings/privacy',
          builder: (context, state) => const PrivacyScreen(),
        ),
        GoRoute(
          path: '/settings/storage',
          builder: (context, state) => const StorageScreen(),
        ),
        GoRoute(
          path: '/settings/model-attribution',
          builder: (context, state) => const ModelAttributionScreen(),
        ),
        GoRoute(
          path: '/settings/licenses',
          builder: (context, state) => const OpenSourceLicensesScreen(),
        ),
        if (identity.internalToolsEnabled)
          GoRoute(
            path: '/benchmark',
            builder: (context, state) => const BenchmarkScreen(),
          ),
      ],
    ),
  ],
);

class GolemApp extends ConsumerStatefulWidget {
  const GolemApp({
    required this.identity,
    this.picker = const AttachmentPicker(),
    this.onPreferencesSettled,
    super.key,
  });

  final AppIdentity identity;
  final AttachmentPicker picker;

  /// Called once, the first time the preferences store has answered — with a
  /// value or a failure. The bootstrap keeps the first frame deferred until
  /// then, so the stored theme, language and text size are on the first frame
  /// the user sees instead of snapping in a frame later (#159).
  final VoidCallback? onPreferencesSettled;

  @override
  ConsumerState<GolemApp> createState() => _GolemAppState();
}

class _GolemAppState extends ConsumerState<GolemApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;

  Timer? _reconcileDebounce;
  bool _preferencesSettled = false;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(picker: widget.picker, identity: widget.identity);
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, so the model controller's own launch pass has
    // settled before anything re-attaches to a transfer it may have found.
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

  // No MediaQuery exists above the app widget, so brightness comes from the
  // platform dispatcher; observing it keeps the theme reactive.
  @override
  void didChangePlatformBrightness() => setState(() {});

  // The widget layer only reports the OS signal; the controller decides
  // whether freeing the engine is safe (never mid-stream, never mid-op).
  @override
  void didHaveMemoryPressure() {
    ref.read(modelControllerProvider.notifier).releaseEngineWhileInactive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Multi-gigabyte weights must not sit resident under the platform's
    // background memory ceiling; prepare() reloads lazily on return.
    if (state == AppLifecycleState.paused) {
      ref.read(modelControllerProvider.notifier).releaseEngineWhileInactive();
    }
    // The only teardown signal this app actually receives on the way out.
    // Intercepting the back press is not an option: with predictive back —
    // default-on at targetSdk 36 — the gesture is handled entirely by the
    // system, so neither PopScope nor didPopRoute runs (verified on device,
    // #124). The handler is therefore synchronous, because the framework does
    // not await this either.
    if (state == AppLifecycleState.detached) {
      ref.read(modelControllerProvider.notifier).releaseEngineForTeardown();
    }
    // Returning to the foreground is the only moment the app can notice that
    // the OS finished, paused, or discarded a download while it was away.
    // Debounced because `resumed` also fires for a permission sheet, a share
    // sheet, or a Control Centre pull, and each pass probes the platform.
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
    // Deliberate .value degrade: while preferences load (one frame at most,
    // under the splash) — or when the store failed to read — the platform
    // defaults apply. The app root must never error-screen over a prefs
    // read; the Appearance screen is where that failure shows.
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
    // Clamped on read: the store's leaves are deliberately tolerant, and
    // TextScaler.linear asserts on negative factors.
    final textScale = (preferences?.textScale ?? 1.0).clamp(
      minTextScale,
      maxTextScale,
    );
    final locale = switch (preferences?.language ?? AppLanguage.system) {
      AppLanguage.system => null,
      AppLanguage.english => const Locale('en'),
      AppLanguage.polish => const Locale('pl'),
      AppLanguage.spanish => const Locale('es'),
      AppLanguage.brazilianPortuguese => const Locale('pt', 'BR'),
      AppLanguage.japanese => const Locale('ja'),
      AppLanguage.indonesian => const Locale('id'),
      AppLanguage.hindi => const Locale('hi'),
      AppLanguage.french => const Locale('fr'),
      AppLanguage.vietnamese => const Locale('vi'),
      AppLanguage.turkish => const Locale('tr'),
      AppLanguage.korean => const Locale('ko'),
      AppLanguage.arabic => const Locale('ar'),
    };
    return CupertinoApp.router(
      title: widget.identity.displayName,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: GolemTheme.theme(brightness),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      builder: (context, child) {
        var body = child ?? const SizedBox.shrink();
        if (textScale != 1.0) {
          // The system scaler is effectively linear here, so sampling it at a
          // reference size folds any platform factor into the user's. Skipped
          // entirely at 1.0, which keeps every existing golden byte-identical.
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
