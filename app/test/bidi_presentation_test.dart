import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/broker/model_catalog.dart';
import 'package:golem_flutter/core/chrome/golem_nav_bar.dart';
import 'package:golem_flutter/features/chat/widgets/markdown/golem_markdown.dart';
import 'package:golem_flutter/features/onboarding/model_download_consent.dart';

import 'support/harness.dart';

void main() {
  testWidgets('search text direction changes without moving RTL controls', (
    tester,
  ) async {
    await pumpSearchScreen(tester, locale: const Locale('ar'));

    final fieldFinder = find.byKey(const Key('search-field'));
    final prefixFinder = find.byKey(const Key('search-prefix'));
    final ambientDirection = Directionality.of(tester.element(fieldFinder));
    final initialPrefixX = tester.getCenter(prefixFinder).dx;

    expect(ambientDirection, TextDirection.rtl);
    expect(
      tester.widget<CupertinoTextField>(fieldFinder).textDirection,
      TextDirection.rtl,
    );

    await tester.enterText(fieldFinder, 'بحث');
    await tester.pump();
    expect(
      tester.widget<CupertinoTextField>(fieldFinder).textDirection,
      TextDirection.rtl,
    );
    expect(tester.getCenter(prefixFinder).dx, initialPrefixX);

    await tester.enterText(fieldFinder, 'config.json');
    await tester.pump();
    expect(
      tester.widget<CupertinoTextField>(fieldFinder).textDirection,
      TextDirection.ltr,
    );
    expect(Directionality.of(tester.element(fieldFinder)), TextDirection.rtl);
    expect(tester.getCenter(prefixFinder).dx, initialPrefixX);
  });

  testWidgets('mixed Markdown list resolves each item independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        locale: const Locale('ar'),
        child: const CupertinoPageScaffold(
          child: GolemMarkdown(text: '- عنصر عربي\n- config.json stays LTR'),
        ),
      ),
    );

    Finder richText(String value) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan?.toPlainText() == value,
    );

    expect(
      Directionality.of(tester.element(richText('عنصر عربي'))),
      TextDirection.rtl,
    );
    expect(
      Directionality.of(tester.element(richText('config.json stays LTR'))),
      TextDirection.ltr,
    );
  });

  testWidgets('navigation title follows content while chrome remains RTL', (
    tester,
  ) async {
    const title = 'Project (API)';
    await tester.pumpWidget(
      wrapApp(
        locale: const Locale('ar'),
        child: CupertinoPageScaffold(
          navigationBar: GolemNavBar(title: title),
          child: const SizedBox.shrink(),
        ),
      ),
    );

    final titleFinder = find.text(title);
    expect(Directionality.of(tester.element(titleFinder)), TextDirection.rtl);
    expect(tester.widget<Text>(titleFinder).textDirection, TextDirection.ltr);
  });

  testWidgets('Arabic download consent isolates model name and size', (
    tester,
  ) async {
    final entry = modelCatalog.firstWhere(
      (candidate) => candidate.key == 'qwen35-2b-gguf',
    );
    await tester.pumpWidget(
      wrapApp(
        locale: const Locale('ar'),
        child: Builder(
          builder: (context) => CupertinoButton(
            key: const Key('show-consent'),
            onPressed: () {
              confirmModelDownload(
                context: context,
                entry: entry,
                simulated: false,
              );
            },
            child: const Text('show'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('show-consent')));
    await tester.pumpAndSettle();

    final message = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('model-download-consent')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.data?.contains('Hugging Face') == true,
            ),
          ),
        )
        .data!;
    expect(message, contains('\u2066${entry.displayName}\u2069'));
    expect(
      message,
      contains('\u2066${formatModelBytes(entry.totalBytes)}\u2069'),
    );
  });
}
