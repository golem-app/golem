import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../core/app_identity.dart';
import '../core/domain/app_preferences.dart';
import '../core/providers/app_providers.dart';
import '../core/theme/golem_theme.dart';
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
/// This is the flavor's foundation: identity, window, container and the
/// storage roots it resolved, so a lab build proves its isolation on screen.
/// The bench itself follows.
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
  bool _preferencesSettled = false;

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

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final preferencesValue = ref.watch(preferencesControllerProvider);
    if (!_preferencesSettled &&
        (preferencesValue.hasValue || preferencesValue.hasError)) {
      _preferencesSettled = true;
      widget.onPreferencesSettled?.call();
    }
    final brightness = switch (preferencesValue.value?.theme ??
        ThemeSetting.system) {
      ThemeSetting.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      ThemeSetting.light => Brightness.light,
      ThemeSetting.dark => Brightness.dark,
    };
    return CupertinoApp(
      title: widget.identity.displayName,
      debugShowCheckedModeBanner: false,
      theme: GolemTheme.theme(brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      home: _LabFoundation(identity: widget.identity),
    );
  }
}

/// Identity, container and engine: technical facts only, which is why nothing
/// here is a sentence in need of a catalog.
class _LabFoundation extends ConsumerWidget {
  const _LabFoundation({required this.identity});

  final AppIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(inferenceBackendProvider);
    final documents = ref.watch(documentsPathProvider);
    final ink = CupertinoDynamicColor.resolve(GolemTheme.ink, context);
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    return CupertinoPageScaffold(
      key: const Key('lab-foundation'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(GolemSpace.s8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(identity.iconAsset, width: 42, height: 42),
                    const SizedBox(width: GolemSpace.s4),
                    Text(
                      identity.displayName,
                      style: GolemText.display.copyWith(color: ink),
                    ),
                  ],
                ),
                const SizedBox(height: GolemSpace.s6),
                for (final line in [
                  identity.applicationId,
                  documents,
                  backend.kind.name,
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: GolemSpace.s2),
                    child: Text(
                      line,
                      style: GolemText.code.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
