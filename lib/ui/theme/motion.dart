import 'package:flutter/material.dart';

const Curve interactionCurve = Curves.easeOutCubic;
const Duration _interactionDuration = Duration(milliseconds: 180);

Duration interactionDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : _interactionDuration;

class AppPageTransitionsBuilder extends PredictiveBackPageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return MediaQuery.disableAnimationsOf(context)
        ? child
        : super.buildTransitions(
            route,
            context,
            animation,
            secondaryAnimation,
            child,
          );
  }
}

/// Animates the replacement in place without retaining the outgoing content.
class MotionEntrance extends StatefulWidget {
  const MotionEntrance({
    required this.trigger,
    required this.child,
    this.distance = 6,
    this.enabled = true,
    super.key,
  });

  final Object trigger;
  final Widget child;
  final double distance;
  final bool enabled;

  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _interactionDuration,
    value: 1,
  );
  late final Animation<double> _progress = _controller.drive(
    CurveTween(curve: interactionCurve),
  );
  late final Animation<double> _opacity = _progress.drive(
    Tween<double>(begin: 0.72, end: 1),
  );

  bool get _enabled =>
      widget.enabled && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enabled) _controller.value = 1;
  }

  @override
  void didUpdateWidget(MotionEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) {
      _controller.value = 1;
    } else if (oldWidget.trigger != widget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: widget.distance == 0
          ? widget.child
          : AnimatedBuilder(
              animation: _progress,
              builder: (BuildContext context, Widget? child) =>
                  Transform.translate(
                    offset: Offset(0, widget.distance * (1 - _progress.value)),
                    child: child,
                  ),
              child: widget.child,
            ),
    );
  }
}

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
