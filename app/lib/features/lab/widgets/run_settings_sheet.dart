import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../broker/model_profile.dart';
import '../../../core/chrome/golem_sheet.dart';
import '../../../l10n/l10n.dart';
import '../application/lab_bench_controller.dart';
import '../domain/lab_run_settings.dart';
import '../lab_copy.dart';
import '../lab_theme.dart';
import 'lab_controls.dart';

/// Opens the run-settings sheet. Edits are held locally and applied as one
/// change, so a conversation is closed once, not per keystroke.
Future<void> showRunSettingsSheet(BuildContext context) => showGolemSheet<void>(
  context: context,
  sheetKey: const Key('lab-settings-sheet'),
  builder: (context) => const _RunSettingsSheet(),
);

class _RunSettingsSheet extends ConsumerStatefulWidget {
  const _RunSettingsSheet();

  @override
  ConsumerState<_RunSettingsSheet> createState() => _RunSettingsSheetState();
}

class _RunSettingsSheetState extends ConsumerState<_RunSettingsSheet> {
  late LabRunSettings _draft;
  late final TextEditingController _seed;
  List<LabSettingsProblem> _problems = const [];

  @override
  void initState() {
    super.initState();
    _draft = ref.read(labBenchControllerProvider).settings;
    _seed = TextEditingController(text: _draft.seed?.toString() ?? '');
  }

  @override
  void dispose() {
    _seed.dispose();
    super.dispose();
  }

