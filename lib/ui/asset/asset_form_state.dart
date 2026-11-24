import '../../data/local/entity/asset_entity.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/precious_metal.dart';
import '../../domain/model/stock_exchange.dart';
import '../../util/decimal_format.dart';

/// Editable state of the asset form. Pure data + validation so it can be
/// unit-tested without a widget tree.
class AssetFormState {
  const AssetFormState({
    this.id = 0,
    this.position = 0,
    this.portfolioId = 0,
    this.type = AssetType.stock,
    this.name = '',
    this.customName = '',
    this.currency = 'USD',
    this.quantity = '',
    this.pricePerUnit = '',
    this.metal,
    this.purity,
    this.customPrice = false,
    this.useTotalValue = false,
    this.symbol = '',
    this.exchange = StockExchange.us,
    this.manualValue = '',
    this.lastPrice,
    this.lastPriceTimestamp,
    this.notes = '',
    this.loading = true,
    this.isFetchingPrice = false,
    this.isSaving = false,
  });

  final int id;
  final int position;
  final int portfolioId;
  final AssetType type;
  final String name;
  final String customName;
  final String currency;
  final String quantity;
  final String pricePerUnit;
  final PreciousMetal? metal;
  final String? purity;
  final bool customPrice;
  final bool useTotalValue;
  final String symbol;
  final StockExchange exchange;
  final String manualValue;
  final double? lastPrice;
  final int? lastPriceTimestamp;
  final String notes;
  final bool loading;
  final bool isFetchingPrice;
  final bool isSaving;

  bool get isEditing => id != 0;

  ValuationMode get valuationMode => type.valuationMode;

  bool get usesStockExchange =>
      type == AssetType.stock || type == AssetType.mutualFund;

  double? get metalRate =>
      customPrice ? double.tryParse(pricePerUnit) : lastPrice;

  String get quoteSymbol => usesStockExchange
      ? exchange.qualify(symbol)
      : symbol.trim().toUpperCase();

  AssetFormState withSymbol(String value) {
    final StockExchange next = usesStockExchange && value.contains('.')
        ? StockExchange.fromSymbol(value)
        : exchange;
    final String nextQuote = usesStockExchange
        ? next.qualify(value)
        : value.trim().toUpperCase();
    return copyWith(
      symbol: value,
      exchange: next,
      name: type.isMarketLinked && nextQuote != quoteSymbol ? '' : null,
      currency: next != exchange ? next.currency : null,
      clearLastPrice: true,
    );
  }

  AssetFormState withExchange(StockExchange value) {
    if (value == exchange) return this;
    final String ticker = quoteSymbol;
    final int separator = ticker.lastIndexOf('.');
    final String nextSymbol = value == StockExchange.other || separator < 0
        ? ticker
        : ticker.substring(0, separator);
    final String nextQuote = usesStockExchange
        ? value.qualify(nextSymbol)
        : nextSymbol.trim().toUpperCase();
    return copyWith(
      exchange: value,
      symbol: nextSymbol,
      name: type.isMarketLinked && nextQuote != ticker ? '' : null,
      currency: value.currency,
      clearLastPrice: true,
    );
  }

  /// Live estimate of the asset's value in its own currency.
  double get estimatedValue {
    switch (type.valuationMode) {
      case ValuationMode.market:
        return (double.tryParse(quantity) ?? 0.0) * (lastPrice ?? 0.0);
      case ValuationMode.metal:
        return useTotalValue
            ? (double.tryParse(manualValue) ?? 0.0)
            : (double.tryParse(quantity) ?? 0.0) * (metalRate ?? 0.0);
      case ValuationMode.quantity:
        return (double.tryParse(quantity) ?? 0.0) *
            (double.tryParse(pricePerUnit) ?? 0.0);
      case ValuationMode.flat:
        return double.tryParse(manualValue) ?? 0.0;
    }
  }

  bool get hasPrecisionLoss => switch (type.valuationMode) {
    ValuationMode.market => losesInputPrecision(quantity),
    ValuationMode.quantity =>
      losesInputPrecision(quantity) || losesInputPrecision(pricePerUnit),
    ValuationMode.metal =>
      useTotalValue
          ? losesInputPrecision(manualValue)
          : losesInputPrecision(quantity) ||
                (customPrice && losesInputPrecision(pricePerUnit)),
    ValuationMode.flat => losesInputPrecision(manualValue),
  };

