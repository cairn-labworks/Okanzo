import 'package:flutter/material.dart';

const Curve interactionCurve = Curves.easeOutCubic;

Duration interactionDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 180);

class DisclosureSize extends StatelessWidget {
  const DisclosureSize({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Duration duration = interactionDuration(context);
    // A zero-duration AnimatedSize can notify its layout listener mid-layout.
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: interactionCurve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
