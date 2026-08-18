import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chrome/golem_button.dart';
import '../../../core/chrome/golem_chrome.dart';
import '../../../core/chrome/golem_toast.dart';
import '../../../core/domain/byte_format.dart';
import '../../../core/domain/model_catalog.dart';
import '../../../core/theme/golem_theme.dart';
import '../../../core/widgets/labeled_row.dart';
import '../../../core/widgets/settings_rows.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/presentation_messages.dart';
import '../application/custom_repository_controller.dart';

/// The Advanced-mode custom-repository loader: name a repository, read it, see
/// exactly what was found, then add it.
///
/// Paints [CustomRepositoryController] and forwards intent to it. The two text
/// controllers stay widget-local — cursor and IME are widget state — and seed
/// from the draft, so leaving and re-entering the screen restores the fields
/// and the resolution together.
class CustomRepositoryCard extends ConsumerStatefulWidget {
  const CustomRepositoryCard({required this.simulatedDownloads, super.key});

  /// Both backends resolve, so only the copy differs — a simulated size is
  /// never presented as something that was measured.
  final bool simulatedDownloads;

  @override
  ConsumerState<CustomRepositoryCard> createState() =>
      _CustomRepositoryCardState();
}

class _CustomRepositoryCardState extends ConsumerState<CustomRepositoryCard> {
  late final TextEditingController _repository;
  late final TextEditingController _revision;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(customRepositoryControllerProvider);
    _repository = TextEditingController(text: draft.repository);
    _revision = TextEditingController(text: draft.revision);
  }

  @override
  void dispose() {
    _repository.dispose();
    _revision.dispose();
    super.dispose();
  }

  CustomRepositoryController get _controller =>
      ref.read(customRepositoryControllerProvider.notifier);

  Future<void> _resolve({String? weightsFile}) =>
      _controller.resolve(weightsFile: weightsFile);

  Future<void> _add() async {
    if (await _controller.add()) {
      _repository.clear();
      _revision.clear();
      if (mounted) showGolemToast(context, context.l10n.modelAdded);
      return;
    }
    // The preference write failed and rolled back; the resolution card is
    // still on screen, so Add remains the retry affordance.
    if (mounted) showGolemToast(context, context.l10n.modelSaveFailed);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(customRepositoryControllerProvider);
    final muted = CupertinoDynamicColor.resolve(GolemTheme.mutedInk, context);
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _EngineChip(
                    key: const Key('custom-repo-engine-mlx'),
                    label: 'MLX',
                    selected: draft.engine == ModelEngine.mlx,
                    onTap: () => _controller.selectEngine(ModelEngine.mlx),
                  ),
                  const SizedBox(width: 8),
                  _EngineChip(
                    key: const Key('custom-repo-engine-gguf'),
                    label: 'GGUF',
                    selected: draft.engine == ModelEngine.gguf,
                    onTap: () => _controller.selectEngine(ModelEngine.gguf),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _field(
                context,
                key: const Key('custom-repo-field'),
                controller: _repository,
                onChanged: (value) => _controller.edit(repository: value),
                placeholder: draft.engine == ModelEngine.mlx
                    ? 'mlx-community/model-name'
                    : 'org/model-name-GGUF',
                muted: muted,
              ),
              const SizedBox(height: 10),
              _field(
                context,
                key: const Key('custom-repo-revision'),
                controller: _revision,
                onChanged: (value) => _controller.edit(revision: value),
                placeholder: context.l10n.repositoryRevisionPlaceholder,
                muted: muted,
              ),
              const SizedBox(height: 16),
              ..._outcome(context, draft.outcome, muted),
              const SizedBox(height: 12),
              Text(switch (draft.outcome) {
                AddResolved(:final resolution)
                    when resolution.profile == null =>
                  context.l10n.unknownTemplateWarning,
                _ when widget.simulatedDownloads =>
                  context.l10n.simulatedRepositoryDetail,
                _ => context.l10n.publicRepositoryDetail,
              }, style: GolemText.footnote.copyWith(color: muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(
    BuildContext context, {
    required Key key,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required String placeholder,
    required Color muted,
  }) => CupertinoTextField(
    key: key,
    controller: controller,
    textDirection: TextDirection.ltr,
    placeholder: placeholder,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: onChanged,
    style: GolemText.code,
    placeholderStyle: GolemText.code.copyWith(color: muted),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      border: Border.all(
        color: CupertinoDynamicColor.resolve(GolemTheme.borderStrong, context),
      ),
      borderRadius: BorderRadius.circular(GolemRadius.field),
    ),
  );

  List<Widget> _outcome(
    BuildContext context,
    AddRepositoryOutcome outcome,
    Color muted,
  ) => switch (outcome) {
    AddIdle() => [_resolveButton()],
    AddResolving() => [
      Row(
        children: [
          const CupertinoActivityIndicator(radius: 8),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              context.l10n.readingRepository,
              style: GolemText.footnote.copyWith(color: muted),
            ),
          ),
        ],
      ),
    ],
    AddRefused(:final reason) => [
      Text(
        key: const Key('custom-repo-error'),
        repositoryRejectionMessage(context.l10n, reason),
        style: GolemText.footnote.copyWith(
          color: CupertinoDynamicColor.resolve(GolemTheme.destructive, context),
        ),
      ),
      const SizedBox(height: 14),
      _resolveButton(label: context.l10n.tryAgain),
    ],
    AddNeedsWeights(:final candidates) => [
      Text(
        context.l10n.chooseWeightFile,
        style: GolemText.footnote.copyWith(color: muted),
      ),
      const SizedBox(height: 10),
      for (final candidate in candidates)
        CupertinoButton(
          key: Key('custom-repo-candidate-${candidate.path}'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          minimumSize: Size.square(GolemChrome.current.minimumTapTarget),
          onPressed: () => _resolve(weightsFile: candidate.path),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  candidate.path,
                  style: GolemText.code,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                gigabytes(candidate.bytes),
                style: GolemText.footnote.copyWith(color: muted),
              ),
            ],
          ),
        ),
    ],
    AddResolved(:final resolution) => [
      Column(
        key: const Key('custom-repo-detail'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabeledRow(
            label: context.l10n.revision,
            // The commit, not the ref that was typed: this is what installs.
            value: resolution.resolved.commitSha.substring(0, 12),
          ),
          const SizedBox(height: 8),
          LabeledRow(
            label: context.l10n.quantization,
            value: resolution.resolved.quantization,
          ),
          const SizedBox(height: 8),
          LabeledRow(
            label: context.l10n.size,
            value: gigabytes(resolution.resolved.totalBytes),
          ),
          const SizedBox(height: 8),
          LabeledRow(
            label: context.l10n.promptProfile,
            value: resolution.profile?.key ?? context.l10n.notRecognized,
          ),
          const SizedBox(height: 12),
          for (final file in resolution.resolved.files.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.path,
                      style: GolemText.code.copyWith(color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    gigabytes(file.bytes),
                    style: GolemText.footnote.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          if (resolution.resolved.files.length > 5)
            Text(
              context.l10n.moreFiles(resolution.resolved.files.length - 5),
              style: GolemText.footnote.copyWith(color: muted),
            ),
        ],
      ),
      const SizedBox(height: 16),
      GolemButton.filled(
        key: const Key('custom-repo-add'),
        label: context.l10n.addModel,
        onPressed: _add,
      ),
    ],
  };

  Widget _resolveButton({String? label}) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _repository,
        builder: (context, value, _) => GolemButton.filled(
          key: const Key('custom-repo-resolve'),
          label: label ?? context.l10n.resolveRepository,
          onPressed: value.text.trim().isEmpty ? null : () => _resolve(),
        ),
      );
}

class _EngineChip extends StatelessWidget {
  const _EngineChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoDynamicColor.resolve(GolemTheme.accent, context);
    // A 6pt dot and a fill were the only cue that this pair is a choice.
    return Semantics(
      selected: selected,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.square(GolemChrome.current.minimumTapTarget),
        onPressed: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(
              selected ? GolemTheme.accentSoft : GolemTheme.fillQuiet,
              context,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: GolemText.captionStrong.copyWith(
                  color: selected
                      ? CupertinoDynamicColor.resolve(
                          GolemTheme.accentIcon,
                          context,
                        )
                      : CupertinoDynamicColor.resolve(
                          GolemTheme.mutedInk,
                          context,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
