import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import '../../../core/domain/app_preferences.dart';
import '../../../core/domain/equality.dart';
import '../../../core/domain/model_activation.dart' as domain;
import '../../../core/domain/model_catalog.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../settings/application/preferences_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'model_providers.g.dart';

/// A value-equal projection of the only preference leaf the model-catalog
/// derivations consume. Watching the whole [AppPreferences] object made a
/// language or theme change invalidate the catalog while the app root was
/// rebuilding Localizations, which trips Riverpod 3.3.2's known mid-build
/// refresh hazard. The unmodifiable view remains owned by AppPreferences.
final class _CustomModelsSelection {
  const _CustomModelsSelection(this.models);

  final List<CustomModelSpec> models;

  @override
  bool operator ==(Object other) =>
      other is _CustomModelsSelection && listEquals(other.models, models);

  @override
  int get hashCode => listHash(models);
}

_CustomModelsSelection _customModelsFrom(AsyncValue<AppPreferences> value) =>
    _CustomModelsSelection(
      value.value?.customModels ?? const <CustomModelSpec>[],
    );

/// Pinned entries plus the user's custom repositories, derived — never stored —
/// so the pinned manifest stays the single source of model knowledge.
/// KeepAlive, deliberately (#69): watched by always-mounted chat surfaces
/// (composer, drawer, recovery banner), so disposal would never fire in
/// practice — and the 3.3.2 scope-swap hazard (see chatStorageSignature)
/// rules autoDispose out. Revisit when the pin crosses 3.4.0.
@Riverpod(keepAlive: true, retry: noRetry)
List<ModelCatalogEntry> effectiveModelCatalog(Ref ref) {
  final pinned = ref.watch(modelCatalogEntriesProvider);
  final custom = ref
      .watch(preferencesControllerProvider.select(_customModelsFrom))
      .models;
  final pinnedKeys = {for (final entry in pinned) entry.key};
  return [
    ...pinned,
    for (final spec in custom)
      if (!pinnedKeys.contains(spec.key)) spec.toCatalogEntry(),
  ];
}

/// The models a per-chat selection may name: installed, and of the engine this
/// build composed. Derived here so chat, Settings, and Storage cannot disagree
/// about which model is live (#20).
/// KeepAlive, deliberately (#69): same grounds as effectiveModelCatalog —
/// continuously watched, and the 3.3.2 scope-swap hazard. Revisit when the
/// pin crosses 3.4.0.
@Riverpod(keepAlive: true, retry: noRetry)
Set<String> loadableModelKeys(Ref ref) => domain.loadableModelKeys(
  backend: ref.watch(inferenceBackendProvider),
  catalog: ref.watch(effectiveModelCatalogProvider),
  models: ref.watch(modelControllerProvider).value,
);

/// The keys a download may be *started* for: the pinned catalog, plus custom
/// repositories that resolved against Hugging Face and so have a real file
/// list. An unresolved entry synthesizes its files, so a request for it could
/// not succeed — Settings and the chat picker both withhold the affordance
/// rather than failing on the tap, and derive that from here so the rule has
/// one statement (#79).
/// KeepAlive, deliberately (#69): same grounds as loadableModelKeys.
@Riverpod(keepAlive: true, retry: noRetry)
Set<String> downloadableModelKeys(Ref ref) {
  final simulated =
      ref.watch(modelControllerProvider).value?.simulated ??
      ref.watch(inferenceBackendProvider).simulatedInference;
  final pinned = {
    for (final entry in ref.watch(modelCatalogEntriesProvider)) entry.key,
  };
  final resolved = {
    for (final spec
        in ref
            .watch(preferencesControllerProvider.select(_customModelsFrom))
            .models)
      if (spec.resolved != null) spec.key,
  };
  return {
    for (final entry in ref.watch(effectiveModelCatalogProvider))
      if (simulated ||
          pinned.contains(entry.key) ||
          resolved.contains(entry.key))
        entry.key,
  };
}

