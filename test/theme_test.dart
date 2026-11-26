import 'package:flutter/material.dart';
import 'package:okanzo/domain/model/app_theme.dart';
import 'package:okanzo/ui/theme/app_style.dart';
import 'package:okanzo/ui/theme/colors.dart';
import 'package:okanzo/ui/theme/theme.dart';
import 'package:test/test.dart';

void main() {
  group('AppTheme', () {
    test('round-trips through its storage name', () {
      for (final AppTheme theme in AppTheme.values) {
        expect(AppTheme.fromName(theme.storageName), theme);
      }
    });

    test('unknown or missing names fall back to Classic', () {
      expect(AppTheme.fromName('NOPE'), AppTheme.classic);
      expect(AppTheme.fromName(null), AppTheme.classic);
    });
  });

  group('AppStyle', () {
    test('classic is a flat, neutral look', () {
      expect(AppStyle.classic.heroGradient, isNull);
      expect(AppStyle.classic.fabGradient, isNull);
      expect(AppStyle.classic.colorfulCategories, isFalse);
    });

    test('midnight keeps tonal depth and distinct category accents', () {
      expect(AppStyle.midnight.heroGradient, isNotNull);
      expect(AppStyle.midnight.heroGradient!.length, greaterThanOrEqualTo(2));
      expect(AppStyle.midnight.fabGradient, isNotNull);
      expect(AppStyle.midnight.colorfulCategories, isTrue);
    });

    test('lerp snaps between the two styles at the midpoint', () {
      expect(AppStyle.classic.lerp(AppStyle.midnight, 0.2), AppStyle.classic);
      expect(AppStyle.classic.lerp(AppStyle.midnight, 0.8), AppStyle.midnight);
    });
  });

  group('categoryColorAt', () {
    test('cycles through the palette', () {
      expect(categoryColorAt(0), categoryPalette.first);
      expect(categoryColorAt(categoryPalette.length), categoryPalette.first);
      expect(categoryColorAt(1), categoryPalette[1]);
    });
  });

  group('precision design', () {
    test('shared controls use resolved platform typography', () {
      final ThemeData theme = buildTheme(brightness: Brightness.dark);
      expect(theme.textTheme.headlineSmall?.fontFamily, isNotNull);
      expect(
        theme.appBarTheme.titleTextStyle?.fontFamily,
        theme.textTheme.headlineSmall?.fontFamily,
      );
      expect(
        theme.chipTheme.labelStyle?.fontFamily,
        theme.textTheme.labelMedium?.fontFamily,
      );
      expect(
        theme.inputDecorationTheme.labelStyle?.fontFamily,
        theme.textTheme.bodyLarge?.fontFamily,
      );
      final TextStyle? floatingLabel = WidgetStateProperty.resolveAs(
        theme.inputDecorationTheme.floatingLabelStyle,
        const <WidgetState>{},
      );
      expect(floatingLabel?.fontFamily, theme.textTheme.bodyMedium?.fontFamily);
      expect(
        floatingLabel!.fontSize! * 0.75,
        closeTo(theme.textTheme.bodyMedium!.fontSize!, 0.01),
      );
    });

    test('Midnight uses the selected deep-green and sage palette', () {
      final ThemeData theme = buildTheme(
        brightness: Brightness.light,
        appTheme: AppTheme.midnight,
      );
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.surface, const Color(0xFF172220));
      expect(theme.colorScheme.primary, const Color(0xFFC1E1BD));
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.cardTheme.color, theme.colorScheme.surfaceContainerLow);
      expect(
        theme.inputDecorationTheme.enabledBorder,
        isA<UnderlineInputBorder>(),
      );
      expect(
        theme.floatingActionButtonTheme.foregroundColor,
        theme.colorScheme.onPrimary,
      );
    });

    test('Classic preserves light and dark schemes', () {
      for (final Brightness brightness in Brightness.values) {
        final ThemeData fixed = buildTheme(brightness: brightness);
        expect(fixed.brightness, brightness);
        expect(
          fixed.colorScheme,
          brightness == Brightness.dark ? darkColors : lightColors,
        );
      }
    });

    test('Warm Minimalism light palette and terracotta liabilities meet 4.5:1 contrast', () {
      expect(lightColors.surface, const Color(0xFFFAF8F3));
      expect(lightColors.surfaceContainerLow, const Color(0xFFF2EEE5));
      expect(lightColors.outlineVariant, const Color(0xFFDFD9CC));
      expect(FinanceColors.light.negative, const Color(0xFF8C4A27));
      expect(FinanceColors.dark.negative, const Color(0xFFF2B896));
      expect(FinanceColors.light.negative, isNot(lightColors.error));
      expect(FinanceColors.dark.negative, isNot(darkColors.error));
      expect(liabilityChartColorAt(0, dark: false), const Color(0xFF8C4A27));
      expect(liabilityChartColorAt(0, dark: true), const Color(0xFFF2B896));
    });

    test('text and primary actions meet a 4.5:1 contrast ratio', () {
      double contrast(Color a, Color b) {
        final double first = a.computeLuminance();
        final double second = b.computeLuminance();
        final double high = first > second ? first : second;
        final double low = first > second ? second : first;
        return (high + 0.05) / (low + 0.05);
      }

      for (final (ColorScheme scheme, FinanceColors finance)
          in <(ColorScheme, FinanceColors)>[
            (lightColors, FinanceColors.light),
            (darkColors, FinanceColors.dark),
          ]) {
        for (final (Color foreground, Color background) pair
            in <(Color, Color)>[
              (scheme.onSurface, scheme.surface),
              (scheme.onSurfaceVariant, scheme.surfaceContainerLow),
              (scheme.primary, scheme.surface),
              (scheme.onPrimary, scheme.primary),
              (scheme.onSecondaryContainer, scheme.secondaryContainer),
              (finance.positive, scheme.surface),
              (finance.positive, scheme.surfaceContainerLow),
              (finance.negative, scheme.surface),
              (finance.negative, scheme.surfaceContainerLow),
            ]) {
          expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        }
      }
      for (final Color surface in AppStyle.midnight.heroGradient!) {
        expect(
          contrast(AppStyle.midnight.heroForeground!, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      for (final Color fill in AppStyle.midnight.fabGradient!) {
        expect(contrast(darkColors.onPrimary, fill), greaterThanOrEqualTo(4.5));
      }
    });
  });
}
