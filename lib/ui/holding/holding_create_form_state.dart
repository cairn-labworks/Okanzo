import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/holding_type.dart';
import '../../domain/model/precious_metal.dart';
import '../../domain/model/stock_exchange.dart';
import '../asset/asset_form_state.dart'
    show isPositiveDecimal, isValidTickerSymbol;

/// Pure form state for creating an entry whose asset vs. liability
/// classification is automatically derived from [holdingType].
class HoldingCreateFormState {
  const HoldingCreateFormState({
    this.portfolioId = 0,
    this.holdingType = const HoldingType.asset(AssetType.stock),
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
    this.flatAmount = '',
    this.lastPrice,
    this.lastPriceTimestamp,
    this.notes = '',
    this.loading = true,
    this.isFetchingPrice = false,
    this.isPreparingSave = false,
    this.isPersisting = false,
  });

  final int portfolioId;
  final HoldingType holdingType;
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

  /// Shared numeric input for flat-valued assets (`Value`), total-valued
  /// precious items (`Total value`), and liabilities (`Outstanding amount`) so
  /// switching between them preserves entered figures.
  final String flatAmount;
  final double? lastPrice;
  final int? lastPriceTimestamp;
  final String notes;
  final bool loading;
  final bool isFetchingPrice;

  /// True while `save()` is awaiting an automatic pre-save quote lookup before
  /// anything is written to the database. Inline Cancel remains enabled.
  final bool isPreparingSave;

  /// True while a repository insert is in progress. Input changes, Cancel, and
  /// Back navigation are locked until the write finishes.
  final bool isPersisting;

  bool get isSaving => isPreparingSave || isPersisting;

  HoldingKind get detectedKind => holdingType.kind;

  bool get isAsset => holdingType.isAsset;

  bool get isLiability => holdingType.isLiability;

  ValuationMode? get assetValuationMode => holdingType.assetType?.valuationMode;

  bool get isMarketLinked => assetValuationMode == ValuationMode.market;

  bool get usesStockExchange =>
      holdingType.assetType == AssetType.stock ||
      holdingType.assetType == AssetType.mutualFund;

  double? get metalRate =>
      customPrice ? double.tryParse(pricePerUnit) : lastPrice;

  String get quoteSymbol => usesStockExchange
      ? exchange.qualify(symbol)
      : symbol.trim().toUpperCase();

  HoldingCreateFormState withSymbol(String value) {
    final StockExchange next = usesStockExchange && value.contains('.')
        ? StockExchange.fromSymbol(value)
        : exchange;
    final String nextQuote = usesStockExchange
        ? next.qualify(value)
        : value.trim().toUpperCase();
    return copyWith(
      symbol: value,
      exchange: next,
      name: isMarketLinked && nextQuote != quoteSymbol ? '' : null,
      currency: next != exchange ? next.currency : null,
      clearLastPrice: true,
    );
  }

