import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_identity.dart';
import '../core/domain/app_preferences.dart';
import '../core/providers/app_providers.dart';
import '../core/theme/golem_theme.dart';
import '../features/benchmark/benchmark_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/widgets/attach_sheet.dart';
import '../features/chat/search_screen.dart';
import '../features/settings/appearance_screen.dart';
import '../features/settings/models_screen.dart';
import '../features/settings/privacy_screen.dart';
import '../features/settings/response_style_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/storage_screen.dart';
import '../features/settings/system_prompt_screen.dart';
import '../features/splash/splash_screen.dart';

GoRouter _createRouter(AttachmentPicker picker) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => ChatScreen(picker: picker),
    ),
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
  const GolemApp({this.picker = const AttachmentPicker(), super.key});

  final AttachmentPicker picker;

  @override
  ConsumerState<GolemApp> createState() => _GolemAppState();
}

class _GolemAppState extends ConsumerState<GolemApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _createRouter(widget.picker);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
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
  }

  @override
  Widget build(BuildContext context) {
    // While preferences load (one frame at most, under the splash) the
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
      supportedLocales: const [Locale('en')],
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
        return StartupGate(child: body);
      },
    );
  }
}
