import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golem_flutter/app/launch_composition.dart';
import 'package:golem_flutter/broker/backend_policy.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/chrome/golem_tappable.dart';
import 'package:golem_flutter/core/chrome/golem_icon_button.dart';
import 'package:golem_flutter/core/chrome/golem_button.dart';
import 'package:golem_flutter/core/domain/device_eligibility.dart';
import 'package:golem_flutter/core/domain/inference_backend.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/repositories/contracts.dart';
import 'package:golem_flutter/core/repositories/fake_benchmark_repository.dart';
import 'package:golem_flutter/core/repositories/fake_inference_repository.dart';
import 'package:golem_flutter/core/repositories/fake_repository_resolver.dart';
import 'package:golem_flutter/core/services/cache_probe.dart';
import 'package:golem_flutter/core/services/device_storage.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/search_screen.dart';
import 'package:golem_flutter/core/domain/download_pace.dart';
import 'package:golem_flutter/features/lab/application/lab_providers.dart';
import 'package:golem_flutter/features/lab/lab_shell.dart';
import 'package:golem_flutter/features/lab/lab_theme.dart';
import 'package:golem_flutter/features/lab/widgets/lab_controls.dart';
import 'package:golem_flutter/features/models/application/download_pace_providers.dart';
import 'package:golem_flutter/l10n/l10n.dart';

import 'in_memory_attachment_repository.dart';
import 'in_memory_chat_history_repository.dart';
import 'in_memory_preferences_repository.dart';
import 'in_memory_settings_repository.dart';

export 'image_fixtures.dart';

/// The iPhone 17 logical viewport every widget/golden suite renders in.
const viewport = Size(402, 874);

/// The window Golem Model Lab opens at, and the smallest it allows
/// (`MainFlutterWindow.swift`'s desktop profile).
const labViewport = Size(1440, 900);
const labMinViewport = Size(1000, 640);

Future<String> fixtureAsset(String key) async =>
    '[{"role": "user", "content": "${'x' * 400}"}]';

void setViewport(WidgetTester tester, {Size size = viewport}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

/// Widget tests report `TargetPlatform.android` unless overridden, and the
/// chrome layer branches on the platform — golden tests pin the axis with
/// these framework-managed variants (a bare override trips the foundation
/// debug-variable invariant at test end).
const iosChrome = TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS});
const androidChrome = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.android,
});
const bothChromes = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.iOS,
  TargetPlatform.android,
});

/// The bench's chrome: it ships on macOS only (ADR 0021).
const macChrome = TargetPlatformVariant(<TargetPlatform>{TargetPlatform.macOS});

/// Filename suffix for the current variant run of a golden matrix test.
String chromeSuffix() => switch (debugDefaultTargetPlatformOverride) {
  TargetPlatform.android => '-android',
  TargetPlatform.macOS => '-macos',
  _ => '',
};

/// The fake backend as `resolveBackendPolicy` would build it for the platform
/// this variant runs, so `simulatedEngine` is set the way a real qa build sets
/// it.
InferenceBackendConfig fakeBackendForTestPlatform() => resolveBackendPolicy(
  backendName: 'fake',
  profileDefine: '',
  artifactDefine: '',
  modelPathDefine: '',
  tier: DeviceTier.preferred,
  platform: switch (debugDefaultTargetPlatformOverride) {
    TargetPlatform.android => HostPlatform.android,
    TargetPlatform.macOS => HostPlatform.macos,
    _ => HostPlatform.ios,
  },
);

/// The tap-target guideline for the chrome this variant runs, so a surface
/// enrolled under [bothChromes] is measured against the same minimum
/// `GolemChrome.minimumTapTarget` promises — 48 on Android, 44 on iOS.
/// Asserting the iOS guideline alone is what let the Android floor ship 4dp
/// short across the shared chrome (#118).
AccessibilityGuideline get tapTargetGuideline =>
    switch (debugDefaultTargetPlatformOverride) {
      TargetPlatform.android => androidTapTargetGuideline,
      TargetPlatform.macOS => labTapTargetGuideline,
      _ => iOSTapTargetGuideline,
    };

