import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golem_flutter/core/theme/golem_theme.dart';
import 'package:integration_test/integration_test.dart';

/// Integration-only visual probe for Simplified Chinese script coverage.
///
/// This standalone surface does not enter production routing or localization
/// catalogs. It renders representative strings through the shipping theme at
/// 1.6x and keeps the screen visible long enough for device inspection:
///
/// ```sh
/// flutter test \
///   integration_test/simplified_chinese_typography_probe_test.dart \
///   -d <device> --flavor qa --no-uninstall \
///   --dart-define=GOLEM_SIMPLIFIED_CHINESE_TYPOGRAPHY_PROBE=true \
///   --dart-define=GOLEM_SCRIPT_PROBE_HOLD_SECONDS=20
/// ```
///
/// Inspect both iOS and Android for missing glyphs, Japanese/Korean regional
/// Han forms, wrapping, clipping, semantics, and native font behavior.
const _enabled = bool.fromEnvironment(
  'GOLEM_SIMPLIFIED_CHINESE_TYPOGRAPHY_PROBE',
);
const _holdSeconds = int.fromEnvironment(
  'GOLEM_SCRIPT_PROBE_HOLD_SECONDS',
  defaultValue: 0,
);
const _zhHans = Locale('zh', 'CN');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shipping typography renders the Simplified Chinese probe at 1.6x',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: CupertinoApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [_zhHans],
            localizationsDelegates: const [
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: GolemTheme.theme(Brightness.light),
            home: const _SimplifiedChineseTypographyProbe(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('zh-hans-probe')), findsOneWidget);
      expect(find.text('本地人工智能，隐私优先'), findsOneWidget);
      expect(find.textContaining('Gemma 4 E2B'), findsOneWidget);
      expect(find.textContaining('2.18 GB'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('download-model-semantics')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const Key('download-model-semantics')))
            .label,
        '下载并验证模型',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('new-chat-semantics')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(const Key('new-chat-semantics'))).label,
        '开始新的聊天',
      );
      expect(tester.takeException(), isNull);

      debugPrint(
        'SCRIPT_PROBE platform=$defaultTargetPlatform locale=zh_CN '
        'textScale=1.6 inspect=missing-glyphs,regional-Han-forms,wrapping,'
        'clipping,semantics,native-font',
      );
      if (_holdSeconds > 0) {
        await tester.pump(Duration(seconds: _holdSeconds));
      }
      semantics.dispose();
    },
    skip: !_enabled,
  );
}

class _SimplifiedChineseTypographyProbe extends StatelessWidget {
  const _SimplifiedChineseTypographyProbe();

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(
      middle: Text('简体中文显示检查', locale: _zhHans),
    ),
    child: SafeArea(
      child: ListView(
        key: const Key('zh-hans-probe'),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Semantics(
            header: true,
            child: const Text(
              '本地人工智能，隐私优先',
              locale: _zhHans,
              style: GolemText.display,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '模型在设备上离线运行。首次使用时需要下载并验证文件。'
            '聊天内容不会上传到服务器，您可以随时删除本地模型。',
            locale: _zhHans,
            style: GolemText.body,
          ),
          const SizedBox(height: 20),
          const _ProbeLabel('模型与格式'),
          const Text(
            'Gemma 4 E2B · Qwen 3.5 2B（MLX / GGUF）',
            locale: _zhHans,
            style: GolemText.bodyStrong,
          ),
          const SizedBox(height: 16),
          const _ProbeLabel('数字与技术文本'),
          const Text(
            '2.18 GB · SHA-256 · 391 · 2026年8月13日',
            locale: _zhHans,
            style: GolemText.metrics,
          ),
          const SizedBox(height: 16),
          const _ProbeLabel('地区字形人工检查'),
          const Text(
            '骨、直、令、门、关、复、国、下载、隐私、设备',
            locale: _zhHans,
            style: GolemText.body,
          ),
          const SizedBox(height: 24),
          Semantics(
            key: const Key('download-model-semantics'),
            button: true,
            label: '下载并验证模型',
            excludeSemantics: true,
            child: SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: () {},
                child: const Text(
                  '下载并验证模型',
                  locale: _zhHans,
                  style: GolemText.bodyStrong,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            key: const Key('new-chat-semantics'),
            button: true,
            label: '开始新的聊天',
            excludeSemantics: true,
            child: SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                onPressed: () {},
                child: const Text(
                  '开始新的聊天',
                  locale: _zhHans,
                  style: GolemText.bodyStrong,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '兼容性冒烟检查，不代表完整的中文本地化或语言质量声明。',
            locale: _zhHans,
            style: GolemText.caption,
          ),
        ],
      ),
    ),
  );
}

class _ProbeLabel extends StatelessWidget {
  const _ProbeLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, locale: _zhHans, style: GolemText.footnoteStrong),
  );
}
