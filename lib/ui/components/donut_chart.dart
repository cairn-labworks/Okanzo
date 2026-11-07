import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// One wedge of a [DonutChart].
@immutable
class PieSlice {
  const PieSlice(this.label, this.value, this.color);

  final String label;
  final double value;
  final Color color;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PieSlice &&
          other.label == label &&
          other.value == value &&
          other.color == color;

  @override
  int get hashCode => Object.hash(label, value, color);
}

/// A dependency-free donut chart. Tapping a wedge reports its index through
/// [onSelect] (tapping the selected wedge again, or the empty hole, clears the
/// selection by reporting null). The [child] is rendered in the donut hole.
class DonutChart extends StatelessWidget {
  const DonutChart({
    required this.slices,
    required this.selectedIndex,
    required this.onSelect,
    required this.child,
    this.diameter = 220,
    this.thicknessRatio = 0.42,
    super.key,
  });

  final List<PieSlice> slices;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;
  final Widget child;
  final double diameter;
  final double thicknessRatio;

  static const double _gapDegrees = 1.5;

  double get _total =>
      slices.fold<double>(0, (double sum, PieSlice s) => sum + s.value);

  void _handleTap(Offset local) {
    final double total = _total;
    if (total <= 0) return;
    final Offset center = Offset(diameter / 2, diameter / 2);
    final double dx = local.dx - center.dx;
    final double dy = local.dy - center.dy;
    final double distance = math.sqrt(dx * dx + dy * dy);
    final double outer = diameter / 2;
    final double inner = outer * (1 - thicknessRatio);
    if (distance < inner || distance > outer) {
      onSelect(null);
      return;
    }
    // Angle clockwise from 12 o'clock, matching the arc drawing.
    double theta = math.atan2(dy, dx) * 180 / math.pi;
    theta = (theta + 90 + 360) % 360;
    double accumulated = 0;
    for (int i = 0; i < slices.length; i++) {
      final double sweep = slices[i].value / total * 360;
      if (theta >= accumulated && theta < accumulated + sweep) {
        onSelect(selectedIndex == i ? null : i);
        return;
      }
      accumulated += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails details) =>
            _handleTap(details.localPosition),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _DonutPainter(
              slices: slices,
              selectedIndex: selectedIndex,
              thicknessRatio: thicknessRatio,
              gapDegrees: _gapDegrees,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.slices,
    required this.selectedIndex,
    required this.thicknessRatio,
    required this.gapDegrees,
  });

  final List<PieSlice> slices;
  final int? selectedIndex;
  final double thicknessRatio;
  final double gapDegrees;

  @override
  void paint(Canvas canvas, Size size) {
    final double total = slices.fold<double>(
      0,
      (double sum, PieSlice s) => sum + s.value,
    );
    if (total <= 0) return;

    final double outer = math.min(size.width, size.height) / 2;
    final double stroke = outer * thicknessRatio;
    final double radius = outer - stroke / 2;
    final Rect rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );

    double startAngle = -90;
    for (int index = 0; index < slices.length; index++) {
      final PieSlice slice = slices[index];
      final double sweep = slice.value / total * 360;
      final bool dim = selectedIndex != null && selectedIndex != index;
      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = dim ? slice.color.withValues(alpha: 0.30) : slice.color;
      canvas.drawArc(
        rect,
        startAngle * math.pi / 180,
        (sweep - gapDegrees) * math.pi / 180,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.thicknessRatio != thicknessRatio ||
      oldDelegate.gapDegrees != gapDegrees ||
      !listEquals(oldDelegate.slices, slices);
}