  HoldingCreateFormState withExchange(StockExchange value) {
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
      name: isMarketLinked && nextQuote != ticker ? '' : null,
      currency: value.currency,
      clearLastPrice: true,
    );
  }

  double get estimatedValue {
    switch (assetValuationMode) {
      case ValuationMode.market:
        return (double.tryParse(quantity) ?? 0.0) * (lastPrice ?? 0.0);
      case ValuationMode.metal:
        return useTotalValue
            ? (double.tryParse(flatAmount) ?? 0.0)
            : (double.tryParse(quantity) ?? 0.0) * (metalRate ?? 0.0);
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
      final double? parsed = double.tryParse(flatAmount);
      if (parsed == null || !parsed.isFinite) return 'Enter an amount';
      return null;
    }
    final AssetType assetType = holdingType.assetType!;
    if (!assetType.isMarketLinked && name.trim().isEmpty) {
      return 'Give this asset a name';
    }
    if (currency.trim().isEmpty) return 'Choose a currency';
    switch (assetType.valuationMode) {
      case ValuationMode.market:
        if (quoteSymbol.isEmpty) return 'Enter a ticker symbol';
        if (!isValidTickerSymbol(
          quoteSymbol,
          isCrypto: assetType == AssetType.crypto,
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
          return !isPositiveDecimal(flatAmount) || !estimatedValue.isFinite
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
        final double? parsed = double.tryParse(flatAmount);
        return parsed == null || !parsed.isFinite ? 'Enter a value' : null;
    }
  }

  bool hasUnsavedChangesFrom(HoldingCreateFormState initial) =>
      holdingType != initial.holdingType ||
      name.trim() != initial.name.trim() ||
      customName.trim() != initial.customName.trim() ||
      currency != initial.currency ||
      quantity.trim() != initial.quantity.trim() ||
      pricePerUnit.trim() != initial.pricePerUnit.trim() ||
      metal != initial.metal ||
      purity != initial.purity ||
      customPrice != initial.customPrice ||
      useTotalValue != initial.useTotalValue ||
      symbol.trim() != initial.symbol.trim() ||
      exchange != initial.exchange ||
      flatAmount.trim() != initial.flatAmount.trim() ||
      notes.trim() != initial.notes.trim();

  AssetEntity toAssetEntity({int? now}) {
    final AssetType type = holdingType.assetType!;
    final int timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final String ticker = quoteSymbol;
    final String trimmedName = name.trim();
    final String trimmedCustom = customName.trim();
    final String persistedName = type.isMarketLinked
        ? (trimmedName.isNotEmpty ? trimmedName : ticker)
        : trimmedName;
    return AssetEntity(
      portfolioId: portfolioId,
      type: type,
      name: persistedName,
      customName: type.isMarketLinked && trimmedCustom.isNotEmpty
          ? trimmedCustom
          : null,
      currency: currency.trim().toUpperCase(),
      quantity: _finiteInput(quantity),
      pricePerUnit:
          type.valuationMode == ValuationMode.quantity ||
              type.valuationMode == ValuationMode.metal
          ? _finiteInput(pricePerUnit)
          : null,
      metal: type == AssetType.metals ? metal : null,
      purity: type == AssetType.metals ? purity : null,
      customPrice: type == AssetType.metals && customPrice,
      useTotalValue: type == AssetType.metals && useTotalValue,
      symbol: type.isMarketLinked && ticker.isNotEmpty ? ticker : null,
      lastPrice: lastPrice,
      lastPriceTimestamp: lastPriceTimestamp,
      manualValue: _finiteInput(flatAmount),
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
      amount: _finiteInput(flatAmount) ?? 0.0,
      notes: notes.trim().isEmpty ? null : notes.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  HoldingCreateFormState copyWith({
    int? portfolioId,
    HoldingType? holdingType,
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
    String? flatAmount,
    double? lastPrice,
    int? lastPriceTimestamp,
    bool clearLastPrice = false,
    String? notes,
    bool? loading,
    bool? isFetchingPrice,
    bool? isPreparingSave,
    bool? isPersisting,
  }) {
    return HoldingCreateFormState(
      portfolioId: portfolioId ?? this.portfolioId,
      holdingType: holdingType ?? this.holdingType,
      name: name ?? this.name,
      customName: customName ?? this.customName,
      currency: currency ?? this.currency,
      quantity: quantity ?? this.quantity,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      metal: clearMetal ? null : (metal ?? this.metal),
      purity: clearMetal || clearPurity ? null : (purity ?? this.purity),
      customPrice: customPrice ?? this.customPrice,
      useTotalValue: useTotalValue ?? this.useTotalValue,
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
      isPreparingSave: isPreparingSave ?? this.isPreparingSave,
      isPersisting: isPersisting ?? this.isPersisting,
    );
  }
}

bool _isPositiveNumber(String raw) {
  final double? parsed = double.tryParse(raw.trim());
  return parsed != null && parsed.isFinite && parsed > 0.0;
}

double? _finiteInput(String raw) {
  final double? value = double.tryParse(raw);
  return value != null && value.isFinite ? value : null;
}
