import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:golem_flutter/app/app.dart';
import 'package:golem_flutter/app/launch_composition.dart';
import 'package:golem_flutter/core/app_identity.dart';
import 'package:golem_flutter/core/providers/app_providers.dart';
import 'package:golem_flutter/features/chat/widgets/attach_sheet.dart';
import 'package:golem_flutter/features/settings/settings_screen.dart';

import 'support/harness.dart';

Iterable<String> _routePaths(GoRouter router) sync* {
  Iterable<String> walk(List<RouteBase> routes) sync* {
    for (final route in routes) {
      if (route is GoRoute) yield route.path;
      yield* walk(route.routes);
    }
  }

  yield* walk(router.configuration.routes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production and legacy route tables omit benchmark', () {
    for (final identity in [AppIdentity.production, AppIdentity.flutter]) {
      final router = createAppRouter(
        picker: const AttachmentPicker(),
        identity: identity,
      );
      addTearDown(router.dispose);
      expect(_routePaths(router), isNot(contains('/benchmark')));
    }
  });

  test('qa and dev route tables retain benchmark', () {
    for (final identity in [AppIdentity.qa, AppIdentity.dev]) {
      final router = createAppRouter(
        picker: const AttachmentPicker(),
        identity: identity,
      );
      addTearDown(router.dispose);
      expect(_routePaths(router), contains('/benchmark'));
    }
  });

  test('production composition can leave benchmark unwired', () {
    final dependencies = launchDependenciesWith(includeBenchmark: false);
    final container = ProviderContainer(
      overrides: launchOverrides(dependencies),
    );
    addTearDown(container.dispose);

    expect(
      () => container.read(benchmarkRepositoryProvider),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('Override benchmarkRepositoryProvider at startup'),
        ),
      ),
    );
  });

  testWidgets('production settings hide the benchmark affordance', (
    tester,
  ) async {
    await pumpWithRepositories(
      tester,
      child: const SettingsScreen(identity: AppIdentity.production),
    );
    expect(find.byKey(const Key('open-benchmark')), findsNothing);
  });

  testWidgets('qa and dev settings retain the benchmark affordance', (
    tester,
  ) async {
    for (final identity in [AppIdentity.qa, AppIdentity.dev]) {
      await pumpWithRepositories(
        tester,
        child: SettingsScreen(identity: identity),
      );
      expect(find.byKey(const Key('open-benchmark')), findsOneWidget);
    }
  });
}
