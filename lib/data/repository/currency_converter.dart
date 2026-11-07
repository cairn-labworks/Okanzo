const String _usd = 'USD';

/// Converts monetary amounts between currencies using cached rates expressed as
/// units-per-USD. When a rate is unavailable the amount is passed through 1:1 and
/// [canConvert] returns false so the UI can warn that a total may be approximate.
class CurrencyConverter {
  const CurrencyConverter(this.unitsPerUsd);

  const CurrencyConverter.empty() : unitsPerUsd = const <String, double>{};

  final Map<String, double> unitsPerUsd;

  bool canConvert(String code) {
    final double? rate = _rateFor(code);
    return rate != null && rate.isFinite && rate > 0;
  }

  double convert(double amount, String from, String to) {
    if (from == to) return amount;
    final double? fromRate = _rateFor(from);
    if (fromRate == null) return amount;
    final double? toRate = _rateFor(to);
    if (toRate == null) return amount;
    if (fromRate == 0.0) return amount;
    final double inUsd = amount / fromRate;
    return inUsd * toRate;
  }

  double? _rateFor(String code) => code == _usd ? 1.0 : unitsPerUsd[code];

  bool get isEmpty => unitsPerUsd.isEmpty;
}