/// KeepAlive: a command controller whose downloads, busy guard, and epochs
/// must survive leaving the Models screen (§3.4 — an autoDispose command
/// provider dies mid-flight).
@Riverpod(keepAlive: true, retry: noRetry)
class ModelController extends _$ModelController {
  int _operationEpoch = 0;
  // One mutating model operation at a time. Pause and cancel stay exempt:
  // they are the escape hatches that end an in-flight download.
  bool _busy = false;
  bool _releasing = false;

  /// The subset of [_busy] operations that command the engine. Freeing the
  /// engine skips these but not a download: unloading beneath `prepare()` or
  /// beneath `delete()`'s own unload is a real collision, while a transfer
  /// stuck on an unresponsive platform must never block memory relief.
  bool _engineBusy = false;

  @override
  Future<ModelState> build() {
    // Bound before any await so commands arriving during hydration see it.
    // Watched, not read: if the bridge is ever refreshed, this rebuild
    // re-binds the fresh instance instead of leaving readers unbound (#88).
    final bridge = ref.watch(modelSessionBridgeProvider);
    bridge.bindReflectEngineLoaded(reflectEngineLoaded);
    bridge.bindRegisterCustomModel(registerCustomModel);
    return ref.read(modelManagementRepositoryProvider).load();
  }

  /// Re-runs reconciliation and re-attaches to anything the platform is still
  /// transferring. Called at startup once the first state has settled, and on
  /// every return to the foreground — the only moment a transfer the OS moved
  /// on without telling anyone can be noticed.
  ///
  /// Deliberately outside the busy guard: a download stuck waiting on a
  /// platform that stopped answering is precisely when this has to run.
  Future<void> reconcileDownloads() async {
    try {
      // Never before build has installed its own value: Riverpod assigns that
      // result after the fact, and would overwrite the fresher snapshot below
      // with the one the launch pass resolved to — leaving the card stale and
      // the busy guard raised, so the user's own tap does nothing.
      await future;
      final value = await ref.read(modelManagementRepositoryProvider).load();
      if (!ref.mounted) return;
      state = AsyncData(value);
      await _reattach(value);
    } catch (_) {
      // Reconciliation is a repair pass; a failed one must not blank the
      // screen or replace a usable snapshot with an error.
    }
  }

  /// Streams a transfer the platform is already running so its progress
  /// reaches the UI. [download] adopts rather than enqueues, so this never
  /// starts a second writer.
  Future<void> _reattach(ModelState value) async {
    if (_busy) return;
    for (final entry in value.artifacts.entries) {
      if (entry.value.phase == ArtifactPhase.downloading) {
        await download(entry.key);
        return;
      }
    }
  }

  Future<void> download(String artifactKey) async {
    if (_busy) return;
    // Defence in depth behind the withheld card button and the chat banner's
    // absent CTA (#27): a device that can never load these weights must never
    // spend gigabytes fetching them, whichever path asked. Reconciliation is
    // the path that still can — it re-adopts a transfer the platform is still
    // running — so that one is stopped rather than relabelled. Nothing is
    // published over it: the card already carries the reason.
    if (ref.read(deviceRefusalProvider) != null) {
      final phase = state.value?.statusOf(artifactKey).phase;
      if (phase == ArtifactPhase.downloading || phase == ArtifactPhase.paused) {
        await cancel(artifactKey);
      }
      return;
    }
    _busy = true;
    try {
      final epoch = ++_operationEpoch;
      await for (final value
          in ref
              .read(modelManagementRepositoryProvider)
              .download(artifactKey)) {
        if (!ref.mounted || epoch != _operationEpoch) return;
        state = AsyncData(value);
      }
    } catch (error) {
      // Operational failures arrive as failed-phase snapshots; anything that
      // still throws must land on the card, not blank the screen as AsyncError.
      _publishFailure(artifactKey, error);
    } finally {
      _busy = false;
    }
  }

