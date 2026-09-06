import 'package:intl/intl.dart';

import '../../core/domain/byte_format.dart';
import '../../core/domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'domain/lab_run_settings.dart';

/// Numbers the bench prints, formatted once so every surface agrees:
/// precise and unrounded, in the reader's locale, and never a unit without a
/// measurement behind it.
abstract final class LabFormat {
  static String seconds(double value, {int decimals = 1}) =>
      value.toStringAsFixed(decimals);

  static String ttft(double value) => value.toStringAsFixed(2);

  static String rate(double value) => value.toStringAsFixed(1);

  static String count(int value, String locale) =>
      NumberFormat.decimalPattern(locale).format(value);

  static String bytes(int value) => gigabytes(value);

  static String milliseconds(double value) => value.round().toString();

  /// A run's clock: seconds under a minute, minutes and seconds above.
  static String elapsed(Duration value) {
    if (value.inSeconds < 60) return seconds(value.inMilliseconds / 1000);
    final minutes = value.inMinutes;
    final rest = value.inSeconds - minutes * 60;
    return '$minutes m ${rest.toString().padLeft(2, '0')} s';
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
  LabSettingsProblem.contextBelowFloor => l10n.labProblemContextFloor(
    labContextFloor,
  ),
  LabSettingsProblem.contextAboveCeiling => l10n.labProblemContextCeiling,
  LabSettingsProblem.maxTokensBelowOne => l10n.labProblemMaxTokensFloor,
  LabSettingsProblem.maxTokensAboveBudget => l10n.labProblemMaxTokensBudget(
    labPromptReserveTokens,
  ),
  LabSettingsProblem.temperatureOutOfRange => l10n.labProblemTemperature,
  LabSettingsProblem.topPOutOfRange => l10n.labProblemTopP,
  LabSettingsProblem.topKNegative => l10n.labProblemTopK,
  LabSettingsProblem.seedNegative => l10n.labProblemSeed,
};

/// Words an artifact's phase for the Rig chip.
String labArtifactPhaseLabel(AppLocalizations l10n, ArtifactPhase phase) =>
    switch (phase) {
      ArtifactPhase.installed => l10n.labArtifactVerified,
      ArtifactPhase.notDownloaded => l10n.labArtifactMissing,
      ArtifactPhase.downloading => l10n.labArtifactDownloading,
      ArtifactPhase.verifying => l10n.labArtifactVerifying,
      ArtifactPhase.paused => l10n.paused,
      ArtifactPhase.failed => l10n.labArtifactFailed,
    };
