import 'dart:io';

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

  test('the production route table omits benchmark', () {
    final router = createAppRouter(
      picker: const AttachmentPicker(),
      identity: AppIdentity.production,
    );
    addTearDown(router.dispose);
    expect(_routePaths(router), isNot(contains('/benchmark')));
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

  test('the lab route table omits benchmark too', () {
    final router = createAppRouter(
      picker: const AttachmentPicker(),
      identity: AppIdentity.lab,
    );
    addTearDown(router.dispose);
    expect(_routePaths(router), isNot(contains('/benchmark')));
  });

  test('the lab root is reachable only behind the kLabBuild statement', () {
    // The store builds' freedom from the lab rests on constant-condition
    // elimination of one `if`; the release-size proof runs by hand, so this
    // pins the shape that proof depends on: every lab reference in the
    // bootstrap sits inside `if (kLabBuild) {` — never a ternary, an `&&`,
    // or a reference hoisted outside the block.
    final source = File('lib/app/bootstrap.dart').readAsStringSync();
    final gate = 'if (kLabBuild) {';
    final start = source.indexOf(gate);
    expect(start, greaterThan(0), reason: 'the gate is an if statement');
    expect(source.indexOf(gate, start + 1), -1, reason: 'one gate');
    var depth = 0;
    var end = -1;
    for (var i = start + gate.length - 1; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}' && --depth == 0) {
        end = i;
        break;
      }
    }
    expect(end, greaterThan(start));
    final references = RegExp(r'\bLabApp\b|\blabLaunchOverrides\b');
    for (final match in references.allMatches(source)) {
      final line = source.substring(0, match.start).split('\n').length;
      final lineText = source.split('\n')[line - 1];
      if (lineText.trimLeft().startsWith('import ')) continue;
      expect(
        match.start > start && match.start < end,
        isTrue,
        reason: 'line $line references the lab outside the kLabBuild block',
      );
    }
  });

  test('only the phone-internal identities compose the benchmark', () {
    expect(composesSimulatedBenchmark(AppIdentity.qa), isTrue);
    expect(composesSimulatedBenchmark(AppIdentity.dev), isTrue);
    expect(composesSimulatedBenchmark(AppIdentity.production), isFalse);
    expect(composesSimulatedBenchmark(AppIdentity.lab), isFalse);
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
