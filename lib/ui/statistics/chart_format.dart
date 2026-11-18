/// Minimum scale factor applied to a full formatted amount in the donut hole
/// before switching to compact currency units.
const double kMinFullChartAmountScale = 0.75;

/// Percentage label shown under the donut's center value: whole numbers at or
/// above 10%, one decimal below that.
String percentageLabel(double value, double total) {
  if (total <= 0.0) return '';
  final double pct = value / total * 100.0;
  return pct >= 10.0 ? '${pct.truncate()}%' : '${pct.toStringAsFixed(1)}%';
}

/// Chooses between [fullText] and [compactText] for a donut hole of [maxWidth]
/// given the unscaled single-line [fullTextWidth].
///
/// Preserves the exact [fullText] whenever scaling it into [maxWidth] stays at
/// or above [minScale] of the headline font size, switching to [compactText]
/// when the full figure would shrink too small to read comfortably.
String selectDonutCenterAmount({
  required String fullText,
  required String compactText,
  required double fullTextWidth,
  required double maxWidth,
  double minScale = kMinFullChartAmountScale,
}) {
  if (maxWidth <= 0 ||
      compactText == fullText ||
      compactText.length >= fullText.length) {
    return fullText;
  }
  return fullTextWidth * minScale > maxWidth ? compactText : fullText;
}
