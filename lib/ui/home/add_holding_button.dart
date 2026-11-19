import 'dart:ui';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class AddHoldingButton extends StatelessWidget {
  const AddHoldingButton({
    required this.onAsset,
    required this.onLiability,
    super.key,
  });

  final VoidCallback onAsset;
  final VoidCallback onLiability;

  Future<void> _open(BuildContext context) async {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(
              context,
              rootNavigator: true,
            ).overlay!.context.findRenderObject()!
            as RenderBox;
    final Rect anchor =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    final double endInset = Directionality.of(context) == TextDirection.ltr
        ? overlay.size.width - anchor.right
        : anchor.left;
    final double bottomInset = overlay.size.height - anchor.bottom;
    final bool reducedMotion = MediaQuery.disableAnimationsOf(context);
    final bool? asset = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close'.tr(context),
      barrierColor: Colors.transparent,
      transitionDuration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 360),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final ColorScheme colors = Theme.of(context).colorScheme;
        final Animation<double> curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final double endWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
          0,
          300,
        );
        final double width = lerpDouble(anchor.width, endWidth, curve.value)!;
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 4 * curve.value,
                    sigmaY: 4 * curve.value,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: .08 * curve.value),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              end: endInset,
              bottom: bottomInset,
              width: width,
              child: Material(
                key: const ValueKey<String>('expanded-add-holding'),
                color: colors.primary,
                textStyle: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: colors.onPrimary),
                elevation: 3 + 5 * curve.value,
                borderRadius: BorderRadius.circular(16 + 6 * curve.value),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        (MediaQuery.sizeOf(context).height -
                                bottomInset -
                                MediaQuery.paddingOf(context).top)
                            .clamp(0, double.infinity),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizeTransition(
                          sizeFactor: curve,
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: <Widget>[
                                _Choice(
                                  animation: animation,
                                  start: .33,
                                  icon: Icons.trending_up,
                                  label: 'New asset'.tr(context),
                                  iconColor: const Color(0xFF27583B),
                                  iconBackground: const Color(0xFFB8D7B1),
                                  onTap: () => Navigator.of(context).pop(true),
                                ),
                                const SizedBox(height: 8),
                                _Choice(
                                  animation: animation,
                                  start: .22,
                                  icon: Icons.trending_down,
                                  label: 'New liability'.tr(context),
                                  iconColor: const Color(0xFF754424),
                                  iconBackground: const Color(0xFFF0D7B9),
                                  onTap: () => Navigator.of(context).pop(false),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: colors.onPrimary.withValues(
                            alpha: .14 * curve.value,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Color.lerp(
                              colors.onPrimary,
                              colors.primary,
                              .2 * curve.value,
                            ),
                            textStyle: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.lerp(
                                    FontWeight.w600,
                                    FontWeight.w400,
                                    curve.value,
                                  ),
                                ),
                            minimumSize: Size(width, anchor.height),
                            alignment: AlignmentDirectional.centerStart,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Row(
                            children: <Widget>[
                              Transform.rotate(
                                angle: curve.value * .785398,
                                child: const Icon(Icons.add, size: 20),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Stack(
                                  children: <Widget>[
                                    Opacity(
                                      opacity: 1 - curve.value,
                                      child: Text('Add holding'.tr(context)),
                                    ),
                                    Opacity(
                                      opacity: curve.value,
                                      child: Text('Close'.tr(context)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    if (!context.mounted || asset == null) return;
    if (asset) {
      onAsset();
    } else {
      onLiability();
    }
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (BuildContext buttonContext) => FilledButton.icon(
      key: const ValueKey<String>('add-holding'),
      onPressed: () => _open(buttonContext),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.add, size: 20),
      label: Text('Add holding'.tr(context)),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.animation,
    required this.start,
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.iconBackground,
    required this.onTap,
  });

  final Animation<double> animation;
  final double start;
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = Theme.of(context).colorScheme.onPrimary;
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Interval(start, .9, curve: Curves.easeOut),
      ),
      child: Material(
        color: foreground.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(13),
        child: ListTile(
          minTileHeight: 66,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 20, color: iconColor),
            ),
          ),
          title: Text(label, style: TextStyle(color: foreground)),
          onTap: onTap,
        ),
      ),
    );
  }
}
