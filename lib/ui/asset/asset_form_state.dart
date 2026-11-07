import '../../data/local/entity/asset_entity.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/stock_exchange.dart';

/// Editable state of the asset form. Pure data + validation so it can be
/// unit-tested without a widget tree.
class AssetFormState {
  const AssetFormState({
    this.id = 0,
    this.portfolioId = 0,
    this.type = AssetType.stock,
    this.name = '',
    this.currency = 'USD',
    this.quantity = '',
    this.pricePerUnit = '',
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
  final int portfolioId;
  final AssetType type;
  final String name;
  final String currency;
  final String quantity;
  final String pricePerUnit;
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

  String get quoteSymbol => usesStockExchange
      ? exchange.qualify(symbol)
      : symbol.trim().toUpperCase();

  AssetFormState withSymbol(String value) {
    final StockExchange next = usesStockExchange && value.contains('.')
        ? StockExchange.fromSymbol(value)
        : exchange;
    return copyWith(
      symbol: value,
      exchange: next,
      currency: next != exchange ? next.currency : null,
      clearLastPrice: true,
    );
  }

  AssetFormState withExchange(StockExchange value) {
    if (value == exchange) return this;
    final String ticker = quoteSymbol;
    final int separator = ticker.lastIndexOf('.');
    return copyWith(
      exchange: value,
      symbol: value == StockExchange.other || separator < 0
          ? ticker
          : ticker.substring(0, separator),
      currency: value.currency,
      clearLastPrice: true,
    );
  }

  /// Live estimate of the asset's value in its own currency.
  double get estimatedValue {
    switch (type.valuationMode) {
      case ValuationMode.market:
        return (double.tryParse(quantity) ?? 0.0) * (lastPrice ?? 0.0);
      case ValuationMode.quantity:
        return (double.tryParse(quantity) ?? 0.0) *
            (double.tryParse(pricePerUnit) ?? 0.0);
      case ValuationMode.flat:
        return double.tryParse(manualValue) ?? 0.0;
    }
  }

  /// Returns the first validation error, or null when the form can be saved.
  String? validate() {
    if (name.trim().isEmpty) return 'Give this asset a name';
    if (currency.trim().isEmpty) return 'Choose a currency';
    switch (type.valuationMode) {
      case ValuationMode.market:
        if (symbol.trim().isEmpty) return 'Enter a ticker symbol';
        if ((double.tryParse(quantity) ?? 0.0) <= 0.0) {
          return 'Enter a quantity';
        }
        return null;
      case ValuationMode.quantity:
        if ((double.tryParse(quantity) ?? 0.0) <= 0.0) {
          return 'Enter a quantity';
        }
        if ((double.tryParse(pricePerUnit) ?? 0.0) <= 0.0) {
          return 'Enter a price per unit';
        }
        return null;
      case ValuationMode.flat:
        return double.tryParse(manualValue) == null ? 'Enter a value' : null;
    }
  }

  /// Mirrors the Android editor: both timestamps are stamped with the current
  /// time, and the repository re-stamps [updatedAt] when saving.
  AssetEntity toEntity({int? now}) {
    final int timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final String ticker = quoteSymbol;
    return AssetEntity(
      id: id,
      portfolioId: portfolioId,
      type: type,
      name: name.trim(),
      currency: currency.trim().toUpperCase(),
      quantity: double.tryParse(quantity),
      pricePerUnit: double.tryParse(pricePerUnit),
      symbol: ticker.isEmpty ? null : ticker,
      lastPrice: lastPrice,
      lastPriceTimestamp: lastPriceTimestamp,
      manualValue: double.tryParse(manualValue),
      notes: notes.trim().isEmpty ? null : notes.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static AssetFormState fromEntity(AssetEntity asset) => AssetFormState(
    id: asset.id,
    portfolioId: asset.portfolioId,
    type: asset.type,
    name: asset.name,
    currency: asset.currency,
    quantity: asset.quantity == null ? '' : formatInput(asset.quantity!),
    pricePerUnit: asset.pricePerUnit == null
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
    String? currency,
    String? quantity,
    String? pricePerUnit,
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
      portfolioId: portfolioId ?? this.portfolioId,
      type: type ?? this.type,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      quantity: quantity ?? this.quantity,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
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
String formatInput(double value) =>
    value % 1.0 == 0.0 ? value.truncate().toString() : value.toString();
