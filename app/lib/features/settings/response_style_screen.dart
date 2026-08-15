import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Deliberate layering note: features may consume the broker's model
// knowledge (profiles carry no Inferno import); the Inferno boundary is
// unchanged — only lib/broker/ touches package:inferno.
import '../../broker/model_profile.dart';
import '../../core/chrome/golem_chrome.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/domain/app_preferences.dart';
import '../../core/domain/generation_settings.dart';
import '../../core/domain/response_style_mapping.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/retry_pane.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';
import '../chat/model_label.dart';
import '../models/application/model_providers.dart';
import 'application/preferences_providers.dart';
import 'application/settings_providers.dart';
import 'save_feedback.dart';
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
        title: context.l10n.responseStyle,
        previousPageTitle: context.l10n.settings,
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
                context.l10n.responseStyleDescription(modelLabel),
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
                onTap: () => announceFailedSave(
                  context,
                  ref
                      .read(preferencesControllerProvider.notifier)
                      .setResponseStyle(profileKey, style),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (!preferences.advancedMode)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SettingsFootnote(context.l10n.advancedSamplingHint),
              )
            else ...[
              const SizedBox(height: 14),
              SectionHeader(context.l10n.sampling),
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

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    // Selection belongs to the row, and only to the row that has it. The tick
    // used to carry "<title> selected" as its own label unconditionally, so
    // every option announced itself as chosen and the chosen one said its
    // title twice (#118). Same shape as the language rows.
    return Semantics(
      selected: selected,
      value: selected
          ? context.l10n.selectedOption(_styleTitle(context, style))
          : null,
      child: CupertinoButton(
        key: Key('style-${style.name}'),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.fromSTEB(17, 15, 15, 15),
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
                      _styleTitle(context, style),
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
                      _styleDetail(context, style),
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
              // Dial face: the row above says what this paints.
              Container(
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
            ],
          ),
        ),
      ),
    );
  }
}

String _styleTitle(BuildContext context, ResponseStyle style) =>
    switch (style) {
      ResponseStyle.precise => context.l10n.stylePrecise,
      ResponseStyle.balanced => context.l10n.styleBalanced,
      ResponseStyle.creative => context.l10n.styleCreative,
    };

String _styleDetail(BuildContext context, ResponseStyle style) =>
    switch (style) {
      ResponseStyle.precise => context.l10n.stylePreciseDetail,
      ResponseStyle.balanced => context.l10n.styleBalancedDetail,
      ResponseStyle.creative => context.l10n.styleCreativeDetail,
    };

