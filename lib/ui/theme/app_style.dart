import 'package:flutter/material.dart';

import '../../domain/model/app_theme.dart';

/// Extra visual tokens that vary by [AppTheme] but are not part of the standard
/// Material [ColorScheme]: the net-worth hero treatment, the FAB fill and
/// whether category cards use per-type accent colours.
@immutable
class AppStyle extends ThemeExtension<AppStyle> {
  const AppStyle({
    required this.heroGradient,
    required this.heroForeground,
    required this.fabGradient,
    required this.colorfulCategories,
    this.appTheme = AppTheme.classic,
  });

  /// Legacy hero gradient token. Quiet overview uses an unboxed headline.
  final List<Color>? heroGradient;

  /// Foreground paired with the legacy [heroGradient] treatment.
  final Color? heroForeground;

  /// Gradient painted behind the "Add" FAB. Null keeps the default fill.
  final List<Color>? fabGradient;

  /// Whether asset/liability category cards are tinted with a per-type accent.
  final bool colorfulCategories;
  final AppTheme appTheme;

  bool get isEnhanced =>
      appTheme == AppTheme.sculpted || appTheme == AppTheme.liquidGlass;

  bool get isGlass => appTheme == AppTheme.liquidGlass;

  /// The understated Material You look (default).
  static const AppStyle classic = AppStyle(
    heroGradient: null,
    heroForeground: null,
    fabGradient: null,
    colorfulCategories: false,
  );

  /// Deep-green tonal gradients with quiet, per-category accents.
  static const AppStyle midnight = AppStyle(
    appTheme: AppTheme.midnight,
    heroGradient: <Color>[Color(0xFF24382D), Color(0xFF20302A)],
    heroForeground: Color(0xFFC1E1BD),
    fabGradient: <Color>[Color(0xFFC1E1BD), Color(0xFFB2D0AE)],
    colorfulCategories: true,
  );

  static const AppStyle sculpted = AppStyle(
    appTheme: AppTheme.sculpted,
    heroGradient: null,
    heroForeground: null,
    fabGradient: null,
    colorfulCategories: false,
  );

  static const AppStyle liquidGlass = AppStyle(
    appTheme: AppTheme.liquidGlass,
    heroGradient: null,
    heroForeground: null,
    fabGradient: null,
    colorfulCategories: false,
  );

  static AppStyle of(BuildContext context) =>
      Theme.of(context).extension<AppStyle>() ?? AppStyle.classic;

  @override
  AppStyle copyWith({
    List<Color>? heroGradient,
    Color? heroForeground,
    List<Color>? fabGradient,
    bool? colorfulCategories,
    AppTheme? appTheme,
  }) => AppStyle(
    heroGradient: heroGradient ?? this.heroGradient,
    heroForeground: heroForeground ?? this.heroForeground,
    fabGradient: fabGradient ?? this.fabGradient,
    colorfulCategories: colorfulCategories ?? this.colorfulCategories,
    appTheme: appTheme ?? this.appTheme,
  );

  // Swap material treatments at the midpoint while Flutter interpolates colors.
  @override
  AppStyle lerp(ThemeExtension<AppStyle>? other, double t) {
    if (other is! AppStyle) return this;
    return t < 0.5 ? this : other;
  }
}
