import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    this.holePadding = 8,
    super.key,
  });

  final List<PieSlice> slices;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;
  final Widget child;
  final double diameter;
  final double thicknessRatio;

  /// Radial clearance kept between the inner edge of the ring and [child].
  final double holePadding;

  static const double _gapDegrees = 1.5;

  /// Radius of the unpainted inner hole before [holePadding] is subtracted.
  double get innerRadius => (diameter / 2) * (1 - thicknessRatio);

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
    final double inner = innerRadius;
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
    final double safeHoleRadius = math.max(0, innerRadius - holePadding);
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
            child: _DonutHoleSlot(holeRadius: safeHoleRadius, child: child),
          ),
        ),
      ),
    );
  }
}

/// Centers [child] inside the circular donut hole of [holeRadius], scaling it
/// down uniformly only when its bounding-box diagonal would cross [holeRadius].
class _DonutHoleSlot extends SingleChildRenderObjectWidget {
  const _DonutHoleSlot({required this.holeRadius, required super.child});

  final double holeRadius;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDonutHoleSlot(holeRadius: holeRadius);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDonutHoleSlot renderObject,
  ) {
    renderObject.holeRadius = holeRadius;
  }
}

class _RenderDonutHoleSlot extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderDonutHoleSlot({required double holeRadius}) : _holeRadius = holeRadius;

  static const double _preferredWidthFactor = 1.85;

  double _holeRadius;
  double _scale = 1;
  final LayerHandle<TransformLayer> _transformLayer =
      LayerHandle<TransformLayer>();

  double get holeRadius => _holeRadius;

  set holeRadius(double value) {
    if (_holeRadius == value) return;
    _holeRadius = value;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final RenderBox? currentChild = child;
    if (currentChild == null) {
      _scale = 1;
      return;
    }
    final double maxWidth = math.max(0, _holeRadius * _preferredWidthFactor);
    currentChild.layout(
      BoxConstraints(maxWidth: maxWidth),
      parentUsesSize: true,
    );
    final Size childSize = currentChild.size;
    final double halfDiagonal =
        math.sqrt(
          childSize.width * childSize.width +
              childSize.height * childSize.height,
        ) /
        2;
    _scale = (halfDiagonal > 0 && halfDiagonal > _holeRadius)
        ? (_holeRadius / halfDiagonal)
        : 1;
  }

  Matrix4 _buildTransform() {
    final Size childSize = child!.size;
    final double dx = (size.width - childSize.width * _scale) / 2;
    final double dy = (size.height - childSize.height * _scale) / 2;
    return Matrix4.translationValues(dx, dy, 0)
      ..multiply(Matrix4.diagonal3Values(_scale, _scale, 1));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_buildTransform());
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderBox? currentChild = child;
    if (currentChild == null || _holeRadius <= 0) {
      _transformLayer.layer = null;
      return;
    }
    if (_scale == 1) {
      _transformLayer.layer = null;
      final Offset childOffset = Offset(
        (size.width - currentChild.size.width) / 2,
        (size.height - currentChild.size.height) / 2,
      );
      context.paintChild(currentChild, offset + childOffset);
      return;
    }
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _buildTransform(),
      (PaintingContext innerContext, Offset innerOffset) {
        innerContext.paintChild(currentChild, innerOffset);
      },
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final RenderBox? currentChild = child;
    if (currentChild == null || _holeRadius <= 0) return false;
    return result.addWithPaintTransform(
      transform: _buildTransform(),
      position: position,
      hitTest: (BoxHitTestResult res, Offset transformed) =>
          currentChild.hitTest(res, position: transformed),
    );
  }

  @override
  void dispose() {
    _transformLayer.layer = null;
    super.dispose();
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
