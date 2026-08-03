import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/golem_theme.dart';
import '../features/benchmark/benchmark_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ChatScreen()),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/benchmark',
      builder: (context, state) => const BenchmarkScreen(),
    ),
  ],
);

class GolemApp extends StatefulWidget {
  const GolemApp({super.key});

  @override
  State<GolemApp> createState() => _GolemAppState();
}

class _GolemAppState extends State<GolemApp> with WidgetsBindingObserver {
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

  @override
  Widget build(BuildContext context) => CupertinoApp.router(
    title: 'Golem Flutter',
    debugShowCheckedModeBanner: false,
    routerConfig: _router,
    theme: GolemTheme.theme(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    ),
    // User-facing copy is intentionally hardcoded English, matching the
    // native app this port mirrors. The Cupertino global delegates are still
    // required by the framework widgets themselves.
    localizationsDelegates: const [
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    builder: (context, child) =>
        StartupGate(child: child ?? const SizedBox.shrink()),
  );
}
