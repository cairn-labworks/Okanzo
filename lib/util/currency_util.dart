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

  static final RegExp _localeSeparator = RegExp('[_-]');
  static final RegExp _letterCurrencyPattern = RegExp(
    r'(\p{L})(\p{Sc})',
    unicode: true,
  );
  static final Map<String, String> _symbolCache = <String, String>{};
  static String? _cachedDeviceLocale;
  static String? _cachedDeviceCurrency;

  /// Every ISO-4217 currency code known to the app, sorted.
  static List<String> get allCurrencies => _allCurrencies;

  /// The currency of the current locale's country, falling back to USD.
  static String deviceCurrencyCode() {
    final String locale = Intl.defaultLocale ?? Intl.systemLocale;
    if (_cachedDeviceLocale == locale && _cachedDeviceCurrency != null) {
      return _cachedDeviceCurrency!;
    }
    final List<String> parts = locale.split(_localeSeparator);
    String resolved = 'USD';
    for (final String part in parts.reversed) {
      final String candidate = part.toUpperCase();
      final String? code = kCountryCurrencies[candidate];
      if (code != null) {
        resolved = code;
        break;
      }
    }
    _cachedDeviceLocale = locale;
    _cachedDeviceCurrency = resolved;
    return resolved;
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
  static String symbol(String code) =>
      _symbolCache.putIfAbsent(code, () => _spaceSymbol(_rawSymbol(code)));

  static String _rawSymbol(String code) => kCurrencies[code]?.symbol ?? code;

  static String _spaceSymbol(String symbol) => symbol.replaceAllMapped(
    _letterCurrencyPattern,
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

  /// Compact headline figures: lakh/crore/lakh-crore for INR, K/M/B/T otherwise.
  static String formatCompact(double amount, String code) {
    final String currencySymbol = symbol(code);
    final double abs = amount.abs();
    final String sign = amount < 0 ? '-' : '';
    if (code == 'INR') {
      if (abs >= 1000000000000) {
        return '$sign$currencySymbol${_round(abs / 1000000000000, decimalPlaces: 2, indianGrouping: true)} L Cr';
      }
      if (abs >= 10000000) {
        return '$sign$currencySymbol${_round(abs / 10000000, decimalPlaces: 2, indianGrouping: true)} Cr';
      }
      if (abs >= 100000) {
        return '$sign$currencySymbol${_round(abs / 100000, decimalPlaces: 2, indianGrouping: true)} L';
      }
    }
    if (abs >= 1000000000000) {
      return '$sign$currencySymbol${_round(abs / 1000000000000)}T';
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

  static String _round(
    double value, {
    int decimalPlaces = 1,
    bool indianGrouping = false,
  }) {
    if (!value.isFinite) return '0';
    final int scaleInt = math.pow(10, decimalPlaces).round();
    final double scaledDouble = value * scaleInt;
    if (scaledDouble.abs() >= 9007199254740992.0) {
      return value.toStringAsExponential(1);
    }
    final int scaled = scaledDouble.truncate();
    final int whole = scaled ~/ scaleInt;
    final int fraction = scaled % scaleInt;
    final String wholeText = _groupCompactWhole(whole, indian: indianGrouping);
    if (decimalPlaces <= 0 || fraction == 0) {
      return wholeText;
    }
    final String fractionDigits = fraction
        .toString()
        .padLeft(decimalPlaces, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '$wholeText.$fractionDigits';
  }

  static String _groupCompactWhole(int value, {required bool indian}) {
    final String digits = value.toString();
    if (digits.length <= 3) return digits;
    if (indian) {
      final String tail = digits.substring(digits.length - 3);
      final String head = digits.substring(0, digits.length - 3);
      final StringBuffer buffer = StringBuffer();
      final int leading = head.length % 2;
      if (leading > 0) {
        buffer.write(head.substring(0, leading));
      }
      for (int i = leading; i < head.length; i += 2) {
        if (buffer.isNotEmpty) buffer.write(',');
        buffer.write(head.substring(i, i + 2));
      }
      buffer
        ..write(',')
        ..write(tail);
      return buffer.toString();
    }
    final StringBuffer buffer = StringBuffer();
    final int leading = digits.length % 3;
    if (leading > 0) {
      buffer.write(digits.substring(0, leading));
    }
    for (int i = leading; i < digits.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write(',');
      buffer.write(digits.substring(i, i + 3));
    }
    return buffer.toString();
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
