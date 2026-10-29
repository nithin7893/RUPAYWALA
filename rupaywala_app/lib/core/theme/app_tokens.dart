import 'package:flutter/material.dart';

/// The Rupaywala design tokens.
///
/// The brand palette is unchanged — deep navy with an emerald accent — but it
/// is now expressed as a single consistent scale instead of the loosely
/// related constants that were spread across widgets. Everything visual in the
/// app resolves through this file.
class AppColors {
  AppColors._();

  // --- Brand ---------------------------------------------------------
  static const Color primary = Color(0xFF123B7A);
  static const Color primaryDark = Color(0xFF0B2751);
  static const Color primarySoft = Color(0xFFE8EFFA);
  static const Color secondary = Color(0xFF10B981);
  static const Color secondaryDark = Color(0xFF059669);
  static const Color secondarySoft = Color(0xFFE7F7F1);

  /// Accent that stays legible on the dark snackbar background.
  static const Color onDarkAccent = Color(0xFF6EE7B7);

  // --- Neutrals ------------------------------------------------------
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE3E8EF);
  static const Color divider = Color(0xFFEDF1F6);

  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF5A6779);
  static const Color textHint = Color(0xFF98A2B3);
  static const Color textOnPrimary = Colors.white;

  // --- Semantic ------------------------------------------------------
  static const Color success = Color(0xFF12805C);
  static const Color successSoft = Color(0xFFE6F6F0);
  static const Color warning = Color(0xFFB54708);
  static const Color warningSoft = Color(0xFFFDF3E7);
  static const Color error = Color(0xFFB42318);
  static const Color errorSoft = Color(0xFFFDECEA);
  static const Color info = Color(0xFF175CD3);
  static const Color infoSoft = Color(0xFFEBF2FD);
  static const Color neutralSoft = Color(0xFFF1F4F8);

  static const Color disabled = Color(0xFFE4E7EC);

  static const Color gradientStart = Color(0xFF123B7A);
  static const Color gradientEnd = Color(0xFF10B981);
}

/// Spacing scale. Everything in the UI is a multiple of 4 so rhythm is
/// automatic.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const EdgeInsets screen = EdgeInsets.fromLTRB(16, 8, 16, 24);
  static const EdgeInsets card = EdgeInsets.all(16);
  static const EdgeInsets field =
      EdgeInsets.symmetric(horizontal: 16, vertical: 14);
}

class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

class AppElevation {
  AppElevation._();

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F101828), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x14101828), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

/// Responsive breakpoints. The layout is mobile first and widens for tablets.
class AppBreakpoints {
  AppBreakpoints._();

  static const double tablet = 640;
  static const double desktop = 1024;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tablet;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;

  /// Caps content width so text lines stay readable on large screens.
  static const double maxContentWidth = 720;

  static double contentWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width > maxContentWidth ? maxContentWidth : width;
  }
}

class AppIcon {
  AppIcon._();

  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
}

/// The three-button vocabulary described in the design brief.
enum AppButtonVariant { primary, secondary, ghost, success, danger }

enum AppButtonSize { small, medium, large }

/// Minimum comfortable touch target.
const double kMinTouchTarget = 48;

/// Duration used for the small, purposeful transitions in the app.
const Duration kFastAnimation = Duration(milliseconds: 160);
const Duration kMediumAnimation = Duration(milliseconds: 260);

class AppDimensions {
  AppDimensions._();

  static const EdgeInsets pagePadding = AppSpacing.screen;
  static const double spacingXs = AppSpacing.xs;
  static const double spacingSm = AppSpacing.sm;
  static const double spacingMd = AppSpacing.md;
  static const double spacingLg = AppSpacing.lg;
  static const double spacingXl = AppSpacing.xl;
  static const double spacingXxl = AppSpacing.xxl;
  static const double radiusSm = AppRadius.sm;
  static const double radiusMd = AppRadius.md;
  static const double radiusLg = AppRadius.lg;
  static const double radiusFull = AppRadius.pill;
  static const double iconSizeSm = AppIcon.sm;
  static const double iconSizeMd = AppIcon.md;
  static const double iconSizeLg = AppIcon.lg;
}
