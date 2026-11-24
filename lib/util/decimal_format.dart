/// The shortest decimal representation that round-trips to [value], without
/// scientific notation or a trailing `.0`.
String formatPlainDecimal(double value) {
  final sign = value < 0 ? '-' : '';
  final parts = value.abs().toString().split('e');
  final mantissa = parts.first.endsWith('.0')
      ? parts.first.substring(0, parts.first.length - 2)
      : parts.first;
  if (parts.length == 1) return '$sign$mantissa';
  final point = mantissa.contains('.')
      ? mantissa.indexOf('.')
      : mantissa.length;
  final digits = mantissa.replaceAll('.', '');
  final position = point + int.parse(parts.last);
  if (position <= 0) {
    return '${sign}0.${'0' * -position}$digits';
  }
  if (position >= digits.length) {
    return '$sign$digits${'0' * (position - digits.length)}';
  }
  return '$sign${digits.substring(0, position)}.${digits.substring(position)}';
}
