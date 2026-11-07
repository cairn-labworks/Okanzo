import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'currency_data.dart';

/// Helpers for currency codes and money formatting. All formatting happens
/// on-device; nothing is transmitted.
class CurrencyUtil {
  const CurrencyUtil._();

  /// A curated shortlist surfaced first in pickers.
  static const List<String> commonCurrencies = <String>[
    'USD', 'EUR', 'GBP', 'INR', 'JPY', 'CNY', 'AUD', 'CAD', 'CHF', //
    'SGD', 'HKD', 'AED', 'SAR', 'ZAR', 'BRL', 'RUB', 'KRW', 'SEK', //
    'NOK', 'DKK', 'NZD', 'MXN', 'THB', 'IDR', 'MYR', 'PHP',
  ];

  /// Short masked placeholder for compact spots (rows, tiles).
  static const String maskShort = '••••';

  static final List<String> _allCurrencies = kCurrencies.keys.toList(
    growable: false,
  )..sort();

  /// Every ISO-4217 currency code known to the app, sorted.
  static List<String> get allCurrencies => _allCurrencies;

  /// The currency of the current locale's country, falling back to USD.
  static String deviceCurrencyCode() {
    final String locale = Intl.defaultLocale ?? Intl.systemLocale;
    final List<String> parts = locale.split(RegExp('[_-]'));
    for (final String part in parts.reversed) {
      final String candidate = part.toUpperCase();
      final String? code = kCountryCurrencies[candidate];
      if (code != null) return code;
    }
    return 'USD';
  }

  static String displayName(String code) =>
      kCurrencies[code]?.displayName ?? code;

  /// Fraction digits appropriate for the currency (e.g. 0 for JPY, 2 for USD).
  static int fractionDigits(String code) {
    final int? digits = kCurrencies[code]?.fractionDigits;
    if (digits == null) return 2;
    return digits < 0 ? 0 : digits;
  }

  /// The currency symbol, with a space inserted between letter prefixes and the
  /// currency sign so codes like USD read as "US $" instead of "US$".
  static String symbol(String code) => _spaceSymbol(_rawSymbol(code));

  static String _rawSymbol(String code) => kCurrencies[code]?.symbol ?? code;

  static String _spaceSymbol(String symbol) => symbol.replaceAllMapped(
    RegExp(r'(\p{L})(\p{Sc})', unicode: true),
    (Match match) => '${match[1]} ${match[2]}',
  );

  /// Formats [amount] as a currency string with grouping and no decimals,
  /// e.g. "US $1,234" or "₹1,234". Decimals are intentionally truncated.
  static String format(double amount, String code) {
    final String currencySymbol = symbol(code);
    final int rounded = _javaRound(amount);
    final String sign = rounded < 0 ? '-' : '';
    return '$sign$currencySymbol${_integerFormat.format(rounded.abs())}';
  }

  /// A masked placeholder for a hidden balance, e.g. "₹ ••••" or "US $ ••••".
  static String masked(String code) => '${symbol(code)} $maskShort';

  /// Compact headline figures: lakh/crore for INR, K/M/B otherwise.
  static String formatCompact(double amount, String code) {
    final String currencySymbol = symbol(code);
    final double abs = amount.abs();
    final String sign = amount < 0 ? '-' : '';
    if (code == 'INR') {
      if (abs >= 10000000) {
        return '$sign$currencySymbol${_round(abs / 10000000, decimalPlaces: 2)} Cr';
      }
      if (abs >= 100000) {
        return '$sign$currencySymbol${_round(abs / 100000, decimalPlaces: 2)} L';
      }
    }
    if (abs >= 1000000000) {
      return '$sign$currencySymbol${_round(abs / 1000000000)}B';
    }
    if (abs >= 1000000) {
      return '$sign$currencySymbol${_round(abs / 1000000)}M';
    }
    if (abs >= 1000) {
      return '$sign$currencySymbol${_round(abs / 1000)}K';
    }
    return format(amount, code);
  }

  static String _round(double value, {int decimalPlaces = 1}) {
    final double scale = math.pow(10, decimalPlaces).toDouble();
    final double rounded = (value * scale).truncate() / scale;
    return rounded % 1.0 == 0.0
        ? rounded.truncate().toString()
        : rounded.toString();
  }

  /// Matches `java.lang.Math.round`: floor(value + 0.5), which differs from
  /// Dart's [double.round] for negative halves (-0.5 rounds to 0, not -1).
  static int _javaRound(double value) {
    if (value.isNaN) return 0;
    if (value.isInfinite) {
      return value.isNegative ? -9007199254740992 : 9007199254740992;
    }
    final double shifted = value + 0.5;
    if (shifted.abs() > 9007199254740992.0) return shifted.toInt();
    return shifted.floor();
  }

  static NumberFormat get _integerFormat {
    final String locale = Intl.defaultLocale ?? Intl.systemLocale;
    if (_cachedLocale != locale || _cachedFormat == null) {
      _cachedLocale = locale;
      NumberFormat format;
      try {
        format = NumberFormat.decimalPattern(locale);
      } on Exception {
        format = NumberFormat.decimalPattern('en_US');
      }
      format.maximumFractionDigits = 0;
      _cachedFormat = format;
    }
    return _cachedFormat!;
  }

  static String? _cachedLocale;
  static NumberFormat? _cachedFormat;
}
