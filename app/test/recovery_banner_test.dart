import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golem_flutter/core/domain/model_catalog.dart';
import 'package:golem_flutter/core/domain/models.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/core/repositories/fake_model_management_repository.dart';
import 'package:golem_flutter/features/chat/widgets/recovery_banner.dart';

const _catalog = [
  ModelCatalogEntry(
    key: 'test-gguf',
    displayName: 'Test Model',
    engine: ModelEngine.gguf,
    quantization: 'Q4_0',
    repository: 'example/test-gguf',
    revision: 'fedcba9876543210',
    files: [
      ModelArtifactFile(path: 'model.gguf', bytes: 2600000000, sha256: 'bb'),
    ],
  ),
];

void main() {
  testWidgets('the missing-model banner offers the sized download CTA', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('golem-banner-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final models = FakeModelManagementRepository(
      File('${directory.path}/model.json'),
      catalog: _catalog,
      activeArtifactKey: 'test-gguf',
      stepDelay: Duration.zero,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const CupertinoPageScaffold(
            child: RecoveryBanner(
              message: 'The local model is not downloaded on this device yet.',
              missingModelArtifactKey: 'test-gguf',
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const CupertinoPageScaffold(
            child: SizedBox(key: Key('settings-stub')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelCatalogEntriesProvider.overrideWithValue(_catalog),
          modelManagementRepositoryProvider.overrideWithValue(models),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    // The fake repository does real file IO, which cannot complete inside
    // the widget test's fake-async zone — give it real-async windows.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Download Test Model (2.6 GB)'), findsOneWidget);

    // The tap starts the simulated download and lands on Settings, where
    // the model card owns progress.
    await tester.tap(find.byKey(const Key('download-active-model')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-stub')), findsOneWidget);
    // The CTA's job is to start the download (completion timing belongs to
    // the fake repository's own tests).
    final status = await tester.runAsync(() => models.load());
    expect(
      status!.statusOf('test-gguf').phase,
      isNot(ArtifactPhase.notDownloaded),
    );
  });

  testWidgets('an ordinary failure shows no download CTA', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoveryBanner(message: 'Something failed.'),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('download-active-model')), findsNothing);
    expect(find.byKey(const Key('retry-generation')), findsOneWidget);
  });
}