  Future<void> pause(String artifactKey) async {
    _operationEpoch++;
    try {
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .pause(artifactKey);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (error) {
      _publishFailure(artifactKey, error);
    }
  }

  Future<void> cancel(String artifactKey) async {
    _operationEpoch++;
    try {
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .cancel(artifactKey);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (error) {
      _publishFailure(artifactKey, error);
    }
  }

  Future<void> delete(String artifactKey) async {
    if (_busy) return;
    _busy = true;
    _engineBusy = true;
    try {
      // Never delete weights the engine may still have mapped: releasing
      // the runtime comes first, and an unload failure aborts the delete.
      // Residency decides, since a switch can make any installed artifact the
      // one that is mapped (#20).
      final resident =
          ref.read(inferenceRepositoryProvider).residentModelKey.value ??
          state.value?.activeArtifactKey;
      if (artifactKey == resident) {
        await ref.read(inferenceRepositoryProvider).unload();
        if (!ref.mounted) return;
      }
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .delete(artifactKey);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (error) {
      _publishFailure(artifactKey, error);
    } finally {
      _busy = false;
      _engineBusy = false;
    }
  }

  /// Records that the engine holds weights after ChatController's lazy
  /// prepare(). Skips sideloaded paths — outside the catalog's phase tracking.
  Future<void> reflectEngineLoaded() async {
    if (_busy) return;
    final current = state.value;
    final target = _engineTargetKey();
    if (current == null ||
        current.runtime == RuntimePhase.loaded ||
        target == null ||
        current.statusOf(target).phase != ArtifactPhase.installed) {
      return;
    }
    _busy = true;
    _engineBusy = true;
    try {
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .recordRuntime(RuntimePhase.loaded);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (_) {
      // Phase bookkeeping must never disturb an in-flight generation.
    } finally {
      _busy = false;
      _engineBusy = false;
    }
  }

  /// Fast and non-streaming, so it skips the busy gate.
  Future<void> registerCustomModel(ModelCatalogEntry entry) async {
    try {
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .addModel(entry);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (error) {
      _publishFailure(entry.key, error);
    }
  }

  void _publishFailure(String artifactKey, Object error) {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.withArtifact(
        artifactKey,
        current
            .statusOf(artifactKey)
            .copyWith(
              phase: ArtifactPhase.failed,
              failure: '$error',
              failureReason: const ArtifactFailure(
                ArtifactFailureKind.transfer,
              ),
            ),
      ),
    );
  }

  /// The persisted RuntimePhase must reflect the engine, not bookkeeping: a
  /// real `prepare()`/`unload()` runs before the phase is recorded — the
  /// deferred #37 finding, and only the inference repository touches the engine
  /// (#42). Engine failures stay in memory as a failed phase.
  Future<void> toggleRuntime() async {
    if (_busy) return;
    _busy = true;
    _engineBusy = true;
    try {
      final repository = ref.read(modelManagementRepositoryProvider);
      final current = state.requireValue;
      if (current.runtime == RuntimePhase.loaded) {
        try {
          await ref.read(inferenceRepositoryProvider).unload();
        } catch (error) {
          if (!ref.mounted) return;
          state = AsyncData(
            current.copyWith(runtime: RuntimePhase.failed, failure: '$error'),
          );
          return;
        }
        if (!ref.mounted) return;
        final value = await repository.recordRuntime(RuntimePhase.unloaded);
        if (!ref.mounted) return;
        state = AsyncData(value);
      } else {
        // Publish loading at once so the UI can disable the toggle.
        state = AsyncData(
          current.copyWith(runtime: RuntimePhase.loading, clearFailure: true),
        );
        // An unsupported device refuses ahead of every other condition (#27):
        // installed weights change nothing about what this hardware can run.
        // Only this branch — unloading stays reachable, so a phase persisted
        // by an earlier build can always be corrected.
        final refusal = ref.read(deviceRefusalProvider);
        if (refusal != null) {
          final value = await repository.recordRuntime(
            RuntimePhase.failed,
            failure: refusal,
          );
          if (!ref.mounted) return;
          state = AsyncData(value);
          return;
        }
        // A sideload's path is the operator's own and has no catalog phase to
        // gate on; everything else must be installed before the engine is
        // touched, and which artifact that is follows the active chat (#20).
        final backend = ref.read(inferenceBackendProvider);
        final target = _engineTargetKey();
        if (!backend.sideloaded &&
            (target == null ||
                current.statusOf(target).phase != ArtifactPhase.installed)) {
          // Refuse with a persisted failed phase; the engine is never touched.
          final value = await repository.recordRuntime(
            RuntimePhase.failed,
            failure: _installFirstFailure(target),
          );
          if (!ref.mounted) return;
          state = AsyncData(value);
          return;
        }
        try {
          await ref.read(inferenceRepositoryProvider).prepare(modelKey: target);
        } catch (error) {
          if (!ref.mounted) return;
          state = AsyncData(
            current.copyWith(runtime: RuntimePhase.failed, failure: '$error'),
          );
          return;
        }
        if (!ref.mounted) return;
        final value = await repository.recordRuntime(RuntimePhase.loaded);
        if (!ref.mounted) return;
        state = AsyncData(value);
      }
    } finally {
      _busy = false;
      _engineBusy = false;
    }
  }

  /// Frees the engine on an OS memory-pressure signal or backgrounding — the
  /// app must never hold multi-gigabyte weights it is not using while the
  /// platform reclaims memory. Only when idle: an advisory signal never cancels
  /// a visible stream, and the busy guard keeps it off a model operation.
  Future<void> releaseEngineWhileInactive() async {
    // Not gated on the download guard. This is the only defence against holding
    // multi-gigabyte weights under the platform's background memory ceiling,
    // and a download stuck on an unresponsive platform would otherwise disable
    // it for the rest of the process — the app is then jetsammed on the next
    // background transition, which is exactly what this exists to prevent.
    // Engine operations are a different matter: unloading underneath one is a
    // collision, not a rescue.
    if (_engineBusy) return;
    final current = state.value;
    if (current == null) return;
    if (ref.read(chatSessionBridgeProvider).generationActive()) return;
    // Its own guard: backgrounding and memory pressure can both fire, and this
    // still must not unload twice.
    if (_releasing) return;
    _releasing = true;
    try {
      final inference = ref.read(inferenceRepositoryProvider);
      // Residency decides, not the catalog phase: a GOLEM_MODEL_PATH load is
      // outside phase tracking, yet just as resident and just as jetsammable.
      final loaded = current.runtime == RuntimePhase.loaded;
      if (!loaded && inference.residentModelKey.value == null) return;
      await inference.unload();
      if (!ref.mounted || !loaded) return;
      final value = await ref
          .read(modelManagementRepositoryProvider)
          .recordRuntime(RuntimePhase.unloaded);
      if (!ref.mounted) return;
      state = AsyncData(value);
    } catch (_) {
      // Advisory signal: no user-visible failure state.
    } finally {
      _releasing = false;
    }
  }

  /// The model the engine would load now: the active chat's choice when it has
  /// one, else the boot artifact. Null for a sideload, whose path no catalog key
  /// describes, and for a build with no inference backend at all.
  String? _engineTargetKey() {
    final backend = ref.read(inferenceBackendProvider);
    if (backend.sideloaded) return null;
    final chatModelKey = ref.read(chatSessionBridgeProvider).activeModelKey();
    return chatModelKey ?? state.value?.activeArtifactKey;
  }

  /// The load-refusal copy for a not-installed target. Owned here since #42:
  /// the management repository no longer knows why a load was refused.
  String _installFirstFailure(String? target) {
    if (target == null) {
      return 'Inference is a build-time opt-in; no backend is configured.';
    }
    return ref.read(inferenceBackendProvider).simulatedInference
        ? 'Install the selected simulated model first.'
        : 'Download and install the active model first.';
  }
}
