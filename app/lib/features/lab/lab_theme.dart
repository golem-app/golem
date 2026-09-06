import 'package:flutter/cupertino.dart';

import '../../core/theme/golem_theme.dart';

/// The desktop density tier (#58): Golem Navy's ramp, proportions and voice,
/// at the sizes a pointer-driven bench of dense numbers reads at. Every
/// changing figure sets tabular figures so columns of numbers hold still.
///
/// Small text sits on [GolemTheme.mutedInk] or the primary ink, never the
/// tertiary ink: the handoff's 3.80:1 metric labels are corrected here, and
/// the guideline sweep enforces 4.5:1 on the bench like everywhere else.
abstract final class LabText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Card and empty-state headline.
  static const headline = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.19,
  );

  /// Transcript body: prompt bubbles and answers.
  static const body = TextStyle(fontSize: 13, height: 1.55);
  static const bodyStrong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Rig chooser labels, sidebar rows.
  static const label = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );
  static const row = TextStyle(fontSize: 12.5, height: 1.3);

  /// Chips and metric lines.
  static const chip = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: _tabular,
  );
  static const detail = TextStyle(
    fontSize: 11.5,
    height: 1.45,
    fontFeatures: _tabular,
  );
  static const detailStrong = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: _tabular,
  );

  /// Section labels: uppercase at the call site, through the locale-aware
  /// helper so Turkish and Devanagari keep their forms.
  static const overline = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.84,
  );
}

/// Desktop spacing: the same 4pt scale, at the tighter steps the bench uses.
abstract final class LabSpace {
  static const double s1 = 4;
  static const double s2 = 6;
  static const double s3 = 8;
  static const double s4 = 10;
  static const double s5 = 12;
  static const double s6 = 14;
  static const double s7 = 16;
  static const double s8 = 20;
  static const double s9 = 24;
  static const double gutter = 16;
}

abstract final class LabSize {
  static const double sidebar = 212;
  static const double rig = 54;
  static const double footer = 38;
  static const double chip = 26;
  static const double control = 28;
  static const double composer = 36;
  static const double trayRow = 44;
  static const double transcriptMaxWidth = 760;

  /// The pointer-tier interactive minimum. A desktop control is not a thumb
  /// target: macOS's own controls sit between 22 and 28 pt, and the guideline
  /// sweep judges the bench at this size under the macOS variant.
  static const double tapMinimum = 24;
}

abstract final class LabRadius {
  static const double chip = 6;
  static const double control = 7;
  static const double card = 10;
  static const double field = 8;
  static const double pill = 12;
}

/// Colours the desktop tier adds to Golem Navy: the sidebar's slightly
/// deeper ground, a pointer hover wash, the focus ring, and ink that keeps
/// 4.5:1 on the accent in both appearances — the handoff's white-on-accent
/// Stop read 2.95:1 in dark.
abstract final class LabColors {
  static const sidebar = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFEAE9E6),
    darkColor: Color(0xFF0B1425),
  );
  static const hover = CupertinoDynamicColor.withBrightness(
    color: Color(0x121763EE),
    darkColor: Color(0x1C5B94FF),
  );
  static const focusRing = CupertinoDynamicColor.withBrightness(
    color: Color(0x661763EE),
    darkColor: Color(0x805B94FF),
  );
  static const textOnAccent = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF0B1425),
  );
}

/// Whether the platform asked for reduced motion. The bench's pulses and
/// blinks become static marks when it did; nothing else here animates.
bool reducedMotionOf(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

Color labResolve(CupertinoDynamicColor color, BuildContext context) =>
    CupertinoDynamicColor.resolve(color, context);

/// One place for the ink levels the bench draws with.
extension LabInk on BuildContext {
  Color get ink => labResolve(GolemTheme.ink, this);
  Color get mutedInk => labResolve(GolemTheme.mutedInk, this);
  Color get accent => labResolve(GolemTheme.accent, this);
  Color get accentIcon => labResolve(GolemTheme.accentIcon, this);
  Color get accentSoft => labResolve(GolemTheme.accentSoft, this);
  Color get surface => labResolve(GolemTheme.surface, this);
  Color get surfaceRaised => labResolve(GolemTheme.surfaceRaised, this);
  Color get field => labResolve(GolemTheme.field, this);
  Color get divider => labResolve(GolemTheme.divider, this);
  Color get borderStrong => labResolve(GolemTheme.borderStrong, this);
}

Color labResolveDestructive(BuildContext context) =>
    labResolve(GolemTheme.destructiveText, context);
