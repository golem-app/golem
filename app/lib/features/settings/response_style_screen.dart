import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Deliberate layering note: features may consume the broker's model
// knowledge (profiles carry no Inferno import); the Inferno boundary is
// unchanged — only lib/broker/ touches package:inferno.
import '../../broker/model_profile.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/domain/generation_settings.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
import '../chat/model_label.dart';
import 'widgets/settings_rows.dart';

/// Response style: the three presets, and — in Advanced mode — the raw
/// sampling controls for the active model profile.
class ResponseStyleScreen extends ConsumerWidget {
  const ResponseStyleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(inferenceBackendProvider);
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final preferences =
        ref.watch(preferencesControllerProvider).value ??
        const AppPreferences();
    final profileKey = backend.profileKey;
    final selected = preferences.styleFor(profileKey);
    final modelLabel = chatModelLabel(backend: backend, catalog: catalog);
    return CupertinoPageScaffold(
      navigationBar: GolemNavBar(
        title: 'Response style',
        previousPageTitle: 'Settings',
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('style-list'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 18),
              child: Text(
                'How much room $modelLabel has to improvise. This only '
                'affects new responses.',
                style: GolemText.body.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ),
            for (final style in ResponseStyle.values) ...[
              _StyleCard(
                style: style,
                selected: style == selected,
                onTap: () => ref
                    .read(preferencesControllerProvider.notifier)
                    .setResponseStyle(profileKey, style),
              ),
              const SizedBox(height: 10),
            ],
            if (!preferences.advancedMode)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: SettingsFootnote(
                  'Turn on Advanced mode in Settings to set temperature, '
                  'top-p and token budgets by hand.',
                ),
              )
            else ...[
              const SizedBox(height: 14),
              const SectionHeader('Sampling'),
              const SizedBox(height: 8),
              GenerationCard(profileKey: profileKey),
            ],
          ],
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final ResponseStyle style;
  final bool selected;
  final VoidCallback onTap;

