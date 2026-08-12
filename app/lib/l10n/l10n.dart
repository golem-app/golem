import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_en.dart';

export 'generated/app_localizations.dart';

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
