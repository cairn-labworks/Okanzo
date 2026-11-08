import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../domain/model/app_theme.dart';
import 'app_style.dart';
import 'colors.dart';

/// Semantic colors that are not part of the standard Material scheme.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({required this.positive, required this.negative});

  static const FinanceColors light = FinanceColors(
    positive: positiveGreen,
    negative: negativeRed,
  );

  static const FinanceColors dark = FinanceColors(
    positive: positiveGreenDark,
    negative: negativeRedDark,
  );

  final Color positive;
  final Color negative;

  static FinanceColors of(BuildContext context) =>
      Theme.of(context).extension<FinanceColors>() ?? light;

  @override
  FinanceColors copyWith({Color? positive, Color? negative}) => FinanceColors(
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
  );

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    return FinanceColors(
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
    );
  }
}

// Material 3 type scale. Uses the platform default font family so the app reads
// as a native Material app without shipping custom fonts.
const TextTheme appTypography = TextTheme(
  displayLarge: TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 57,
    height: 64 / 57,
    letterSpacing: -0.25,
  ),
  displayMedium: TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 45,
    height: 52 / 45,
  ),
  displaySmall: TextStyle(
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    fontWeight: FontWeight.w500,
    fontSize: 38,
    height: 1.2,
    letterSpacing: -1.7,
  ),
  headlineLarge: TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 31,
    height: 1.2,
    letterSpacing: -1,
  ),
  headlineMedium: TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 28,
    height: 36 / 28,
    letterSpacing: -0.8,
  ),
  headlineSmall: TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 24,
    height: 32 / 24,
    letterSpacing: -0.6,
  ),
  titleLarge: TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 22,
    height: 28 / 22,
    letterSpacing: -0.4,
  ),
  titleMedium: TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 24 / 16,
    letterSpacing: 0.15,
  ),
  titleSmall: TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0.1,
  ),
  bodyLarge: TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 24 / 16,
    letterSpacing: 0,
  ),
  bodyMedium: TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0,
  ),
  bodySmall: TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0,
  ),
  labelLarge: TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0.1,
  ),
  labelMedium: TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0.5,
  ),
  labelSmall: TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 11,
    height: 16 / 11,
    letterSpacing: 0.5,
  ),
);

// Shared geometry for quiet inset surfaces and compact controls.
const double shapeExtraSmall = 4;
const double shapeSmall = 8;
const double shapeMedium = 20;
const double shapeLarge = 20;
const double shapeExtraLarge = 28;

/// Builds the app theme for the selected [appTheme]. [AppTheme.classic] adapts
/// to [brightness] and an optional platform [dynamicScheme] (Material You),
/// while [AppTheme.midnight] keeps the fixed deep-green palette.
ThemeData buildTheme({
  required Brightness brightness,
  ColorScheme? dynamicScheme,
  AppTheme appTheme = AppTheme.classic,
}) {
  final bool midnight = appTheme == AppTheme.midnight;
  final bool dark = midnight || brightness == Brightness.dark;
  final ColorScheme scheme = midnight
      ? midnightColors
      : (dynamicScheme ?? (dark ? darkColors : lightColors));
  final AppStyle appStyle = midnight ? AppStyle.midnight : AppStyle.classic;
  final Typography typography = Typography.material2021(
    platform: defaultTargetPlatform,
  );
  final TextTheme textTheme = (dark ? typography.white : typography.black)
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
      .merge(appTypography);
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[
      dark ? FinanceColors.dark : FinanceColors.light,
      appStyle,
    ],
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeMedium),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeExtraLarge),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(shapeExtraLarge),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 72,
      titleTextStyle: textTheme.headlineSmall?.copyWith(
        color: scheme.onSurface,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeMedium),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      elevation: 0,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      useIndicator: true,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 0.5,
      space: 1,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
