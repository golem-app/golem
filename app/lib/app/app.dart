import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_identity.dart';
import '../core/domain/app_preferences.dart';
import '../core/providers/app_providers.dart';
import '../core/theme/golem_theme.dart';
import '../features/benchmark/benchmark_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/search_screen.dart';
import '../features/settings/appearance_screen.dart';
import '../features/settings/models_screen.dart';
import '../features/settings/privacy_screen.dart';
import '../features/settings/response_style_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/storage_screen.dart';
import '../features/settings/system_prompt_screen.dart';
import '../features/splash/splash_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ChatScreen()),
    GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
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
      path: '/settings/privacy',
      builder: (context, state) => const PrivacyScreen(),
    ),
    GoRoute(
      path: '/settings/storage',
      builder: (context, state) => const StorageScreen(),
    ),
    GoRoute(
      path: '/benchmark',
      builder: (context, state) => const BenchmarkScreen(),
    ),
  ],
);

class GolemApp extends ConsumerStatefulWidget {
  const GolemApp({super.key});

  @override
  ConsumerState<GolemApp> createState() => _GolemAppState();
}

class _GolemAppState extends ConsumerState<GolemApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The theme brightness comes from the platform dispatcher because no
  // MediaQuery exists above the app widget; observing the platform keeps it
  // reactive when the system appearance changes while the app is running.
  @override
  void didChangePlatformBrightness() => setState(() {});

  // The widget layer only reports OS signals; the controller decides
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
  }

  @override
  Widget build(BuildContext context) {
    // Appearance preferences resolve here so a change re-themes the live
    // app. While they load (one frame at most, under the splash) the
    // platform default applies.
    final preferences = ref.watch(preferencesControllerProvider).value;
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
    return CupertinoApp.router(
      title: AppIdentity.current.displayName,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: GolemTheme.theme(brightness),
      // User-facing copy is intentionally hardcoded English. The global
      // delegates are still required by the framework widgets themselves —
      // Material included: text-field selection toolbars resolve to the
      // Material implementation on Android chrome.
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      builder: (context, child) {
        var body = child ?? const SizedBox.shrink();
        if (textScale != 1.0) {
          // Compose the user's factor onto the system scaler. The system
          // scaler is effectively linear here (hardcoded-English Cupertino
          // app); sampling it at a reference size folds any platform factor
          // in. At the 1.0 default this wrapper is skipped entirely, so
          // every existing golden stays byte-identical.
          final media = MediaQuery.of(context);
          final systemFactor = media.textScaler.scale(100) / 100;
          body = MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(systemFactor * textScale),
            ),
            child: body,
          );
        }
        return StartupGate(child: body);
      },
    );
  }
}
