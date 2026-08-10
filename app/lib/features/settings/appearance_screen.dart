import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chrome/golem_nav_bar.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
import 'save_feedback.dart';
import 'widgets/settings_rows.dart';

/// Appearance: theme, text size, and the transcript toggles.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(preferencesControllerProvider).value ??
        const AppPreferences();
    final notifier = ref.read(preferencesControllerProvider.notifier);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: 'Appearance',
        previousPageTitle: 'Settings',
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            const SectionHeader('Theme'),
            const SizedBox(height: 8),
            GolemSegmented<ThemeSetting>(
              groupValue: preferences.theme,
              onChanged: (value) =>
                  announceFailedSave(context, notifier.setTheme(value)),
              segments: const {
                ThemeSetting.system: Text(
                  'System',
                  key: Key('theme-system'),
                  style: GolemText.footnoteStrong,
                ),
                ThemeSetting.light: Text(
                  'Light',
                  key: Key('theme-light'),
                  style: GolemText.footnoteStrong,
                ),
                ThemeSetting.dark: Text(
                  'Dark',
                  key: Key('theme-dark'),
                  style: GolemText.footnoteStrong,
                ),
              },
            ),
            const SizedBox(height: 24),
            const SectionHeader('Text size'),
            const SizedBox(height: 8),
            _TextSizeCard(
              scale: preferences.textScale,
              onCommit: (value) =>
                  announceFailedSave(context, notifier.setTextScale(value)),
            ),
            const SizedBox(height: 24),
            const SectionHeader('In the transcript'),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsToggleRow(
                  toggleKey: const Key('toggle-metrics'),
                  label: 'Show inference metrics',
                  value: preferences.showMetrics,
                  onChanged: (value) => announceFailedSave(
                    context,
                    notifier.setShowMetrics(value),
                  ),
                ),
                SettingsToggleRow(
                  toggleKey: const Key('toggle-reasoning'),
                  label: 'Always expand reasoning',
                  value: preferences.expandReasoning,
                  onChanged: (value) => announceFailedSave(
                    context,
                    notifier.setExpandReasoning(value),
                  ),
                ),
                SettingsToggleRow(
                  toggleKey: const Key('toggle-haptics'),
                  label: 'Haptics on send',
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
  double? _drag;

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
              // real chat copy at the dragged size.
              Align(
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
                        'Looks about right.',
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('A', style: TextStyle(fontSize: 13, color: ink)),
                  const SizedBox(width: 10),
                  Expanded(
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
                        widget.onCommit((next - 1.0).abs() < 0.03 ? 1.0 : next);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('A', style: TextStyle(fontSize: 19, color: ink)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