  /// Returns the first validation error, or null when the form can be saved.
  String? validate() {
    if (!type.isMarketLinked && name.trim().isEmpty) {
      return 'Give this asset a name';
    }
    if (currency.trim().isEmpty) return 'Choose a currency';
    if (hasPrecisionLoss) return numberPrecisionError;
    switch (type.valuationMode) {
      case ValuationMode.market:
        if (quoteSymbol.isEmpty) return 'Enter a ticker symbol';
        if (!isValidTickerSymbol(
          quoteSymbol,
          isCrypto: type == AssetType.crypto,
        )) {
          return 'Enter a valid ticker symbol';
        }
        if (!_isPositiveNumber(quantity)) {
          return 'Enter a quantity';
        }
        return null;
      case ValuationMode.quantity:
        if (!_isPositiveNumber(quantity)) {
          return 'Enter a quantity';
        }
        if (!_isPositiveNumber(pricePerUnit)) {
          return 'Enter a price per unit';
        }
        return null;
      case ValuationMode.metal:
        if (metal == null) return 'Choose a precious item';
        if (useTotalValue) {
          return !isPositiveDecimal(manualValue) || !estimatedValue.isFinite
              ? 'Enter a positive total value'
              : null;
        }
        if (metal!.hasPurity && metal!.grades[purity] == null) {
          return 'Choose a purity';
        }
        if (!_isPositiveNumber(quantity) || !estimatedValue.isFinite) {
          return 'Enter a positive weight';
        }
        if (customPrice
            ? !isPositiveDecimal(pricePerUnit)
            : metalRate == null || !metalRate!.isFinite || metalRate! <= 0) {
          return 'Enter a positive price per gram';
        }
        return null;
      case ValuationMode.flat:
        final double? parsed = double.tryParse(manualValue);
        return parsed == null || !parsed.isFinite ? 'Enter a value' : null;
    }
  }

