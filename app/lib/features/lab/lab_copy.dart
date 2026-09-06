import 'package:intl/intl.dart';

import '../../broker/context_window.dart' show contextPromptReserveTokens;
import '../../core/domain/byte_format.dart';
import '../../l10n/generated/app_localizations.dart';
import 'domain/lab_run_settings.dart';

/// Numbers the bench prints, formatted once so every surface agrees:
/// precise and unrounded, in the reader's locale, and never a unit without a
/// measurement behind it.
abstract final class LabFormat {
  static String _decimal(double value, String locale, int decimals) =>
      NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: decimals,
      ).format(value);

  static String seconds(double value, String locale, {int decimals = 1}) =>
      _decimal(value, locale, decimals);

  static String ttft(double value, String locale) => _decimal(value, locale, 2);

  static String rate(double value, String locale) => _decimal(value, locale, 1);

  static String count(int value, String locale) =>
      NumberFormat.decimalPattern(locale).format(value);

  static String bytes(int value) => gigabytes(value);

  static String milliseconds(double value, String locale) =>
      count(value.round(), locale);

  /// A run's clock: seconds under a minute, minutes and seconds above, with
  /// the units from the catalog like every other figure's.
  static String elapsed(Duration value, AppLocalizations l10n, String locale) {
    if (value.inSeconds < 60) {
      return l10n.labElapsedSeconds(
        seconds(value.inMilliseconds / 1000, locale),
      );
    }
    final minutes = value.inMinutes;
    final rest = value.inSeconds - minutes * 60;
    return l10n.labElapsedMinutes(minutes, rest.toString().padLeft(2, '0'));
  }

  /// Physical memory as the machine is sold: binary, whole gigabytes.
  static String memoryGigabytes(int value) =>
      (value / (1 << 30)).toStringAsFixed(0);
}

/// Words a settings problem for the sheet.
String labSettingsProblemMessage(
  AppLocalizations l10n,
  LabSettingsProblem problem,
) => switch (problem) {
  LabSettingsProblem.benchLocked => l10n.labProblemLocked,
  LabSettingsProblem.contextBelowFloor => l10n.labProblemContextFloor(
    labContextFloor,
  ),
  LabSettingsProblem.contextAboveCeiling => l10n.labProblemContextCeiling,
  LabSettingsProblem.maxTokensBelowOne => l10n.labProblemMaxTokensFloor,
  LabSettingsProblem.maxTokensAboveBudget => l10n.labProblemMaxTokensBudget(
    contextPromptReserveTokens,
  ),
  LabSettingsProblem.temperatureOutOfRange => l10n.labProblemTemperature,
  LabSettingsProblem.topPOutOfRange => l10n.labProblemTopP,
  LabSettingsProblem.topKNegative => l10n.labProblemTopK,
  LabSettingsProblem.seedNegative => l10n.labProblemSeed,
};
