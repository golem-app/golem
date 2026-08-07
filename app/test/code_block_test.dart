import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:golem_flutter/features/chat/chat_screen.dart';
import 'package:golem_flutter/features/chat/widgets/markdown/code_block.dart';

import 'support/harness.dart';

/// The rendered header label — the uppercase language, or `CODE` when the
/// fence carried no tag.
String headerLabel(WidgetTester tester) {
  final card = find.byKey(const Key('code-block'));
  final text = tester.widget<Text>(
    find.descendant(of: card, matching: find.byType(Text)).first,
  );
  return text.data!;
}

/// True when the body carries token colors *beneath* its base ink span.
/// A plain body is one uncolored run under that base; a colorized one
/// adds keyword, callable, and string hues. The walk starts below the
/// card's own root span, skipping both it and the wrapper `Text.rich`
/// adds — each of which always carries a color of its own.
bool isColorized(WidgetTester tester) {
  final rich = tester.widget<RichText>(
    find
        .descendant(
          of: find.descendant(
            of: find.byKey(const Key('code-block')),
            matching: find.byType(SingleChildScrollView),
          ),
          matching: find.byType(RichText),
        )
        .first,
  );
  var colored = false;
  void walk(InlineSpan span) {
    if (span.style?.color != null) colored = true;
    if (span is TextSpan) span.children?.forEach(walk);
  }

  // rich.text is Text.rich's wrapper; its single child is the card's base
  // ink span, and the token spans hang below that.
  final wrapper = rich.text as TextSpan;
  final base = wrapper.children!.single as TextSpan;
  base.children?.forEach(walk);
  return colored;
}