  /// Mirrors the Android editor: both timestamps are stamped with the current
  /// time, and the repository re-stamps [updatedAt] when saving.
  AssetEntity toEntity({int? now}) {
    final int timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final String ticker = quoteSymbol;
    final String trimmedName = name.trim();
    final String trimmedCustom = customName.trim();
    final String persistedName = type.isMarketLinked
        ? (trimmedName.isNotEmpty ? trimmedName : ticker)
        : trimmedName;
    return AssetEntity(
      id: id,
      position: position,
      portfolioId: portfolioId,
      type: type,
      name: persistedName,
      customName: type.isMarketLinked && trimmedCustom.isNotEmpty
          ? trimmedCustom
          : null,
      currency: currency.trim().toUpperCase(),
      quantity: _finiteInput(quantity),
      pricePerUnit:
          valuationMode == ValuationMode.quantity ||
              valuationMode == ValuationMode.metal
          ? _finiteInput(pricePerUnit)
          : null,
      metal: type == AssetType.metals ? metal : null,
      purity: type == AssetType.metals ? purity : null,
      customPrice: type == AssetType.metals && customPrice,
      useTotalValue: type == AssetType.metals && useTotalValue,
      symbol: type.isMarketLinked && ticker.isNotEmpty ? ticker : null,
      lastPrice: lastPrice,
      lastPriceTimestamp: lastPriceTimestamp,
      manualValue: _finiteInput(manualValue),
      notes: notes.trim().isEmpty ? null : notes.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static AssetFormState fromEntity(AssetEntity asset) => AssetFormState(
    id: asset.id,
    position: asset.position,
    portfolioId: asset.portfolioId,
    type: asset.type,
    metal: asset.metal,
    purity: asset.purity,
    customPrice: asset.customPrice,
    useTotalValue: asset.useTotalValue,
    name: asset.name,
    customName: asset.customName ?? '',
    currency: asset.currency,
    quantity: asset.quantity == null ? '' : formatInput(asset.quantity!),
    pricePerUnit: asset.type == AssetType.metals && !asset.customPrice
        ? asset.lastPrice == null
              ? ''
              : formatInput(asset.lastPrice!)
        : asset.pricePerUnit == null
        ? ''
        : formatInput(asset.pricePerUnit!),
    symbol: asset.symbol ?? '',
    exchange: StockExchange.fromSymbol(asset.symbol ?? ''),
    manualValue: asset.manualValue == null
        ? ''
        : formatInput(asset.manualValue!),
    lastPrice: asset.lastPrice,
    lastPriceTimestamp: asset.lastPriceTimestamp,
    notes: asset.notes ?? '',
    loading: false,
  );

  AssetFormState copyWith({
    int? id,
    int? portfolioId,
    AssetType? type,
    String? name,
    String? customName,
    String? currency,
    String? quantity,
    String? pricePerUnit,
    PreciousMetal? metal,
    String? purity,
    bool clearMetal = false,
    bool clearPurity = false,
    bool? customPrice,
    bool? useTotalValue,
    String? symbol,
    StockExchange? exchange,
    String? manualValue,
    double? lastPrice,
    int? lastPriceTimestamp,
    bool clearLastPrice = false,
    String? notes,
    bool? loading,
    bool? isFetchingPrice,
    bool? isSaving,
  }) {
    return AssetFormState(
      id: id ?? this.id,
      position: position,
      portfolioId: portfolioId ?? this.portfolioId,
      type: type ?? this.type,
      name: name ?? this.name,
      customName: customName ?? this.customName,
      currency: currency ?? this.currency,
      quantity: quantity ?? this.quantity,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      metal: clearMetal ? null : metal ?? this.metal,
      purity: clearMetal || clearPurity ? null : purity ?? this.purity,
      customPrice: customPrice ?? this.customPrice,
      useTotalValue: useTotalValue ?? this.useTotalValue,
      symbol: symbol ?? this.symbol,
      exchange: exchange ?? this.exchange,
      manualValue: manualValue ?? this.manualValue,
      lastPrice: clearLastPrice ? null : (lastPrice ?? this.lastPrice),
      lastPriceTimestamp: clearLastPrice
          ? null
          : (lastPriceTimestamp ?? this.lastPriceTimestamp),
      notes: notes ?? this.notes,
      loading: loading ?? this.loading,
      isFetchingPrice: isFetchingPrice ?? this.isFetchingPrice,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

/// Keeps digits and at most one decimal point, like the Compose form did.
String filterDecimal(String input) {
  final StringBuffer buffer = StringBuffer();
  bool seenDot = false;
  for (int i = 0; i < input.length; i++) {
    final int unit = input.codeUnitAt(i);
    if (unit >= 0x30 && unit <= 0x39) {
      buffer.writeCharCode(unit);
    } else if (unit == 0x2E && !seenDot) {
      buffer.writeCharCode(unit);
      seenDot = true;
    }
  }
  return buffer.toString();
}

/// Renders a stored double back into the text field, dropping a trailing `.0`.
String formatInput(double value) => formatPlainDecimal(value);

const String numberPrecisionError =
    'This number can’t be saved exactly. Enter fewer digits.';

final RegExp _inputDecimal = RegExp(r'^-?(?:\d+(?:\.\d*)?|\.\d+)$');
final RegExp _leadingZeros = RegExp(r'^0+(?=\d)');
final RegExp _trailingZeros = RegExp(r'0+$');

/// Compare decimal text on both sides so a double rounding to a different
/// value (for example sixteen nines rounding to 10^16) is not saved silently.
bool losesInputPrecision(String input) {
  final String trimmed = input.trim();
  if (!_inputDecimal.hasMatch(trimmed)) return false;
  final double value = double.parse(trimmed);
  if (!value.isFinite) return true;
  final List<String> parts = trimmed.split('.');
  final bool negative = trimmed.startsWith('-');
  final String whole = (negative ? parts.first.substring(1) : parts.first)
      .replaceFirst(_leadingZeros, '');
  final String fraction = parts.length == 2
      ? parts.last.replaceFirst(_trailingZeros, '')
      : '';
  final String digits =
      '${whole.isEmpty ? '0' : whole}'
      '${fraction.isEmpty ? '' : '.$fraction'}';
  final String normalized = negative && digits != '0' ? '-$digits' : digits;
  if (normalized != formatInput(value)) return true;
  // A double's shortest decimal can hide rounding of a large integer.
  return fraction.isEmpty &&
      value.abs() >= 9007199254740992.0 &&
      BigInt.parse(normalized) != BigInt.from(value);
}

bool _isPositiveNumber(String raw) {
  final double? parsed = double.tryParse(raw.trim());
  return parsed != null && parsed.isFinite && parsed > 0.0;
}

double? _finiteInput(String raw) {
  final value = double.tryParse(raw);
  return value != null && value.isFinite ? value : null;
}

bool isPositiveDecimal(String raw) =>
    RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(raw) &&
    _isPositiveNumber(raw);

final RegExp _disallowedMarketQueryChars = RegExp(
  r'[^\p{L}\p{N}\s.&/\-]',
  unicode: true,
);
final RegExp _stockTickerPattern = RegExp(
  r'^[A-Z0-9]{1,12}([.-][A-Z0-9]{1,6}){0,2}$',
);
final RegExp _cryptoTickerPattern = RegExp(
  r'^[A-Z0-9]{1,12}(-[A-Z0-9]{2,6})?$',
);

/// Strips non-company/non-ticker punctuation from market search queries while
/// keeping letters, digits, spaces, and standard listing separators (`. - & /`).
String sanitizeMarketQuery(String input) =>
    input.replaceAll(_disallowedMarketQueryChars, '');

/// Checks whether [value] is a syntactically valid Yahoo Finance ticker symbol.
bool isValidTickerSymbol(String value, {bool isCrypto = false}) {
  final String cleaned = value.trim().toUpperCase();
  if (cleaned.isEmpty || cleaned.length > 24) return false;
  return isCrypto
      ? _cryptoTickerPattern.hasMatch(cleaned)
      : _stockTickerPattern.hasMatch(cleaned);
}
