import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/image_intake.dart';
import '../../../core/chrome/golem_toast.dart';
import '../../../core/theme/golem_theme.dart';
import '../model_label.dart';
import 'attach_sheet.dart';
import 'model_picker_sheet.dart';

class Composer extends ConsumerStatefulWidget {
  const Composer({
    required this.controller,
    required this.focus,
    required this.reasoningEnabled,
    required this.generation,
    required this.activeId,
    required this.modelKey,
    this.picker = const AttachmentPicker(),
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final bool reasoningEnabled;
  final GenerationPhase generation;

  /// The active conversation, if one exists yet.
  final String? activeId;
  final String? modelKey;

  final AttachmentPicker picker;

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  /// Images chosen but not yet sent. Composition state, like the draft text:
  /// nothing durable exists until send copies the bytes into the store.
  final List<PreparedImage> _pending = [];

  /// A picked image belongs to the chat it was picked in. The Composer element
  /// is reused across a drawer switch, so without this the tray would follow
  /// the user into the next conversation and send there.
  @override
  void didUpdateWidget(Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeId != oldWidget.activeId && _pending.isNotEmpty) {
      setState(_pending.clear);
    }
  }

  /// Rejections surface as a toast rather than a banner: nothing was sent, and
  /// the user's next move is simply to pick a different picture.
  Future<void> _attach(String modelLabel, bool supportsImages) async {
    try {
      final source = await showAttachSheet(
        context,
        modelLabel: modelLabel,
        supportsImages: supportsImages,
      );
      if (source == null || !mounted) return;
      final picked = await widget.picker.pick(source);
      if (picked == null || !mounted) return;
      setState(() => _pending.add(picked));
    } on ImageRejectedException catch (error) {
      if (!mounted) return;
      showGolemToast(context, switch (error.reason) {
        ImageRejection.unsupportedType =>
          'That file type is not supported. Use a JPEG, PNG, or WebP image.',
        ImageRejection.tooLarge => 'That image is too large to attach.',
        ImageRejection.undecodable => 'That image could not be read.',
      });
    } catch (error) {
      // The picker is a platform channel: a denied permission, a revoked grant
      // and a photo that never materialized all arrive as something other than
      // a rejection. Silence would look like a dead button.
      if (!mounted) return;
      final denied =
          error is PlatformException &&
          const {
            'camera_access_denied',
            'camera_access_restricted',
            'photo_access_denied',
            'photo_access_restricted',
          }.contains(error.code);
      showGolemToast(
        context,
        denied
            ? 'Golem needs access to your camera and photos. Turn it on in '
                  'Settings to attach a picture.'
            : 'That picture could not be added.',
      );
    }
  }

  Widget _tray(BuildContext context) => Padding(
    key: const Key('composer-attachments'),
    padding: const EdgeInsets.only(top: GolemSpace.s3, bottom: GolemSpace.s1),
    child: Row(
      children: [
        for (var index = 0; index < _pending.length; index++)
          Padding(
            padding: const EdgeInsets.only(right: GolemSpace.s2),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(GolemRadius.field),
                  child: Image.memory(
                    _pending[index].bytes,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    // Decorative: the remove button beside it carries the
                    // accessible name.
                    excludeFromSemantics: true,
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: CupertinoButton(
                    key: Key('composer-attachment-remove-$index'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(
                      GolemSize.hitTarget,
                      GolemSize.hitTarget,
                    ),
                    onPressed: () => setState(() => _pending.removeAt(index)),
                    child: Semantics(
                      button: true,
                      label: 'Remove attached image',
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: CupertinoDynamicColor.resolve(
                            GolemTheme.surface,
                            context,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: CupertinoDynamicColor.resolve(
                              GolemTheme.divider,
                              context,
                            ),
                          ),
                        ),
                        child: Icon(
                          CupertinoIcons.xmark,
                          size: 12,
                          color: CupertinoDynamicColor.resolve(
                            GolemTheme.mutedInk,
                            context,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  TextEditingController get controller => widget.controller;
  FocusNode get focus => widget.focus;
  bool get reasoningEnabled => widget.reasoningEnabled;
  GenerationPhase get generation => widget.generation;
  String? get activeId => widget.activeId;
  String? get modelKey => widget.modelKey;

  @override
  Widget build(BuildContext context) {
    final generating = generation != GenerationPhase.idle;
    final backend = ref.watch(inferenceBackendProvider);
    final catalog = ref.watch(effectiveModelCatalogProvider);
    final resident = ref.watch(residentModelKeyProvider);
    final loadable = ref.watch(loadableModelKeysProvider);
    final modelLabel = chatModelLabel(
      backend: backend,
      catalog: catalog,
      modelKey: modelKey,
      residentModelKey: resident,
      loadableKeys: loadable,
    );
    final supportsImages = chatModelSupportsImages(
      backend: backend,
      catalog: catalog,
      modelKey: modelKey,
      residentModelKey: resident,
      loadableKeys: loadable,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        GolemSpace.gutter,
        8,
        GolemSpace.gutter,
        8 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      // Per the handoff: a solid card with the float shadow, not glass.
      child: Container(
        key: const Key('composer-card'),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
          ),
          boxShadow: GolemShadow.float(context),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 10, 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_pending.isNotEmpty) _tray(context),
              CupertinoTextField.borderless(
                key: const Key('chat-composer'),
                controller: controller,
                focusNode: focus,
                enabled: !generating,
                // Left null, a borderless field paints Flutter's built-in
                // disabled fill (near-black in dark mode) over the card while
                // generating; an empty decoration keeps it transparent.
                decoration: const BoxDecoration(),
                minLines: 1,
                maxLines: 6,
                placeholder: 'Message Golem…',
                textInputAction: TextInputAction.newline,
                // 14pt keeps the single-line field at the 44pt tap target.
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // The left cluster yields as one group so send stays pinned
                  // right; inside it only the model chip shrinks.
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PowerButton(
                          buttonKey: const Key('composer-attach'),
                          semanticLabel: 'Add to this chat',
                          onPressed: generating
                              ? null
                              : () => _attach(modelLabel, supportsImages),
                          child: _circle(
                            context,
                            child: Icon(
                              CupertinoIcons.plus,
                              size: 19,
                              color: CupertinoDynamicColor.resolve(
                                GolemTheme.mutedInk,
                                context,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Intrinsic width with a hard cap: sharing flex with a
                        // trailing Spacer starved the label to nothing on device.
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 190),
                            child: _PowerButton(
                              buttonKey: const Key('composer-model-chip'),
                              semanticLabel: 'Model for this chat',
                              onPressed: generating
                                  ? null
                                  : () => _openModelPicker(context, ref),
                              child: Container(
                                height: 34,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: CupertinoDynamicColor.resolve(
                                    GolemTheme.field,
                                    context,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    GolemRadius.pill,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: CupertinoDynamicColor.resolve(
                                          GolemTheme.accent,
                                          context,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Flexible(
                                      child: Text(
                                        modelLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GolemText.captionStrong.copyWith(
                                          color: CupertinoDynamicColor.resolve(
                                            GolemTheme.mutedInk,
                                            context,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      CupertinoIcons.chevron_down,
                                      size: 14,
                                      color: CupertinoDynamicColor.resolve(
                                        GolemTheme.tertiaryInk,
                                        context,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _PowerButton(
                          buttonKey: const Key('reasoning-toggle'),
                          semanticLabel: reasoningEnabled
                              ? 'Reasoning on'
                              : 'Reasoning off',
                          onPressed: generating
                              ? null
                              : () => ref
                                    .read(chatControllerProvider.notifier)
                                    .toggleReasoning(),
                          child: reasoningEnabled
                              ? Container(
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CupertinoDynamicColor.resolve(
                                      GolemTheme.reasoningSurface,
                                      context,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      GolemRadius.pill,
                                    ),
                                    border: Border.all(
                                      color: CupertinoDynamicColor.resolve(
                                        GolemTheme.reasoningBorder,
                                        context,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        CupertinoIcons.lightbulb_fill,
                                        size: 15,
                                        color: GolemTheme.amber,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Think',
                                        style: GolemText.captionStrong.copyWith(
                                          color: CupertinoDynamicColor.resolve(
                                            GolemTheme.ink,
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : _circle(
                                  context,
                                  child: Icon(
                                    CupertinoIcons.lightbulb,
                                    size: 18,
                                    color: CupertinoDynamicColor.resolve(
                                      GolemTheme.mutedInk,
                                      context,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  // Only send depends on the live text, so it listens to the
                  // controller alone instead of rebuilding the whole composer
                  // on every keystroke.
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final hasText = controller.text.trim().isNotEmpty;
                      // An image alone is a complete turn — but a tray the
                      // current model cannot read is not one. The picture stays,
                      // with its remove button, so the way out is visible.
                      final canSend =
                          (hasText || _pending.isNotEmpty) &&
                          (_pending.isEmpty || supportsImages);
                      return CupertinoButton(
                        key: Key(generating ? 'stop-button' : 'send-button'),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: generating
                            ? () => ref
                                  .read(chatControllerProvider.notifier)
                                  .stop()
                            : !canSend
                            ? null
                            : () async {
                                final text = controller.text;
                                final images = List.of(_pending);
                                controller.clear();
                                setState(_pending.clear);
                                if (ref
                                        .read(preferencesControllerProvider)
                                        .value
                                        ?.hapticsOnSend ??
                                    true) {
                                  HapticFeedback.lightImpact();
                                }
                                try {
                                  await ref
                                      .read(chatControllerProvider.notifier)
                                      .send(text, images: images);
                                } catch (_) {
                                  // send() only throws when an attachment never
                                  // reached disk; the banner is already up, so
                                  // this puts the turn back within reach rather
                                  // than losing the picture with it.
                                  if (!mounted) return;
                                  controller.text = text;
                                  setState(() => _pending.addAll(images));
                                }
                              },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: generating || canSend
                                ? CupertinoDynamicColor.resolve(
                                    GolemTheme.accent,
                                    context,
                                  )
                                : CupertinoDynamicColor.resolve(
                                    GolemTheme.divider,
                                    context,
                                  ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: generating
                                ? Semantics(
                                    label: 'Stop',
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.white,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    CupertinoIcons.arrow_up,
                                    semanticLabel: 'Send',
                                    color: CupertinoColors.white,
                                    size: 20,
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openModelPicker(BuildContext context, WidgetRef ref) async {
    var conversationId = activeId;
    if (conversationId == null) {
      final controller = ref.read(chatControllerProvider.notifier);
      await controller.newChat();
      conversationId = ref.read(chatControllerProvider).value?.activeId;
    }
    if (conversationId == null || !context.mounted) return;
    await showModelPickerSheet(context, conversationId: conversationId);
  }

  Widget _circle(BuildContext context, {required Widget child}) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(GolemTheme.field, context),
      shape: BoxShape.circle,
    ),
    child: Center(child: child),
  );
}

/// A power-row control with a 34pt visual inside a 44pt hit target.
final class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.buttonKey,
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
  });
  final Key buttonKey;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    key: buttonKey,
    padding: EdgeInsets.zero,
    minimumSize: const Size(44, 44),
    onPressed: onPressed,
    child: Semantics(label: semanticLabel, child: child),
  );
}
