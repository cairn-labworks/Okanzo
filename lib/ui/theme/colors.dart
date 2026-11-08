import 'package:flutter/material.dart';

// Fixed sage palettes used when Material You does not supply device colours.

const ColorScheme lightColors = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF3D6249),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFDCE9D8),
  onPrimaryContainer: Color(0xFF203828),
  secondary: Color(0xFF566A5C),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE2EBE1),
  onSecondaryContainer: Color(0xFF304536),
  tertiary: Color(0xFF546C76),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFCBE6FF),
  onTertiaryContainer: Color(0xFF001E30),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFF6F8F3),
  onSurface: Color(0xFF25332B),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFEDF2EA),
  surfaceContainer: Color(0xFFE8EEE5),
  surfaceContainerHigh: Color(0xFFE1E9DE),
  surfaceContainerHighest: Color(0xFFD9E3D6),
  onSurfaceVariant: Color(0xFF5F7063),
  outline: Color(0xFF748677),
  outlineVariant: Color(0xFFD1DCCE),
  surfaceTint: Color(0xFF3D6249),
  inverseSurface: Color(0xFF2D3130),
  onInverseSurface: Color(0xFFEFF1EF),
  inversePrimary: Color(0xFFC1E1BD),
);

const ColorScheme darkColors = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFC1E1BD),
  onPrimary: Color(0xFF1E3025),
  primaryContainer: Color(0xFF2D4635),
  onPrimaryContainer: Color(0xFFD6EBD1),
  secondary: Color(0xFFB8CFBB),
  onSecondary: Color(0xFF203329),
  secondaryContainer: Color(0xFF24372E),
  onSecondaryContainer: Color(0xFFD3E3D4),
  tertiary: Color(0xFFA7C9D0),
  onTertiary: Color(0xFF1C343C),
  tertiaryContainer: Color(0xFF2D474E),
  onTertiaryContainer: Color(0xFFD1E7EB),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF172220),
  onSurface: Color(0xFFE8F0E9),
  surfaceContainerLowest: Color(0xFF111B18),
  surfaceContainerLow: Color(0xFF20302A),
  surfaceContainer: Color(0xFF24352E),
  surfaceContainerHigh: Color(0xFF2B3D34),
  surfaceContainerHighest: Color(0xFF33473C),
  onSurfaceVariant: Color(0xFF88A196),
  outline: Color(0xFF779184),
  outlineVariant: Color(0xFF2A3934),
  surfaceTint: Color(0xFFC1E1BD),
  inverseSurface: Color(0xFFE0E3E1),
  onInverseSurface: Color(0xFF191C1B),
  inversePrimary: Color(0xFF3D6249),
);

// Semantic colors for positive (assets/gains) and negative (liabilities/losses).
const Color positiveGreen = Color(0xFF3D6249);
const Color positiveGreenDark = Color(0xFFC1E1BD);
const Color negativeRed = Color(0xFFBA1A1A);
const Color negativeRedDark = Color(0xFFFFB4AB);

/// Palette used for chart slices, cycled by index.
const List<Color> chartColors = <Color>[
  Color(0xFF7DAD8B),
  Color(0xFF7897B0),
  Color(0xFFC0A169),
  Color(0xFF9C89B5),
  Color(0xFF98AF79),
  Color(0xFFC48E84),
  Color(0xFF71A9AC),
  Color(0xFFBD946E),
  Color(0xFF9D8E7C),
  Color(0xFF8CACA0),
  Color(0xFFB6B679),
  Color(0xFFB38DAB),
];

Color chartColorAt(int index) => chartColors[index % chartColors.length];

// ---------------------------------------------------------------------------
// Midnight theme
// ---------------------------------------------------------------------------

/// Midnight keeps the fixed precision palette regardless of device appearance.
const ColorScheme midnightColors = darkColors;

/// Subdued, distinct category accents on the Midnight theme.
const List<Color> categoryPalette = <Color>[
  Color(0xFFB9D6B4),
  Color(0xFFA5C3D2),
  Color(0xFFDAC59A),
  Color(0xFFC2B5D5),
  Color(0xFFA7CFCC),
  Color(0xFFD6B49B),
  Color(0xFFD0B5C5),
  Color(0xFFADCABB),
  Color(0xFFB1C1DB),
  Color(0xFFDDB4AA),
];

Color categoryColorAt(int index) =>
    categoryPalette[index % categoryPalette.length];