  void _apply() {
    final seedText = _seed.text.trim();
    final seed = seedText.isEmpty ? null : int.tryParse(seedText);
    if (seedText.isNotEmpty && seed == null) {
      setState(() => _problems = const [LabSettingsProblem.seedNegative]);
      return;
    }
    final settings = _draft.copyWith(seed: () => seed);
    final problems = ref
        .read(labBenchControllerProvider.notifier)
        .updateSettings(settings);
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The profile's defaults for the draft's mode — never the contract,
    // which already carries the committed overrides and the committed mode.
    final armed = ref.watch(labBenchControllerProvider).armed;
    final defaults = armed == null
        ? null
        : modelProfiles[armed.profileKey]!.sampling(
            reasoningEnabled: _draft.reasoningEnabled,
          );
    final pinned = defaults?.pinned ?? false;
    // Scrolls inside the sheet's ceiling at large text sizes.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(LabSpace.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.labRunSettings,
            style: LabText.headline.copyWith(color: context.ink),
          ),
          const SizedBox(height: LabSpace.s3),
          Text(
            l10n.labRunSettingsNote,
            style: LabText.detail.copyWith(color: context.mutedInk),
          ),
          const SizedBox(height: LabSpace.s7),
          _Stepper(
            name: 'context',
            label: l10n.contextLength,
            value: _draft.contextLength,
            fallback: defaults?.contextLength,
            step: 512,
            onChanged: (v) => setState(
              () => _draft = _draft.copyWith(contextLength: () => v),
            ),
          ),
          _Stepper(
            name: 'max-tokens',
            label: l10n.maxTokens,
            value: _draft.maxTokens,
            fallback: defaults?.maxTokens,
            step: 128,
            onChanged: (v) =>
                setState(() => _draft = _draft.copyWith(maxTokens: () => v)),
          ),
          _Stepper(
            name: 'temperature',
            label: l10n.samplingTemperature,
            value: _draft.temperature,
            fallback: defaults?.temperature,
            step: 0.1,
            decimals: 1,
            pinned: pinned,
            onChanged: (v) =>
                setState(() => _draft = _draft.copyWith(temperature: () => v)),
          ),
          _Stepper(
            name: 'top-p',
            label: l10n.samplingTopP,
            value: _draft.topP,
            fallback: defaults?.topP,
            step: 0.05,
            decimals: 2,
            pinned: pinned,
            onChanged: (v) =>
                setState(() => _draft = _draft.copyWith(topP: () => v)),
          ),
          _Stepper(
            name: 'top-k',
            label: l10n.samplingTopK,
            value: _draft.topK,
            fallback: defaults?.topK,
            step: 10,
            pinned: pinned,
            onChanged: (v) =>
                setState(() => _draft = _draft.copyWith(topK: () => v)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LabSpace.s3),
            child: MergeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.reasoning,
                      style: LabText.row.copyWith(color: context.ink),
                    ),
                  ),
                  CupertinoSwitch(
                    key: const Key('lab-setting-reasoning'),
                    value: _draft.reasoningEnabled,
                    onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(reasoningEnabled: v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (pinned)
            Text(
              l10n.labSettingPinned,
              style: LabText.detail.copyWith(color: context.mutedInk),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LabSpace.s3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.labSettingSeed,
                    style: LabText.row.copyWith(color: context.ink),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: CupertinoTextField(
                    key: const Key('lab-setting-seed'),
                    controller: _seed,
                    placeholder: l10n.labSettingSeedFree,
                    keyboardType: TextInputType.number,
                    style: LabText.row.copyWith(color: context.ink),
                    placeholderStyle: LabText.row.copyWith(
                      color: context.mutedInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final problem in _problems)
            Padding(
              padding: const EdgeInsets.only(top: LabSpace.s2),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  labSettingsProblemMessage(l10n, problem),
                  style: LabText.detail.copyWith(
                    color: labResolveDestructive(context),
                  ),
                ),
              ),
            ),
          const SizedBox(height: LabSpace.s7),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              LabButton(
                key: const Key('lab-settings-cancel'),
                label: l10n.cancel,
                style: LabButtonStyle.quiet,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: LabSpace.s3),
              LabButton(
                key: const Key('lab-settings-apply'),
                label: l10n.labApply,
                style: LabButtonStyle.filled,
                onPressed: _apply,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labelled value with −/+ and a way back to the profile default. A pinned
/// field shows the profile's value and takes no edits.
class _Stepper<T extends num> extends StatelessWidget {
  const _Stepper({
    required this.name,
    required this.label,
    required this.value,
    required this.fallback,
    required this.step,
    required this.onChanged,
    this.decimals = 0,
    this.pinned = false,
  });

  final String name;
  final String label;
  final T? value;
  final T? fallback;
  final T step;
  final int decimals;
  final bool pinned;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // A pinned field shows the profile's value: the user's own is not what
    // will be sent, and the contract chip already says so.
    final shown = pinned ? fallback : value ?? fallback;
    final text = shown == null
        ? '—'
        : decimals == 0
        ? shown.round().toString()
        : shown.toStringAsFixed(decimals);
    final isDefault = value == null;
    T? stepped(int direction) {
      final base = shown ?? (step is int ? 0 : 0.0) as T;
      final next = base + step * direction;
      return (decimals == 0
              ? next.round()
              : double.parse(next.toStringAsFixed(decimals)))
          as T;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LabSpace.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: LabText.row.copyWith(color: context.ink)),
          ),
          if (isDefault || pinned)
            Padding(
              padding: const EdgeInsets.only(right: LabSpace.s3),
              child: Text(
                pinned ? l10n.labSettingPinnedShort : l10n.labSettingDefault,
                style: LabText.detail.copyWith(color: context.mutedInk),
              ),
            ),
          LabButton(
            key: Key('lab-setting-$name-minus'),
            label: '−',
            height: LabSize.tapMinimum,
            semanticLabel: l10n.labDecrease(label),
            onPressed: pinned ? null : () => onChanged(stepped(-1)),
          ),
          SizedBox(
            width: 72,
            child: Text(
              text,
              key: Key('lab-setting-$name'),
              textAlign: TextAlign.center,
              style: LabText.detailStrong.copyWith(color: context.ink),
            ),
          ),
          LabButton(
            key: Key('lab-setting-$name-plus'),
            label: '+',
            height: LabSize.tapMinimum,
            semanticLabel: l10n.labIncrease(label),
            onPressed: pinned ? null : () => onChanged(stepped(1)),
          ),
          const SizedBox(width: LabSpace.s2),
          LabButton(
            key: Key('lab-setting-$name-reset'),
            label: l10n.labSettingDefault,
            style: LabButtonStyle.quiet,
            height: LabSize.tapMinimum,
            semanticLabel: l10n.labResetToDefault(label),
            onPressed: pinned || isDefault ? null : () => onChanged(null),
          ),
        ],
      ),
    );
  }
}