/// The pointer tier's minimum: a desktop control is not a thumb target, and
/// the bench promises `LabSize.tapMinimum` on every one of its controls.
final labTapTargetGuideline = MinimumTapTargetGuideline(
  size: const Size(LabSize.tapMinimum, LabSize.tapMinimum),
  link:
      'https://developer.apple.com/design/human-interface-guidelines/'
      'accessibility#Buttons-and-controls',
);

/// The tap handler behind a control, whichever chrome wrapper builds it —
/// `null` means disabled, which is what nearly every caller is asserting.
/// Written once so a control moving between [GolemButton], [GolemIconButton]
/// and [GolemTappable] is not a test change (#131).
VoidCallback? pressedHandler(WidgetTester tester, Finder finder) =>
    switch (tester.widget(finder)) {
      GolemButton(:final onPressed) => onPressed,
      GolemIconButton(:final onPressed) => onPressed,
      GolemTappable(:final onPressed) => onPressed,
      LabButton(:final onPressed) => onPressed,
      LabFocusable(:final onPressed) => onPressed,
      CupertinoButton(:final onPressed) => onPressed,
      final other => throw ArgumentError(
        '${other.runtimeType} is not a button',
      ),
    };

Widget wrapApp({
  required Widget child,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
}) => CupertinoApp(
  debugShowCheckedModeBanner: false,
  theme: GolemTheme.theme(brightness),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

/// 64 decimal GB, matching the handoff's "… of 64 GB" storage meter.
final class FakeDiskCapacity implements DiskCapacityProbe {
  const FakeDiskCapacity([this.bytes = 64 * 1000 * 1000 * 1000]);
  final int? bytes;

  @override
  Future<int?> totalBytes(String path) async => bytes;
}

/// 61.2 decimal GB free, matching the handoff's Storage headline.
final class FakeDiskSpace implements DiskSpaceProbe {
  const FakeDiskSpace([this.bytes = 61200 * 1000 * 1000]);
  final int? bytes;

  @override
  Future<int?> freeBytes(String path) async => bytes;
}

/// One fake launch composition, shared by [buildContainer] and the bootstrap
/// suite so there is a single canonical test wiring of the fifteen seams.
LaunchDependencies launchDependenciesWith({
  Directory? directory,
  ChatHistorySnapshot? history,
  ModelState model = const ModelState(),
  List<ModelCatalogEntry>? catalog,
  InferenceBackendConfig? backend,
  DeviceEligibility? eligibility,
  SettingsRepository? settings,
  PreferencesRepository? preferences,
  AttachmentRepository? attachments,
  CacheProbe? cache,
  CustomRepositoryResolver? resolver,
  ChatHistoryRepository? chatHistory,
  ModelManagementRepository? models,
  InferenceRepository? inference,
  bool includeBenchmark = true,
}) {
  final scratch =
      directory ?? Directory.systemTemp.createTempSync('golem-widget-test-');
  return LaunchDependencies(
    // Resolved through the real policy rather than the bare `.fake()`
    // constant, so the suite exercises the engine a simulation on this
    // platform would compose — the recommendation differs between chromes,
    // and a null `simulatedEngine` would quietly fall back to catalog order
    // and test nothing (#118).
    backendConfig: backend ?? fakeBackendForTestPlatform(),
    deviceEligibility: eligibility ?? const DeviceEligibility.unclassified(),
    chatHistoryRepository:
        chatHistory ??
        InMemoryChatHistoryRepository(
          history ?? const ChatHistorySnapshot(conversations: []),
        ),
    settingsRepository: settings ?? InMemorySettingsRepository(),
    preferencesRepository: preferences ?? InMemoryPreferencesRepository(),
    attachmentRepository: attachments ?? InMemoryAttachmentRepository(),
    cacheProbe: cache ?? FakeCacheProbe(),
    diskFreeSpaceProbe: const FakeDiskSpace(),
    inferenceRepository:
        inference ??
        FakeInferenceRepository(
          eventDelay: Duration.zero,
          catalog: () => catalog ?? modelCatalog,
        ),
    modelCatalogEntries: catalog ?? modelCatalog,
    customRepositoryResolver:
        resolver ?? const DeterministicRepositoryResolver(),
    modelManagementRepository: models ?? StaticModels(model),
    deviceCapacityProbe: const FakeDiskCapacity(),
    documentsPath: scratch.path,
    benchmarkRepository: includeBenchmark
        ? FakeBenchmarkRepository(
            scratch,
            readAsset: fixtureAsset,
            delay: Duration.zero,
          )
        : null,
  );
}

ProviderContainer buildContainer({
  ChatHistorySnapshot? history,
  ModelState model = const ModelState(),
  List<ModelCatalogEntry>? catalog,
  InferenceBackendConfig? backend,
  DeviceEligibility? eligibility,
  SettingsRepository? settings,
  PreferencesRepository? preferences,
  AttachmentRepository? attachments,
  CacheProbe? cache,
  CustomRepositoryResolver? resolver,
  ChatHistoryRepository? chatHistory,
  ModelManagementRepository? models,
  InferenceRepository? inference,
  List<Override> overrides = const [],
}) => ProviderContainer(
  overrides: [
    ...launchOverrides(
      launchDependenciesWith(
        history: history,
        model: model,
        catalog: catalog,
        backend: backend,
        eligibility: eligibility,
        settings: settings,
        preferences: preferences,
        attachments: attachments,
        cache: cache,
        resolver: resolver,
        chatHistory: chatHistory,
        models: models,
        inference: inference,
      ),
    ),
    ...overrides,
  ],
);

/// Pins the live rate/ETA the download surfaces render, so goldens and
/// widget tests never depend on a ticking clock.
final class FixedDownloadPace extends DownloadPace {
  FixedDownloadPace(this.snapshot);

  final DownloadPaceSnapshot? snapshot;

  @override
  DownloadPaceSnapshot? build() => snapshot;
}

Future<void> pumpWithRepositories(
  WidgetTester tester, {
  required Widget child,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  double textScale = 1,
  ChatHistorySnapshot? history,
  ModelState model = const ModelState(),
  List<ModelCatalogEntry>? catalog,
  InferenceBackendConfig? backend,
  DeviceEligibility? eligibility,
  SettingsRepository? settings,
  PreferencesRepository? preferences,
  AttachmentRepository? attachments,
  CacheProbe? cache,
  CustomRepositoryResolver? resolver,
  ChatHistoryRepository? chatHistory,
  ModelManagementRepository? models,
  InferenceRepository? inference,
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  setViewport(tester);
  final container = buildContainer(
    history: history,
    model: model,
    catalog: catalog,
    backend: backend,
    eligibility: eligibility,
    settings: settings,
    preferences: preferences,
    attachments: attachments,
    cache: cache,
    resolver: resolver,
    chatHistory: chatHistory,
    models: models,
    inference: inference,
    overrides: overrides,
  );
  addTearDown(container.dispose);
  final app = UncontrolledProviderScope(
    container: container,
    child: wrapApp(brightness: brightness, locale: locale, child: child),
  );
  await tester.pumpWidget(
    // The app's own MediaQuery takes its scaler from the ancestor it finds, so
    // wrapping here is how a surface is judged at an accessibility size. Built
    // from the view rather than from scratch: a bare MediaQueryData carries
    // Size.zero, which silently lays the whole tree out in a zero-size box —
    // bubbles compute a zero max width and sheets a zero max height.
    textScale == 1
        ? app
        : MediaQuery(
            data: MediaQueryData.fromView(
              tester.view,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: app,
          ),
  );
  if (find.byType(ChatScreen).evaluate().isNotEmpty) {
    final context = tester.element(find.byType(ChatScreen));
    // The drawer header's tile as well as the empty-state mascot: asset
    // decoding is real async work that pump cannot drain, so a golden that
    // draws either one has to precache it rather than rely on the other's
    // runAsync window happening to cover it.
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/golem_mascot.png'),
        context,
      );
      await precacheImage(AssetImage(AppIdentity.current.iconAsset), context);
    });
    await tester.pump();
  }
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Advance provider microtasks and entrance animations without waiting for
    // an intentional indeterminate activity indicator to stop.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// The readings the bench takes off the machine, fixed so a golden holds:
/// a steady footprint and one named Mac.
final class FakeLabProbes
    implements ProcessFootprintProbe, DeviceProvenanceProbe {
  const FakeLabProbes({this.footprintBytes = 3250000000});

  final int? footprintBytes;

  @override
  Future<int?> physicalFootprintBytes() async => footprintBytes;

  @override
  Future<DeviceProvenance?> deviceProvenance() async => const DeviceProvenance(
    model: 'MacBookPro18,3',
    chip: 'Apple M1 Pro',
    memoryBytes: 32 * 1024 * 1024 * 1024,
    osVersion: '26.6.2',
    thermalState: 'nominal',
  );
}

/// Pumps the bench at a desktop size over the lab's launch composition —
/// the consumer wiring with the chat bridge left to the bench controller —
/// and returns the container so a test can drive the controller directly.
Future<ProviderContainer> pumpLabShell(
  WidgetTester tester, {
  Size size = labViewport,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool reducedMotion = false,
  ModelState model = const ModelState(),
  InferenceRepository? inference,
  LabProbes? probes,
  DateTime Function()? clock,
}) async {
  setViewport(tester, size: size);
  final container = ProviderContainer(
    overrides: [
      ...launchOverrides(
        launchDependenciesWith(inference: inference, model: model),
        lab: true,
      ),
      labProbesProvider.overrideWithValue(
        probes ??
            const LabProbes(
              footprint: FakeLabProbes(),
              provenance: FakeLabProbes(),
            ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final app = UncontrolledProviderScope(
    container: container,
    child: wrapApp(
      brightness: brightness,
      locale: locale,
      child: LabShell(clock: clock),
    ),
  );
  await tester.pumpWidget(
    textScale == 1 && !reducedMotion
        ? app
        : MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reducedMotion,
            ),
            child: app,
          ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Pumps a routed app (chat at `/`, search at `/search`) already
/// navigated to the search screen — it pops back to chat, so it needs a
/// real router underneath.
Future<void> pumpSearchScreen(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  ChatHistorySnapshot? history,
}) async {
  setViewport(tester);
  final container = buildContainer(history: history);
  addTearDown(container.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const ChatScreen()),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp.router(
        debugShowCheckedModeBanner: false,
        theme: GolemTheme.theme(brightness),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(router.push('/search'));
  await tester.pumpAndSettle();
}

/// A markdown-rich transcript for renderer goldens: inline code, a
/// fenced block, and a list, kept separate from [seedHistory] so drawer
/// and rename goldens don't re-record when this seed evolves.
///
/// The date sits firmly in the past on purpose: search-result cards
/// print it relative to the wall clock, and a seed near "now" would bake
/// Today/Yesterday into goldens that break the next day.
ChatHistorySnapshot markdownHistory() {
  final conversation = ChatConversation(
    id: 'chat-md',
    title: 'Read a CSV without pandas',
    updatedAt: DateTime.utc(2026, 8, 2),
    messages: [
      ChatMessage.text(
        id: 'user-md',
        role: MessageRole.user,
        text: 'Read a CSV in Python without pandas.',
        createdAt: DateTime.utc(2026, 8, 2),
      ),
      ChatMessage.text(
        id: 'assistant-md',
        role: MessageRole.assistant,
        text:
            'Use the built-in `csv` module. It streams row by row.\n\n'
            '```python\nimport csv\n\ndef rows(path):\n'
            '    with open(path, newline="") as file:\n'
            '        yield from csv.reader(file)\n```\n\n'
            'Two things worth knowing:\n\n'
            '- `newline=""` stops Python mangling quoted line breaks.\n'
            '- Swap in **DictReader** if the file has a header row.',
        metrics: const InferenceMetrics(
          promptTokensPerSecond: 144,
          decodeTokensPerSecond: 24.6,
          tokenCount: 182,
          elapsedSeconds: 7.4,
        ),
        createdAt: DateTime.utc(2026, 8, 2),
      ),
    ],
  );
  return ChatHistorySnapshot(
    conversations: [conversation],
    activeId: conversation.id,
  );
}

/// A transcript whose fenced block carries **no** language on the fence —
/// the path a real model takes when it omits the info string. The fake
/// always tags its Python sample, so this is the only way the untagged
/// branch gets exercised.
ChatHistorySnapshot bareFenceHistory() {
  const code = 'SELECT id, name FROM users WHERE active = true ORDER BY id;';
  final conversation = ChatConversation(
    id: 'chat-bare',
    title: 'Untagged fence',
    updatedAt: DateTime.utc(2026, 8, 2),
    messages: [
      ChatMessage.text(
        id: 'assistant-bare',
        role: MessageRole.assistant,
        text: 'Here you go:\n\n```\n$code\n```\n',
        createdAt: DateTime.utc(2026, 8, 2),
      ),
    ],
  );
  return ChatHistorySnapshot(
    conversations: [conversation],
    activeId: conversation.id,
  );
}

ChatHistorySnapshot seedHistory() {
  final conversation = ChatConversation(
    id: 'chat-1',
    title: 'Plan a quiet weekend',
    updatedAt: DateTime.utc(2026, 8, 2),
    reasoningEnabled: true,
    messages: [
      ChatMessage.text(
        id: 'user-1',
        role: MessageRole.user,
        text: 'Suggest a calm weekend plan close to home.',
        createdAt: DateTime.utc(2026, 8, 2),
      ),
      ChatMessage.text(
        id: 'assistant-1',
        role: MessageRole.assistant,
        text:
            'Start slowly: coffee, a long walk, and an afternoon with a good book.',
        reasoning: 'I’ll balance rest, movement, and one small delight.',
        metrics: const InferenceMetrics(
          promptTokensPerSecond: 144,
          decodeTokensPerSecond: 21.4,
          tokenCount: 18,
          elapsedSeconds: 0.84,
        ),
        createdAt: DateTime.utc(2026, 8, 2),
      ),
    ],
  );
  return ChatHistorySnapshot(
    conversations: [conversation],
    activeId: conversation.id,
  );
}

/// A frozen model repository: every operation reports the same state.
/// [StaticModels] that keeps what it is told, so a test can read back the phase
/// a load reflected or the artifact a delete cleared.
final class RecordingModels implements ModelManagementRepository {
  RecordingModels([this.state = const ModelState()]);

  ModelState state;
  int recordRuntimeCalls = 0;

  @override
  Future<ModelState> load() async => state;

  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    RuntimeFailureKind? failure,
  }) async {
    recordRuntimeCalls++;
    // Both real implementations clear on a null kind rather than letting
    // copyWith's `failure ?? this.failure` carry the old one forward; a fake
    // that keeps it reports a stale failure under a loaded runtime.
    return state = failure == null
        ? state.copyWith(runtime: phase, clearFailure: true)
        : state.copyWith(runtime: phase, failure: failure);
  }

  @override
  Future<ModelState> delete(String artifactKey) async =>
      state = state.withArtifact(artifactKey, const ArtifactStatus());

  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(state);

  @override
  Future<ModelState> pause(String artifactKey) async => state;

  @override
  Future<ModelState> cancel(String artifactKey) async => state;

  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => state;
}

final class StaticModels implements ModelManagementRepository {
  const StaticModels(this.state);
  final ModelState state;

  @override
  Future<ModelState> load() async => state;
  @override
  Future<ModelState> recordRuntime(
    RuntimePhase phase, {
    RuntimeFailureKind? failure,
  }) => Future.value(state);
  @override
  Stream<ModelState> download(String artifactKey) => Stream.value(state);
  @override
  Future<ModelState> pause(String artifactKey) async => state;
  @override
  Future<ModelState> cancel(String artifactKey) async => state;
  @override
  Future<ModelState> delete(String artifactKey) async => state;
  @override
  Future<ModelState> addModel(ModelCatalogEntry entry) async => state;
}
