import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_en.dart';

export 'generated/app_localizations.dart';

/// Uppercases presentation-only labels without losing Turkish dotted and
/// dotless I. Domain values, user text, model output, and diagnostics never
/// pass through this transform.
String localizedUppercase(String value, Locale locale) {
  if (locale.languageCode != 'tr') return value.toUpperCase();
  return value.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
}

/// Devanagari and Hangul should not inherit tracking tuned for uppercase
/// Latin labels. Apply this at the shared style boundary for every localized
/// overline and badge, including reusable badges outside section headers.
TextStyle localizedLabelStyle(TextStyle style, Locale locale) =>
    _usesUntrackedLabelStyle(locale) ? style.copyWith(letterSpacing: 0) : style;

bool _usesUntrackedLabelStyle(Locale locale) =>
    locale.languageCode == 'hi' || locale.languageCode == 'ko';

extension AppLocalizationsContext on BuildContext {
  /// English remains a safe fallback for narrow component hosts that are not
  /// mounted below the product app (for example isolated package consumers).
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();
}

/// Resolves the platform's ordered locale list with Flutter's standard
/// language/script/country matching and English as the final fallback.
Locale resolveAppLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  final supported = supportedLocales.toList(growable: false);
  final supportedLanguageCodes = supported
      .map((locale) => locale.languageCode)
      .toSet();
  final supportedPreferences = (preferredLocales ?? const <Locale>[])
      .where((locale) => supportedLanguageCodes.contains(locale.languageCode))
      .toList(growable: false);
  return basicLocaleListResolution(supportedPreferences, supported);
}
