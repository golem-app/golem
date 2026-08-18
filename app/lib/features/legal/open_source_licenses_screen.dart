import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../core/chrome/golem_button.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_tappable.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';

typedef LicenseCatalogLoader = Future<List<OpenSourceLicense>> Function();

final class OpenSourceLicense {
  OpenSourceLicense({required Iterable<String> packages, required this.text})
    : packages = List.unmodifiable(packages);

  final List<String> packages;
  final String text;

  String get title => packages.join(', ');
}

Future<List<OpenSourceLicense>> loadRegisteredLicenses() async {
  final documentsByPackage = <String, List<String>>{};
  await for (final entry in LicenseRegistry.licenses) {
    final text = entry.paragraphs
        .map((paragraph) => '${'  ' * paragraph.indent}${paragraph.text}')
        .join('\n\n');
    for (final package in entry.packages) {
      documentsByPackage.putIfAbsent(package, () => []).add(text);
    }
  }
  final licenses = [
    for (final entry in documentsByPackage.entries)
      OpenSourceLicense(packages: [entry.key], text: entry.value.join('\n\n')),
  ];
  licenses.sort(
    (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );
  return List.unmodifiable(licenses);
}

class OpenSourceLicensesScreen extends StatefulWidget {
  const OpenSourceLicensesScreen({
    this.loadLicenses = loadRegisteredLicenses,
    super.key,
  });

  final LicenseCatalogLoader loadLicenses;

  @override
  State<OpenSourceLicensesScreen> createState() =>
      _OpenSourceLicensesScreenState();
}

class _OpenSourceLicensesScreenState extends State<OpenSourceLicensesScreen> {
  late Future<List<OpenSourceLicense>> _licenses = widget.loadLicenses();

  void _retry() {
    final licenses = widget.loadLicenses();
    setState(() {
      _licenses = licenses;
    });
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    key: const Key('open-source-licenses-screen'),
    navigationBar: GolemNavBar(
      title: context.l10n.settingsOpenSourceLicenses,
      previousPageTitle: context.l10n.settingsTitle,
    ),
    child: SafeArea(
      bottom: false,
      child: FutureBuilder<List<OpenSourceLicense>>(
        future: _licenses,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CupertinoActivityIndicator(key: Key('licenses-loading')),
            );
          }
          if (snapshot.hasError) return _LicenseFailure(onRetry: _retry);
          final licenses = snapshot.data ?? const <OpenSourceLicense>[];
          return ListView(
            key: const Key('licenses-list'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Text(
                context.l10n.licensesIntroduction,
                style: GolemText.footnote.copyWith(
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SectionHeader(context.l10n.licenseEntries(licenses.length)),
              const SizedBox(height: 8),
              for (final license in licenses) ...[
                _LicenseDisclosure(license: license),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class _LicenseFailure extends StatelessWidget {
  const _LicenseFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.licensesLoadFailed,
            key: const Key('licenses-error'),
            textAlign: TextAlign.center,
            style: GolemText.cardTitle,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.licensesRetryDetail,
            textAlign: TextAlign.center,
            style: GolemText.footnote.copyWith(
              color: CupertinoDynamicColor.resolve(
                GolemTheme.mutedInk,
                context,
              ),
            ),
          ),
          const SizedBox(height: 16),
          GolemButton.filled(
            key: const Key('licenses-retry'),
            label: context.l10n.tryAgain,
            onPressed: onRetry,
            expand: false,
          ),
        ],
      ),
    ),
  );
}

class _LicenseDisclosure extends StatefulWidget {
  const _LicenseDisclosure({required this.license});

  final OpenSourceLicense license;

  @override
  State<_LicenseDisclosure> createState() => _LicenseDisclosureState();
}

class _LicenseDisclosureState extends State<_LicenseDisclosure> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.license.title;
    return Container(
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(GolemTheme.surface, context),
        borderRadius: BorderRadius.circular(GolemRadius.card),
        border: Border.all(
          color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: _expanded
                ? context.l10n.hideLicenseFor(title)
                : context.l10n.showLicenseFor(title),
            child: GolemTappable(
              key: Key('license-${title.toLowerCase()}'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GolemText.bodyStrong.copyWith(
                        color: CupertinoDynamicColor.resolve(
                          GolemTheme.ink,
                          context,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 18,
                    color: CupertinoDynamicColor.resolve(
                      GolemTheme.mutedInk,
                      context,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Container(
              height: 1,
              color: CupertinoDynamicColor.resolve(GolemTheme.divider, context),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.license.text,
                key: Key('license-text-${title.toLowerCase()}'),
                style: GolemText.caption.copyWith(
                  fontFamily: 'Menlo',
                  fontFamilyFallback: const ['Courier', 'monospace'],
                  color: CupertinoDynamicColor.resolve(
                    GolemTheme.mutedInk,
                    context,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
