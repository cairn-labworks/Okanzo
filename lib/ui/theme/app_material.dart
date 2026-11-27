import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_style.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.color,
    this.shape,
    this.clipBehavior,
    super.key,
  });

  final Widget child;
  final Color? color;
  final ShapeBorder? shape;
  final Clip? clipBehavior;

  @override
  Widget build(BuildContext context) => AppSurface(
    child: Card(
      color: AppStyle.of(context).isEnhanced ? Colors.transparent : color,
      shape: shape,
      clipBehavior: clipBehavior,
      child: child,
    ),
  );
}

/// Opt-in depth and bounded backdrop blur; Original keeps its existing child.
class AppSurface extends StatelessWidget {
  const AppSurface({
    required this.child,
    this.radius = 20,
    this.hero = false,
    this.control = false,
    this.tint,
    super.key,
  });

  final Widget child;
  final double radius;
  final bool hero;
  final bool control;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final AppStyle style = AppStyle.of(context);
    if (!style.isEnhanced) return child;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool dark = colors.brightness == Brightness.dark;
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final List<Color> fills;
    if (tint case final Color accent) {
      fills = <Color>[
        Color.alphaBlend(
          accent.withValues(alpha: .20),
          colors.surfaceContainerLowest,
        ),
        Color.alphaBlend(
          accent.withValues(alpha: .08),
          colors.surfaceContainerLow,
        ),
      ];
    } else if (style.isGlass) {
      fills = dark
          ? const <Color>[
              Color(0xC7355343),
              Color(0xB81B2C24),
              Color(0xD6243B30),
            ]
          : const <Color>[
              Color(0xD9EDF0E5),
              Color(0xABE8ECDC),
              Color(0xCCE3E9D9),
            ];
    } else {
      fills = dark
          ? <Color>[
              hero
                  ? colors.surfaceContainerLow
                  : Color.lerp(
                      colors.surfaceContainerLow,
                      colors.onSurface,
                      .02,
                    )!,
              hero ? colors.surface : colors.surfaceContainerLow,
            ]
          : <Color>[colors.surfaceContainerLowest, colors.surfaceContainerLow];
    }
    final Color rim = style.isGlass
        ? (dark ? const Color(0x6BECFFF0) : const Color(0xA6F5F7E5))
        : Color.lerp(colors.outlineVariant, colors.primary, .18)!;
    final BoxDecoration decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: fills,
      ),
      borderRadius: borderRadius,
      border: Border.all(color: rim),
    );
    final List<BoxShadow> shadows = <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? .24 : .08),
        blurRadius: control ? 4 : 20,
        offset: Offset(0, control ? 2 : 8),
      ),
    ];
    if (!style.isGlass) {
      return DecoratedBox(
        decoration: decoration.copyWith(boxShadow: shadows),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: control ? 14 : 20,
            sigmaY: control ? 14 : 20,
          ),
          child: DecoratedBox(decoration: decoration, child: child),
        ),
      ),
    );
  }
}

/// One ambient backdrop behind the navigator, never behind individual rows.
class AppThemeBackground extends StatelessWidget {
  const AppThemeBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppStyle.of(context).isGlass) return child;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool dark = colors.brightness == Brightness.dark;
    final List<(Alignment, Color)> lights = dark
        ? const <(Alignment, Color)>[
            (Alignment(-1, -.8), Color(0x6682B18C)),
            (Alignment(1, .2), Color(0x596D9E98)),
            (Alignment(-.5, 1), Color(0x38879668)),
          ]
        : const <(Alignment, Color)>[
            (Alignment(-1, -.8), Color(0x7093B79B)),
            (Alignment(1, .2), Color(0x80B8D3CE)),
            (Alignment(-.5, 1), Color(0x7AD7D1B4)),
          ];
    return ColoredBox(
      color: colors.surface,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          for (final (Alignment center, Color color) in lights)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: center,
                  radius: 1.1,
                  colors: <Color>[color, color.withValues(alpha: 0)],
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

Widget appButtonSheen(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  if (states.contains(WidgetState.disabled)) {
    return child ?? const SizedBox.shrink();
  }
  final Widget button = context.widget;
  final OutlinedBorder shape =
      (button is ButtonStyleButton
          ? button.style?.shape?.resolve(states)
          : null) ??
      FilledButtonTheme.of(context).style?.shape?.resolve(states) ??
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      );
  return DecoratedBox(
    decoration: ShapeDecoration(
      shape: shape,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const <double>[0, .55, 1],
        colors: <Color>[
          Colors.white.withValues(
            alpha: states.contains(WidgetState.hovered) ? .18 : .12,
          ),
          Colors.transparent,
          Colors.black.withValues(
            alpha: states.contains(WidgetState.pressed) ? .14 : .08,
          ),
        ],
      ),
    ),
    child: child,
  );
}