String _styleSource(BuildContext context, ResponseStyle style) =>
    switch (style) {
      ResponseStyle.precise => context.l10n.stylePreciseLowercase,
      ResponseStyle.balanced => context.l10n.styleBalancedLowercase,
      ResponseStyle.creative => context.l10n.styleCreativeLowercase,
    };

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
      return SettingsFootnote(context.l10n.noTunableProfile);
    }
    // The direct-mode defaults are the editable surface; thinking-mode
    // sampling can be pinned by the profile (see the footnote).
    final defaults = profile.sampling(reasoningEnabled: false);
    final thinking = profile.sampling(reasoningEnabled: true);
    final thinkingPinned = thinking.pinned;
    final settings = ref.watch(settingsControllerProvider);
    if (settings.hasError) {
      // Editing over invented defaults would overwrite whatever the store
      // holds on the next successful write; surface the failed read instead.
      return RetryPane(
        key: const Key('settings-load-error'),
        message: context.l10n.settingsLoadFailed,
        actionLabel: context.l10n.tryAgain,
        onRetry: () => ref.invalidate(settingsControllerProvider),
      );
    }
    final overrides =
        settings.value?.overridesFor(profileKey) ?? const SamplingOverrides();
    // The card must state what generation will actually run: the response
    // style's values layered under the hand-set overrides, exactly as
    // ChatController computes them. Captions name each value's source.
    final style =
        ref.watch(preferencesControllerProvider).value?.styleFor(profileKey) ??
        ResponseStyle.balanced;
    final styleOverrides = styleOverridesFor(profileKey, style);
    String? caption(Object? manual, Object? styled) => manual != null
        ? null
        : styled != null
        ? context.l10n.styleSource(_styleSource(context, style))
        : context.l10n.defaultSource;
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

    Future<void> update(SamplingOverrides next) => announceFailedSave(
      context,
      ref
          .read(settingsControllerProvider.notifier)
          .updateModel(profileKey, next),
    );

    return GolemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!overrides.isEmpty)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: CupertinoButton(
                key: Key('gen-reset-$profileKey'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                // Square, not `fromHeight`: that sets an infinite minimum
                // width, which the parent clamps to its own — and a
                // full-width Reset would ignore the trailing Align above it.
                minimumSize: Size.square(GolemChrome.current.minimumTapTarget),
                onPressed: () => announceFailedSave(
                  context,
                  ref
                      .read(settingsControllerProvider.notifier)
                      .resetModel(profileKey),
                ),
                child: Text(
                  context.l10n.reset,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          _SliderRow(
            sliderKey: Key('gen-temperature-$profileKey'),
            label: context.l10n.samplingTemperature,
            value:
                overrides.temperature ??
                styleOverrides.temperature ??
                defaults.temperature,
            caption: caption(overrides.temperature, styleOverrides.temperature),
            min: 0,
            max: 2,
            display: (value) => value.toStringAsFixed(2),
            onCommit: (value) =>
                update(overrides.copyWith(temperature: () => value)),
          ),
          _SliderRow(
            sliderKey: Key('gen-top-p-$profileKey'),
            label: context.l10n.samplingTopP,
            value: overrides.topP ?? styleOverrides.topP ?? defaults.topP,
            caption: caption(overrides.topP, styleOverrides.topP),
            min: 0.05,
            max: 1,
            display: (value) => value.toStringAsFixed(2),
            onCommit: (value) => update(overrides.copyWith(topP: () => value)),
          ),
          _SliderRow(
            sliderKey: Key('gen-top-k-$profileKey'),
            label: context.l10n.samplingTopK,
            value: (overrides.topK ?? styleOverrides.topK ?? defaults.topK ?? 0)
                .toDouble(),
            caption: caption(overrides.topK, styleOverrides.topK),
            min: 0,
            max: 100,
            display: (value) =>
                value.round() == 0 ? context.l10n.off : '${value.round()}',
            onCommit: (value) => update(
              overrides.copyWith(
                topK: () => value.round() == 0 ? null : value.round(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _StepperRow(
            stepperKey: ValueKey<String>('gen-max-tokens-$profileKey'),
            label: context.l10n.maxTokens,
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
            label: context.l10n.contextLength,
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
            // Value-free on purpose: the pinned recipe lives with the
            // profile, and a hardcoded copy of it has already drifted once.
            thinkingPinned
                ? context.l10n.pinnedTokenBudgetFootnote
                : context.l10n.tokenBudgetFootnote,
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
    required this.caption,
    required this.min,
    required this.max,
    required this.display,
    required this.onCommit,
  });

  final Key sliderKey;
  final String label;
  final double value;

  /// Source caption ('· default', '· precise', …); null when the value is
  /// a hand-set override.
  final String? caption;
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
            if (widget.caption != null && _drag == null)
              Text(
                ' ${widget.caption}',
                style: TextStyle(fontSize: 14, color: muted),
              ),
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
    // One adjustable control rather than two unlabeled glyph buttons — the
    // same shape the text-size slider uses. The name is the row's own label
    // and the value is the number already on screen, so nothing new is said;
    // "increase"/"decrease" come from the platform's own vocabulary.
    return Semantics(
      container: true,
      label: label,
      value: '$value',
      // The framework requires the projected readings beside the actions, so
      // a screen reader can say where a step lands before taking it.
      increasedValue: '${higher.clamp(min, max)}',
      decreasedValue: '${lower.clamp(min, max)}',
      onIncrease: value >= max ? null : () => onCommit(higher.clamp(min, max)),
      onDecrease: value <= min ? null : () => onCommit(lower.clamp(min, max)),
      child: ExcludeSemantics(
        child: Row(
          key: stepperKey,
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            CupertinoButton(
              key: Key('${stepperKey.value}-minus'),
              padding: EdgeInsets.zero,
              minimumSize: Size.square(GolemChrome.current.minimumTapTarget),
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
                    Text(
                      context.l10n.defaultLowercase,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                ],
              ),
            ),
            CupertinoButton(
              key: Key('${stepperKey.value}-plus'),
              padding: EdgeInsets.zero,
              minimumSize: Size.square(GolemChrome.current.minimumTapTarget),
              onPressed: value >= max
                  ? null
                  : () => onCommit(higher.clamp(min, max)),
              child: const Icon(CupertinoIcons.plus_circle, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