Future<void> pumpCard(
  WidgetTester tester, {
  required String code,
  String? language,
  Brightness brightness = Brightness.light,
}) async {
  setViewport(tester);
  await tester.pumpWidget(
    wrapApp(
      brightness: brightness,
      child: Center(
        child: MarkdownCodeBlock(code: code, language: language),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const python =
      'import csv\n\ndef rows(path):\n'
      '    with open(path, newline="") as file:\n'
      '        yield from csv.reader(file)';

  testWidgets('a tagged fence keeps its language and colorizes', (
    tester,
  ) async {
    await pumpCard(tester, code: python, language: 'python');
    expect(headerLabel(tester), 'PYTHON');
    expect(isColorized(tester), isTrue);
  });

  testWidgets('an untagged fence stays neutral and plain', (tester) async {
    // Deliberate: `highlight`'s relevance cannot tell code from prose or
    // log output, so nothing is guessed here. See the note on
    // `_untaggedLanguageLabel`.
    for (final body in const [
      'SELECT id, name FROM users WHERE active = true ORDER BY id;',
      '2026-08-07 10:02:11 INFO starting server on port 8080',
      'To install it, download the archive and add it to your PATH.',
    ]) {
      await pumpCard(tester, code: body);
      expect(headerLabel(tester), 'CODE');
      expect(isColorized(tester), isFalse);
    }
  });

  testWidgets('an unrecognized tag renders plain but keeps its label', (
    tester,
  ) async {
    // `highlight` resolves an unknown tag to its plaintext grammar rather
    // than failing, so the body renders uncolored with the label intact.
    await pumpCard(tester, code: 'nothing here', language: 'notalanguage');
    expect(headerLabel(tester), 'NOTALANGUAGE');
    expect(isColorized(tester), isFalse);
  });

  testWidgets('the gutter belongs to the viewport, not the scrolled body', (
    tester,
  ) async {
    await pumpCard(tester, code: 'x = "${'y' * 400}"', language: 'python');
    final card = find.byKey(const Key('code-block'));
    final scroller = find.descendant(
      of: card,
      matching: find.byType(SingleChildScrollView),
    );
    final body = find.descendant(of: scroller, matching: find.byType(RichText));
    final cardLeft = tester.getTopLeft(card).dx;
    final viewportLeft = tester.getTopLeft(scroller).dx;

    // The discriminator: with the inset back inside the scrollable, the
    // viewport would begin at the card's edge and the 14pt gutter would be
    // scrollable content. It has to be carved out of the viewport instead.
    expect(
      viewportLeft - cardLeft,
      greaterThanOrEqualTo(14),
      reason: 'the horizontal inset must sit outside the scrollable',
    );
    expect(tester.getTopLeft(body).dx, viewportLeft);

    await tester.drag(scroller, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<SingleChildScrollView>(scroller)
        .controller!;
    expect(
      controller.offset,
      greaterThan(0),
      reason: 'the body must actually have scrolled',
    );
    // The body slid left, under the gutter and out of the clip — while the
    // gutter itself stayed put, which is the whole point.
    expect(tester.getTopLeft(body).dx, lessThan(viewportLeft));
    expect(tester.getTopLeft(scroller).dx - cardLeft, viewportLeft - cardLeft);
  });

  testWidgets('the header band holds the iOS minimum height on its own', (
    tester,
  ) async {
    await pumpCard(tester, code: python, language: 'python');
    // The band by key, not `byType(ConstrainedBox).first` — that would
    // silently retarget the card itself the moment anything above the band
    // gains constraints.
    expect(tester.getSize(find.byKey(const Key('code-header'))).height, 44);
    expect(tester.getSize(find.byKey(const Key('code-copy'))).height, 44);
  });

  testWidgets('an untagged fence resolves through the real transcript', (
    tester,
  ) async {
    // End to end rather than widget-in-isolation: proves the markdown
    // parser hands the card a null language for a bare fence.
    await pumpWithRepositories(
      tester,
      history: bareFenceHistory(),
      child: const ChatScreen(),
    );
    expect(find.text('CODE'), findsOneWidget);
  });

  testWidgets('a tag highlight does not register still colorizes', (
    tester,
  ) async {
    // `tsx` is not a registered grammar and would otherwise print a TSX
    // header over an uncolored body.
    await pumpCard(
      tester,
      code: 'const x: number = 1;\nexport default x;',
      language: 'tsx',
    );
    expect(headerLabel(tester), 'TSX');
    expect(isColorized(tester), isTrue);
  });

  testWidgets('the card repaints for the appearance', (tester) async {
    Color surfaceOf(WidgetTester t) =>
        (t.widget<Container>(find.byKey(const Key('code-block'))).decoration!
                as BoxDecoration)
            .color!;

    await pumpCard(tester, code: python, language: 'python');
    final light = surfaceOf(tester);
    await pumpCard(
      tester,
      code: python,
      language: 'python',
      brightness: Brightness.dark,
    );
    expect(surfaceOf(tester), isNot(light));
  });

  testWidgets('a recycled card rewinds its scroll, a streamed one does not', (
    tester,
  ) async {
    Future<void> pump(String code) =>
        pumpCard(tester, code: code, language: 'python');
    const long = 'x = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"';
    await pump(long);
    final scroller = find.byType(SingleChildScrollView);
    await tester.drag(scroller, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<SingleChildScrollView>(scroller)
        .controller!;
    expect(controller.offset, greaterThan(0));

    // A streamed append keeps the reader where they were.
    await pump('$long + "bbbb"');
    expect(controller.offset, greaterThan(0));

    // A different snippet in a recycled element starts at the beginning.
    await pump('y = "cccccccccccccccccccccccccccccccccccccccccccccc"');
    expect(controller.offset, 0);
  });
  // `textContrastGuideline` reduces each text node to its two modal
  // colors, so the minority syntax hues are never the ones it measures.
  // These assert the token values directly.
  group('code palette contrast', () {
    double luminance(Color c) {
      double channel(double v) {
        final s = v / 255;
        return s <= 0.03928
            ? s / 12.92
            : pow((s + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * channel(c.r * 255) +
          0.7152 * channel(c.g * 255) +
          0.0722 * channel(c.b * 255);
    }

    double ratio(Color fg, Color bg) {
      final a = luminance(fg);
      final b = luminance(bg);
      return (max(a, b) + 0.05) / (min(a, b) + 0.05);
    }

    for (final brightness in Brightness.values) {
      test('every ink clears 4.5:1 in ${brightness.name}', () {
        Color pick(CupertinoDynamicColor c) =>
            brightness == Brightness.dark ? c.darkColor : c.color;
        final surface = pick(GolemTheme.codeSurface);
        for (final entry in <String, CupertinoDynamicColor>{
          'codeInk': GolemTheme.codeInk,
          'codeKeyword': GolemTheme.codeKeyword,
          'codeCallable': GolemTheme.codeCallable,
          'codeString': GolemTheme.codeString,
          'codeComment': GolemTheme.codeComment,
        }.entries) {
          expect(
            ratio(pick(entry.value), surface),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} on the code surface',
          );
        }
        // The header label sits on the band, not the card.
        final band = Color.alphaBlend(pick(GolemTheme.codeHeader), surface);
        expect(
          ratio(pick(GolemTheme.codeHeaderInk), band),
          greaterThanOrEqualTo(4.5),
          reason: 'codeHeaderInk on the header band',
        );
        final chip = Color.alphaBlend(pick(GolemTheme.codeChip), band);
        expect(
          ratio(pick(GolemTheme.codeChipInk), chip),
          greaterThanOrEqualTo(4.5),
          reason: 'codeChipInk on the Copy chip',
        );
      });
    }
  });
}
