import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/domain/model_activation.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/retry.dart';
import '../../models/application/model_providers.dart';
import 'chat_providers.dart';

part 'active_model_providers.g.dart';

// Stated once (#129). The composer, the model picker, the Models screen,
// Storage and both label helpers each derived it separately, and the copies
// had already drifted in both directions at once: Send dark for a model the
// header named, and lit for an artifact of the other engine (#118).
//
// ChatController deliberately does not read this. It is the *source* of the
// conversation's key, so reading it here would make the provider depend on
// itself; resolveGenerationTarget calls the same pure helper with the state
// that command has just published.
//
// KeepAlive, deliberately (#69): the composer, drawer and nav bar watch it
// continuously, and it inherits the 3.3.2 scope-swap hazard recorded on
// storageBreakdown. Kept out of the doc comment, as in chat_providers.dart:
// riverpod_generator copies those into three places in the .g.dart.
/// The catalog key the open conversation effectively runs. Null exactly where
/// the resolution yields none — an operator sideload, which no catalog entry
/// describes, or a real build with nothing loadable yet.
@Riverpod(keepAlive: true, retry: noRetry)
String? activeModelKey(Ref ref) => effectiveModelKey(
  backend: ref.watch(inferenceBackendProvider),
  catalog: ref.watch(effectiveModelCatalogProvider),
  modelKey: ref.watch(
    chatControllerProvider.select((state) => state.value?.active?.modelKey),
  ),
  residentModelKey: ref.watch(residentModelKeyProvider),
  loadableKeys: ref.watch(loadableModelKeysProvider),
);