  static const _titles = {
    ResponseStyle.precise: 'Precise',
    ResponseStyle.balanced: 'Balanced',
    ResponseStyle.creative: 'Creative',
  };
  static const _captions = {
    ResponseStyle.precise: 'Sticks to the facts. Best for code and summaries.',
    ResponseStyle.balanced: 'The model\'s own defaults. Recommended.',
    ResponseStyle.creative: 'Looser and more varied. Occasionally wrong.',
  };

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    return CupertinoButton(
      key: Key('style-${style.name}'),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(17, 15, 15, 15),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
          borderRadius: BorderRadius.circular(GolemRadius.card),
          border: Border.all(
            color: selected
                ? accent
                : CupertinoDynamicColor.resolve(GolemTheme.divider, context),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: GolemShadow.card(context),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titles[style]!,
                    // Explicit ink: CupertinoButton would otherwise tint
                    // the title accent-blue.
                    style: GolemText.bodyStrong.copyWith(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.ink,
                        context,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _captions[style]!,
                    style: GolemText.footnote.copyWith(
                      color: CupertinoDynamicColor.resolve(
                        GolemTheme.mutedInk,
                        context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: '${_titles[style]} selected',
              checked: selected,
              child: Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  color: selected ? accent : null,
                  borderRadius: BorderRadius.circular(12),
                  border: selected
                      ? null
                      : Border.all(
                          width: 2,
                          color: CupertinoDynamicColor.resolve(
                            GolemTheme.borderStrong,
                            context,
                          ),
                        ),
                ),
                child: selected
                    ? const Icon(
                        CupertinoIcons.check_mark,
                        size: 14,
                        color: CupertinoColors.white,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Context tokens the budget controls must always leave for the rendered
/// prompt: the engines reject any request whose prompt plus budget exceeds
/// the context, so a budget equal to the context would fail every send.
/// The reserve keeps short prompts working by construction; very long
/// chats can still exhaust it and surface the engines' budget error.
const _promptReserveTokens = 512;

/// The raw sampling controls for one model profile — Advanced mode's
/// hand-tuning layer, persisted as sparse overrides (#39). Values layer
/// over the response style at generation time; a hand-set knob wins.
class GenerationCard extends ConsumerWidget {
  const GenerationCard({required this.profileKey, super.key});

  final String profileKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = modelProfiles[profileKey];
    if (profile == null) {
      // A custom model runs on the generic style table and has no profile
      // registry entry to hand-tune yet.
      return const SettingsFootnote(
        'This model has no tunable profile on this build.',
      );
    }
    // The direct-mode defaults are the editable surface; thinking-mode
    // sampling can be pinned by the profile (see the footnote).
    final defaults = profile.sampling(reasoningEnabled: false);
    final thinking = profile.sampling(reasoningEnabled: true);
    final thinkingPinned = thinking.pinned;
    final overrides =
        ref.watch(settingsControllerProvider).value?.overridesFor(profileKey) ??
        const SamplingOverrides();
    // Persisted values are sanitized into the controls' ranges before
    // rendering: the store's leaves are deliberately tolerant, and a
    // hand-edited file must not be able to make the steppers throw.
    final contextLength = (overrides.contextLength ?? defaults.contextLength)
        .clamp(1024, 8192);
    final maxTokens = (overrides.maxTokens ?? defaults.maxTokens).clamp(
      256,
      contextLength - _promptReserveTokens,
    );
    // A maxTokens override applies to both reasoning modes, but with no
    // override each mode keeps its own default — the clamp below must
    // satisfy the largest of them (Qwen's thinking budget is 4096 while
    // its direct budget is 2048).
    final effectiveBudget =
        overrides.maxTokens ?? max(defaults.maxTokens, thinking.maxTokens);

    Future<void> update(SamplingOverrides next) => ref
        .read(settingsControllerProvider.notifier)
        .updateModel(profileKey, next);

    return GolemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!overrides.isEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                key: Key('gen-reset-$profileKey'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 30),
                onPressed: () => ref
                    .read(settingsControllerProvider.notifier)
                    .resetModel(profileKey),
                child: const Text('Reset', style: TextStyle(fontSize: 14)),
              ),
            ),
          _SliderRow(
            sliderKey: Key('gen-temperature-$profileKey'),
            label: 'Temperature',
            value: overrides.temperature ?? defaults.temperature,
            isDefault: overrides.temperature == null,
            min: 0,
            max: 2,
            display: (value) => value.toStringAsFixed(2),
            onCommit: (value) =>
                update(overrides.copyWith(temperature: () => value)),
          ),
          _SliderRow(
            sliderKey: Key('gen-top-p-$profileKey'),
            label: 'Top-p',
            value: overrides.topP ?? defaults.topP,
            isDefault: overrides.topP == null,
            min: 0.05,
            max: 1,
            display: (value) => value.toStringAsFixed(2),
            onCommit: (value) => update(overrides.copyWith(topP: () => value)),
          ),
          _SliderRow(
            sliderKey: Key('gen-top-k-$profileKey'),
            label: 'Top-k',
            value: (overrides.topK ?? defaults.topK ?? 0).toDouble(),
            isDefault: overrides.topK == null,
            min: 0,
            max: 100,
            display: (value) => value.round() == 0 ? 'Off' : '${value.round()}',
            onCommit: (value) => update(
              overrides.copyWith(
                topK: () => value.round() == 0 ? null : value.round(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _StepperRow(
            stepperKey: ValueKey<String>('gen-max-tokens-$profileKey'),
            label: 'Max tokens',
            value: maxTokens,
            isDefault: overrides.maxTokens == null,
            step: 256,
            min: 256,
            // The engines reject prompt + budget over the context, so the
            // budget must leave the prompt reserve free.
            max: contextLength - _promptReserveTokens,
            onCommit: (value) =>
                update(overrides.copyWith(maxTokens: () => value)),
          ),
          const SizedBox(height: 6),
          _StepperRow(
            stepperKey: ValueKey<String>('gen-context-$profileKey'),
            label: 'Context length',
            value: contextLength,
            isDefault: overrides.contextLength == null,
            step: 1024,
            min: 1024,
            max: 8192,
            onCommit: (value) => update(
              overrides.copyWith(
                contextLength: () => value,
                // Shrinking the context must keep every mode's effective
                // budget under it, prompt reserve included, or generation
                // in that mode would fail its budget check on every send.
                // The written value never exceeds the number on screen: a
                // clamp may lower the visible budget, never quietly raise
                // it (Qwen's hidden 4096 thinking default clamps down to
                // the displayed direct budget instead).
                maxTokens: effectiveBudget > value - _promptReserveTokens
                    ? () => min(maxTokens, value - _promptReserveTokens)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            thinkingPinned
                ? 'Token budgets always leave 512 context tokens free for '
                      'the prompt. Thinking mode keeps this model\'s pinned '
                      'sampling (temperature 0.6 · top-p 0.95); budgets '
                      'apply to both modes.'
                : 'Token budgets always leave 512 context tokens free for '
                      'the prompt.',
            style: TextStyle(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// A labeled slider whose value commits on drag end; the drag position is
/// widget-local state so a drag never spams persisted saves.
class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.isDefault,
    required this.min,
    required this.max,
    required this.display,
    required this.onCommit,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final bool isDefault;
  final double min;
  final double max;
  final String Function(double value) display;
  final ValueChanged<double> onCommit;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.value).clamp(widget.min, widget.max);
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label, style: const TextStyle(fontSize: 14)),
            ),
            Text(widget.display(value), style: const TextStyle(fontSize: 14)),
            if (widget.isDefault && _drag == null)
              Text(' · default', style: TextStyle(fontSize: 14, color: muted)),
          ],
        ),
        SizedBox(
          height: 34,
          child: CupertinoSlider(
            key: widget.sliderKey,
            value: value,
            min: widget.min,
            max: widget.max,
            onChanged: (next) => setState(() => _drag = next),
            onChangeEnd: (next) {
              setState(() => _drag = null);
              widget.onCommit(next);
            },
          ),
        ),
      ],
    );
  }
}

/// A labeled stepped value with minus/plus buttons; steps snap to the
/// nearest multiple so a default like 2048 stays on the grid.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.stepperKey,
    required this.label,
    required this.value,
    required this.isDefault,
    required this.step,
    required this.min,
    required this.max,
    required this.onCommit,
  });

  final ValueKey<String> stepperKey;
  final String label;
  final int value;
  final bool isDefault;
  final int step;
  final int min;
  final int max;
  final ValueChanged<int> onCommit;

  @override
  Widget build(BuildContext context) {
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    final lower = ((value - step) ~/ step) * step;
    final higher = ((value + step) ~/ step) * step;
    return Row(
      key: stepperKey,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        CupertinoButton(
          key: Key('${stepperKey.value}-minus'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(38, 30),
          onPressed: value <= min
              ? null
              : () => onCommit(lower.clamp(min, max)),
          child: const Icon(CupertinoIcons.minus_circle, size: 22),
        ),
        SizedBox(
          width: 64,
          child: Column(
            children: [
              Text('$value', style: const TextStyle(fontSize: 14)),
              if (isDefault)
                Text('default', style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        ),
        CupertinoButton(
          key: Key('${stepperKey.value}-plus'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(38, 30),
          onPressed: value >= max
              ? null
              : () => onCommit(higher.clamp(min, max)),
          child: const Icon(CupertinoIcons.plus_circle, size: 22),
        ),
      ],
    );
  }
}
