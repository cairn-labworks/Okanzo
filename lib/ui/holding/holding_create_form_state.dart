import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/holding_type.dart';
import '../../domain/model/stock_exchange.dart';

/// Pure form state for creating an entry whose asset vs. liability
/// classification is automatically derived from [holdingType].
class HoldingCreateFormState {
  const HoldingCreateFormState({
    this.portfolioId = 0,
    this.holdingType = const HoldingType.asset(AssetType.stock),
    this.name = '',
    this.currency = 'USD',
    this.quantity = '',
    this.pricePerUnit = '',
    this.symbol = '',
    this.exchange = StockExchange.us,
    this.flatAmount = '',
    this.lastPrice,
    this.lastPriceTimestamp,
    this.notes = '',
    this.loading = true,
    this.isFetchingPrice = false,
    this.isSaving = false,
  });

  final int portfolioId;
  final HoldingType holdingType;
  final String name;
  final String currency;
  final String quantity;
  final String pricePerUnit;
  final String symbol;
  final StockExchange exchange;

  /// Shared numeric input for flat-valued assets (`Value`) and liabilities
  /// (`Outstanding amount`) so switching between them preserves entered figures.
  final String flatAmount;
  final double? lastPrice;
  final int? lastPriceTimestamp;
  final String notes;
  final bool loading;
  final bool isFetchingPrice;
  final bool isSaving;

  HoldingKind get detectedKind => holdingType.kind;

  bool get isAsset => holdingType.isAsset;

  bool get isLiability => holdingType.isLiability;

  ValuationMode? get assetValuationMode => holdingType.assetType?.valuationMode;

  bool get isMarketLinked => assetValuationMode == ValuationMode.market;

  bool get usesStockExchange =>
      holdingType.assetType == AssetType.stock ||
      holdingType.assetType == AssetType.mutualFund;

  String get quoteSymbol => usesStockExchange
      ? exchange.qualify(symbol)
      : symbol.trim().toUpperCase();

  HoldingCreateFormState withSymbol(String value) {
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

  HoldingCreateFormState withExchange(StockExchange value) {
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

  double get estimatedValue {
    switch (assetValuationMode) {
      case ValuationMode.market:
        return (double.tryParse(quantity) ?? 0.0) * (lastPrice ?? 0.0);
      case ValuationMode.quantity:
        return (double.tryParse(quantity) ?? 0.0) *
            (double.tryParse(pricePerUnit) ?? 0.0);
      case ValuationMode.flat:
      case null:
        return double.tryParse(flatAmount) ?? 0.0;
    }
  }

  String? validate() {
    if (isLiability) {
      if (name.trim().isEmpty) return 'Give this liability a name';
      if (currency.trim().isEmpty) return 'Choose a currency';
      if (double.tryParse(flatAmount) == null) return 'Enter an amount';
      return null;
    }
    if (name.trim().isEmpty) return 'Give this asset a name';
    if (currency.trim().isEmpty) return 'Choose a currency';
    switch (assetValuationMode!) {
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
        return double.tryParse(flatAmount) == null ? 'Enter a value' : null;
    }
  }

  AssetEntity toAssetEntity({int? now}) {
    final AssetType type = holdingType.assetType!;
    final int timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final String ticker = quoteSymbol;
    return AssetEntity(
      portfolioId: portfolioId,
      type: type,
      name: name.trim(),
      currency: currency.trim().toUpperCase(),
      quantity: double.tryParse(quantity),
      pricePerUnit: double.tryParse(pricePerUnit),
      symbol: ticker.isEmpty ? null : ticker,
      lastPrice: lastPrice,
      lastPriceTimestamp: lastPriceTimestamp,
      manualValue: double.tryParse(flatAmount),
      notes: notes.trim().isEmpty ? null : notes.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  LiabilityEntity toLiabilityEntity({int? now}) {
    final int timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    return LiabilityEntity(
      portfolioId: portfolioId,
      type: holdingType.liabilityType!,
      name: name.trim(),
      currency: currency.trim().toUpperCase(),
      amount: double.tryParse(flatAmount) ?? 0.0,
      notes: notes.trim().isEmpty ? null : notes.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  HoldingCreateFormState copyWith({
    int? portfolioId,
    HoldingType? holdingType,
    String? name,
    String? currency,
    String? quantity,
    String? pricePerUnit,
    String? symbol,
    StockExchange? exchange,
    String? flatAmount,
    double? lastPrice,
    int? lastPriceTimestamp,
    bool clearLastPrice = false,
    String? notes,
    bool? loading,
    bool? isFetchingPrice,
    bool? isSaving,
  }) {
    return HoldingCreateFormState(
      portfolioId: portfolioId ?? this.portfolioId,
      holdingType: holdingType ?? this.holdingType,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      quantity: quantity ?? this.quantity,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      symbol: symbol ?? this.symbol,
      exchange: exchange ?? this.exchange,
      flatAmount: flatAmount ?? this.flatAmount,
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
