import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/chrome/golem_nav_bar.dart';
import '../../core/domain/model_catalog.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/golem_theme.dart';
import '../../core/widgets/section_header.dart';
import '../settings/widgets/settings_rows.dart';

typedef ExternalUriLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

final class ModelSourceAttribution {
  const ModelSourceAttribution({
    required this.repository,
    required this.revision,
  });

  final String repository;
  final String revision;

  Uri get uri => Uri.https('huggingface.co', '/$repository/tree/$revision');
}

final class ModelFamilyAttribution {
  ModelFamilyAttribution({
    required this.title,
    required this.author,
    required this.licenseName,
    required this.licenseUri,
    required this.modelCardUri,
    required Iterable<ModelSourceAttribution> sources,
  }) : sources = List.unmodifiable(sources);

  final String title;
  final String author;
  final String licenseName;
  final Uri licenseUri;
  final Uri modelCardUri;
  final List<ModelSourceAttribution> sources;
}

List<ModelFamilyAttribution> modelAttributionsFor(
  Iterable<ModelCatalogEntry> catalog,
) {
  final byProfile = <String, List<ModelCatalogEntry>>{};
  for (final entry in catalog) {
    if (entry.profileKey == 'gemma4' || entry.profileKey == 'qwen35') {
      byProfile.putIfAbsent(entry.profileKey, () => []).add(entry);
    }
  }

  List<ModelSourceAttribution> sourcesFor(String profile) {
    final sources = <String, ModelSourceAttribution>{};
    void add(String repository, String revision) {
      sources['$repository@$revision'] = ModelSourceAttribution(
        repository: repository,
        revision: revision,
      );
    }

    for (final entry in byProfile[profile] ?? const <ModelCatalogEntry>[]) {
      add(entry.repository, entry.revision);
      for (final file in entry.files) {
        if (file.repository case final repository?) {
          add(repository, file.revision ?? entry.revision);
        }
      }
    }
    final result = sources.values.toList()
      ..sort((a, b) => a.repository.compareTo(b.repository));
    return result;
  }

  return List.unmodifiable([
    ModelFamilyAttribution(
      title: 'Gemma 4 E2B',
      author: 'Google DeepMind',
      licenseName: 'Apache 2.0',
      licenseUri: Uri.parse('https://ai.google.dev/gemma/apache_2'),
      modelCardUri: Uri.parse('https://huggingface.co/google/gemma-4-E2B-it'),
      sources: sourcesFor('gemma4'),
    ),
    ModelFamilyAttribution(
      title: 'Qwen 3.5',
      author: 'Alibaba Cloud · Qwen',
      licenseName: 'Apache 2.0',
      licenseUri: Uri.parse(
        'https://huggingface.co/Qwen/Qwen3.5-2B/blob/'
        '965dcc54bc9c0591873df0e9869c056a54d323d1/LICENSE',
      ),
      modelCardUri: Uri.parse('https://huggingface.co/Qwen/Qwen3.5-4B'),
      sources: sourcesFor('qwen35'),
    ),
  ]);
}

class ModelAttributionScreen extends ConsumerWidget {
  const ModelAttributionScreen({this.openUri = _launchExternally, super.key});

  final ExternalUriLauncher openUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final families = modelAttributionsFor(
      ref.watch(modelCatalogEntriesProvider),
    );
    return CupertinoPageScaffold(
      key: const Key('model-attribution-screen'),
      navigationBar: GolemNavBar(
        title: 'Model attribution',
        previousPageTitle: 'Settings',
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const Key('model-attribution-list'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Text(
              'Golem does not include model weights. It downloads the exact '
              'artifacts listed here only after you approve a download.',
              style: GolemText.footnote.copyWith(
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.mutedInk,
                  context,
                ),
              ),
            ),
            const SizedBox(height: 24),
            for (final family in families) ...[
              SectionHeader(family.title, subtitle: family.author),
              const SizedBox(height: 8),
              SettingsCard(
                children: [
                  SettingsNavRow(
                    label: 'Official model card',
                    onTap: () => unawaited(openUri(family.modelCardUri)),
                  ),
                  SettingsNavRow(
                    label: 'License',
                    value: family.licenseName,
                    onTap: () => unawaited(openUri(family.licenseUri)),
                  ),
                  for (final source in family.sources)
                    SettingsNavRow(
                      key: Key(
                        'model-source-${source.repository}-${source.revision}',
                      ),
                      label: source.repository,
                      value: source.revision.substring(0, 12),
                      onTap: () => unawaited(openUri(source.uri)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            Text(
              'Repositories added by hand are governed by their own upstream '
              'terms. Golem does not certify or redistribute them.',
              style: GolemText.footnote.copyWith(
                color: CupertinoDynamicColor.resolve(
                  GolemTheme.mutedInk,
                  context,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
