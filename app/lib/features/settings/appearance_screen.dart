import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_nav_bar.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/retry_pane.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';
import 'application/preferences_providers.dart';
import 'save_feedback.dart';
import 'widgets/settings_rows.dart';

/// Appearance: theme, text size, and the transcript toggles.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final preferencesValue = ref.watch(preferencesControllerProvider);
    // The app root deliberately degrades a failed preferences read to
    // defaults; this screen is where that failure surfaces with a retry —
    // editing over invented defaults would overwrite the store blind.
    if (preferencesValue.hasError) {
      return CupertinoPageScaffold(
        navigationBar: GolemNavBar(
          title: l10n.settingsAppearance,
          previousPageTitle: l10n.settingsTitle,
        ),
        child: SafeArea(
          bottom: false,
          child: RetryPane(
            key: const Key('preferences-load-error'),
            message: l10n.preferencesLoadFailed,
            actionLabel: l10n.tryAgain,
            onRetry: () => ref.invalidate(preferencesControllerProvider),
          ),
        ),
      );
    }
    final preferences = preferencesValue.value ?? const AppPreferences();
    final notifier = ref.read(preferencesControllerProvider.notifier);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: l10n.settingsAppearance,
        previousPageTitle: l10n.settingsTitle,
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            SectionHeader(l10n.theme),
            const SizedBox(height: 8),
            GolemSegmented<ThemeSetting>(
              groupValue: preferences.theme,
              onChanged: (value) =>
                  announceFailedSave(context, notifier.setTheme(value)),
              segments: {
                ThemeSetting.system: Text(
                  l10n.themeSystem,
                  key: const Key('theme-system'),
                  style: GolemText.footnoteStrong,
                ),
                ThemeSetting.light: Text(
                  l10n.themeLight,
                  key: const Key('theme-light'),
                  style: GolemText.footnoteStrong,
                ),
                ThemeSetting.dark: Text(
                  l10n.themeDark,
                  key: const Key('theme-dark'),
                  style: GolemText.footnoteStrong,
                ),
              },
            ),
            const SizedBox(height: 24),
            SectionHeader(l10n.textSize),
            const SizedBox(height: 8),
            _TextSizeCard(
              scale: preferences.textScale,
              onCommit: (value) =>
                  announceFailedSave(context, notifier.setTextScale(value)),
            ),
            const SizedBox(height: 24),
            SectionHeader(l10n.inTranscript),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsToggleRow(
                  toggleKey: const Key('toggle-metrics'),
                  label: l10n.showInferenceMetrics,
                  value: preferences.showMetrics,
                  onChanged: (value) => announceFailedSave(
                    context,
                    notifier.setShowMetrics(value),
                  ),
                ),
                SettingsToggleRow(
                  toggleKey: const Key('toggle-reasoning'),
                  label: l10n.alwaysExpandReasoning,
                  value: preferences.expandReasoning,
                  onChanged: (value) => announceFailedSave(
                    context,
                    notifier.setExpandReasoning(value),
                  ),
                ),
                SettingsToggleRow(
                  toggleKey: const Key('toggle-haptics'),
                  label: l10n.hapticsOnSend,
                  value: preferences.hapticsOnSend,
                  onChanged: (value) => announceFailedSave(
                    context,
                    notifier.setHapticsOnSend(value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview bubble plus the A–A slider. The drag is widget-local and
/// commits on release, like the sampling sliders.
class _TextSizeCard extends StatefulWidget {
  const _TextSizeCard({required this.scale, required this.onCommit});
  final double scale;
  final ValueChanged<double> onCommit;

  @override
  State<_TextSizeCard> createState() => _TextSizeCardState();
}

class _TextSizeCardState extends State<_TextSizeCard> {
  static const _min = minTextScale;
  static const _max = maxTextScale;

  /// The adjust step a screen reader moves the slider by. Ten stops across the
  /// 0.85–1.3 range, and 1.0 lands on one of them exactly, so the default stays
  /// reachable by gesture from either end.
  static const _step = 0.05;
  double? _drag;

  static int _percent(double scale) => (scale * 100).round();

  double _stepped(double scale, int direction) =>
      (scale + _step * direction).clamp(_min, _max);

  @override
  Widget build(BuildContext context) {
    final scale = (_drag ?? widget.scale).clamp(_min, _max);
    final ink = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    // The ambient scaler already bakes in the committed preference
    // (widget.scale); divide it back out to recover the platform factor,
    // then render the preview under no-text-scaling so the sample shows
    // systemFactor × dragged-scale exactly — never the square of the
    // committed setting.
    final ambient = MediaQuery.of(context).textScaler.scale(100) / 100;
    final systemFactor = widget.scale == 0 ? 1.0 : ambient / widget.scale;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The preview is a user bubble so the change is judged on
              // real chat copy at the dragged size. It and the two size
              // glyphs are the control's dial face rather than content —
              // the slider below announces the setting itself.
              ExcludeSemantics(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.userBubble,
                        context,
                      ),
                      borderRadius: BorderRadius.circular(GolemRadius.bubble),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: MediaQuery.withNoTextScaling(
                        child: Text(
                          context.l10n.textPreview,
                          style: GolemText.body.copyWith(
                            color: GolemTheme.textOnDark,
                            fontSize:
                                (GolemText.body.fontSize ?? 17) *
                                systemFactor *
                                scale,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  ExcludeSemantics(
                    child: Text(
                      'A',
                      style: TextStyle(fontSize: 13, color: ink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // A bare CupertinoSlider announces its position along its own
                  // track ("33%") under no name at all, which says nothing
                  // about text size. Its node is replaced by one that reads in
                  // the units the setting is in and adjusts in the steps the
                  // slider's own increase/decrease would.
                  Expanded(
                    child: Semantics(
                      key: const Key('text-size-control'),
                      container: true,
                      slider: true,
                      label: context.l10n.textSize,
                      value: context.l10n.percentValue(_percent(scale)),
                      increasedValue: context.l10n.percentValue(
                        _percent(_stepped(scale, 1)),
                      ),
                      decreasedValue: context.l10n.percentValue(
                        _percent(_stepped(scale, -1)),
                      ),
                      onIncrease: () => widget.onCommit(_stepped(scale, 1)),
                      onDecrease: () => widget.onCommit(_stepped(scale, -1)),
                      child: ExcludeSemantics(
                        child: CupertinoSlider(
                          key: const Key('text-scale-slider'),
                          value: scale,
                          min: _min,
                          max: _max,
                          onChanged: (next) => setState(() => _drag = next),
                          onChangeEnd: (next) {
                            setState(() => _drag = null);
                            // Snap near-1.0 back to exactly 1.0 so the default
                            // (and the golden-stable no-wrapper path) is easy
                            // to return to by hand.
                            widget.onCommit(
                              (next - 1.0).abs() < 0.03 ? 1.0 : next,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ExcludeSemantics(
                    child: Text(
                      'A',
                      style: TextStyle(fontSize: 19, color: ink),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
