import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../core/chrome/golem_button.dart';
import '../../core/chrome/golem_nav_bar.dart';
import '../../core/chrome/golem_tappable.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';
import 'license_registry.dart';

typedef LicenseCatalogLoader = Future<List<OpenSourceLicense>> Function();

/// The SPDX identifier a license body reads as, or null when nothing matches.
/// Pub packages arrive as text through `NOTICES` with no SPDX header, so this
/// matches on the clauses that distinguish the families. It is deliberately
/// *not* used for the bundled declarations, which author their `kind`: this
/// cannot see a dual license or a runtime exception, and guessing one on a
/// legal surface is worse than saying nothing.
String? licenseKind(String text) {
  if (text.contains('Apache License') && text.contains('Version 2.0')) {
    return 'Apache-2.0';
  }
  if (text.contains('Redistribution and use')) {
    return text.contains('Neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  if (text.contains('Permission is hereby granted')) return 'MIT';
  return null;
}

/// The kind for a package Flutter collected, or null unless every document
/// filed under it reads the same way. A name can carry several — the built
/// `NOTICES` files ten under `flutter` alone, mixing BSD-3 with an MIT shader
/// notice and a font license — and picking the first match would put a
/// confident wrong label on a row whose text says otherwise.
String? _collectedKind(List<String> documents) {
  final kinds = documents.map(licenseKind).toSet();
  return kinds.length == 1 ? kinds.single : null;
}

final class OpenSourceLicense {
  OpenSourceLicense({
    required Iterable<String> packages,
    required this.text,
    this.kind,
  }) : packages = List.unmodifiable(packages);

  final List<String> packages;
  final String text;

  /// The SPDX expression shown beside the title, or null when it is not known
  /// well enough to state.
  final String? kind;

  String get title => packages.join(', ');
}

/// The declared manifests for this platform, in reading order. Flutter's
/// registry also carries the engine's own third-party tree and every dev-time
/// package in the graph; neither is software Golem chose, so neither is
/// rendered here (#144).
///
/// [licenses] and [apple] exist so tests drive both platform arms against a
/// stream they own, rather than mutating the process-wide [LicenseRegistry].
Future<List<OpenSourceLicense>> loadRegisteredLicenses({
  Stream<LicenseEntry>? licenses,
  bool? apple,
}) async {
  final onApple = apple ?? runningOnApplePlatform;
  final declared = declaredLicensePackagesFor(apple: onApple);
  final wanted = declared.toSet();
  final authoredKinds = {
    for (final declaration in bundledLicenseDeclarationsFor(apple: onApple))
      declaration.displayName: declaration.kind,
  };

  // Filter before joining: the bundle holds ~1650 entries and this keeps a
  // few dozen, so nothing undeclared is worth reassembling into a string.
  final documentsByPackage = <String, List<String>>{};
  await for (final entry in licenses ?? LicenseRegistry.licenses) {
    if (!entry.packages.any(wanted.contains)) continue;
    final text = entry.paragraphs
        .map((paragraph) => '${'  ' * paragraph.indent}${paragraph.text}')
        .join('\n\n');
    for (final package in entry.packages) {
      if (wanted.contains(package)) {
        documentsByPackage.putIfAbsent(package, () => []).add(text);
      }
    }
  }

  return List.unmodifiable([
    for (final package in declared)
      if (documentsByPackage[package] case final documents?)
        OpenSourceLicense(
          packages: [package],
          text: documents.join('\n\n'),
          kind: authoredKinds[package] ?? _collectedKind(documents),
        ),
  ]);
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
                  if (widget.license.kind case final kind?) ...[
                    const SizedBox(width: 8),
                    // Flexible, not a bare Text: an SPDX expression can be as
                    // long as `Apache-2.0 WITH Swift-exception`, which
                    // overflows the row beside a full-width name. It wraps
                    // rather than ellipsising — half an identifier on a legal
                    // surface is worse than two lines.
                    Flexible(
                      child: Text(
                        kind,
                        textAlign: TextAlign.end,
                        style: GolemText.caption.copyWith(
                          color: CupertinoDynamicColor.resolve(
                            GolemTheme.mutedInk,
                            context,
                          ),
                        ),
                      ),
                    ),
                  ],
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
