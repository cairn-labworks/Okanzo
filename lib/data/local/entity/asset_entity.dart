import '../../../domain/model/asset_type.dart';

/// A single holding inside a portfolio.
class AssetEntity {
  const AssetEntity({
    this.id = 0,
    required this.portfolioId,
    required this.type,
    required this.name,
    this.customName,
    required this.currency,
    this.quantity,
    this.pricePerUnit,
    this.symbol,
    this.lastPrice,
    this.lastPriceTimestamp,
    this.manualValue,
    this.notes,
    this.position = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AssetEntity.fromMap(Map<String, Object?> map) => AssetEntity(
    id: map['id'] as int,
    portfolioId: map['portfolioId'] as int,
    type: AssetType.fromName(map['type'] as String?),
    name: map['name'] as String,
    customName: _nonEmptyText(map['customName']),
    currency: map['currency'] as String,
    quantity: (map['quantity'] as num?)?.toDouble(),
    pricePerUnit: (map['pricePerUnit'] as num?)?.toDouble(),
    symbol: map['symbol'] as String?,
    lastPrice: (map['lastPrice'] as num?)?.toDouble(),
    lastPriceTimestamp: map['lastPriceTimestamp'] as int?,
    manualValue: (map['manualValue'] as num?)?.toDouble(),
    notes: map['notes'] as String?,
    position: map['position'] as int? ?? 0,
    createdAt: map['createdAt'] as int,
    updatedAt: map['updatedAt'] as int,
  );

  final int id;
  final int portfolioId;
  final AssetType type;
  final String name;

  /// Optional user-provided display label for market-linked holdings.
  final String? customName;
  final String currency;

  /// Units held (shares, coins, grams). Used by market and quantity valuation.
  final double? quantity;

  /// Manually entered price per unit (e.g. gold). Used by quantity valuation.
  final double? pricePerUnit;

  /// Ticker / market symbol (e.g. AAPL, BTC-USD). Used by market valuation.
  final String? symbol;

  /// Last fetched market price per unit, in [currency].
  final double? lastPrice;

  /// Epoch millis when [lastPrice] was fetched.
  final int? lastPriceTimestamp;

  /// Flat total value (e.g. cash, property). Used by flat valuation.
  final double? manualValue;
  final String? notes;

  /// User-defined sort order within this asset's type. Lower shows first.
  final int position;
  final int createdAt;
  final int updatedAt;

  /// Name shown in lists: [customName] overrides [name] when set.
  String get displayName {
    final String? custom = _nonEmptyText(customName);
    if (custom != null) return custom;
    final String? base = _nonEmptyText(name);
    if (base != null) return base;
    return symbol?.trim().toUpperCase() ?? '';
  }

  /// The asset's total value expressed in its own [currency].
  double get value {
    switch (type.valuationMode) {
      case ValuationMode.market:
        return (quantity ?? 0.0) * (lastPrice ?? 0.0);
      case ValuationMode.quantity:
        return (quantity ?? 0.0) * (pricePerUnit ?? 0.0);
      case ValuationMode.flat:
        return manualValue ?? 0.0;
    }
  }

  Map<String, Object?> toMap({bool includeId = true}) => <String, Object?>{
    if (includeId && id != 0) 'id': id,
    'portfolioId': portfolioId,
    'type': type.storageName,
    'name': name,
    'customName': customName,
    'currency': currency,
    'quantity': quantity,
    'pricePerUnit': pricePerUnit,
    'symbol': symbol,
    'lastPrice': lastPrice,
    'lastPriceTimestamp': lastPriceTimestamp,
    'manualValue': manualValue,
    'notes': notes,
    'position': position,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  AssetEntity copyWith({
    int? id,
    int? portfolioId,
    AssetType? type,
    String? name,
    String? customName,
    bool clearCustomName = false,
    String? currency,
    double? quantity,
    double? pricePerUnit,
    String? symbol,
    double? lastPrice,
    int? lastPriceTimestamp,
    double? manualValue,
    String? notes,
    int? position,
    int? createdAt,
    int? updatedAt,
  }) => AssetEntity(
    id: id ?? this.id,
    portfolioId: portfolioId ?? this.portfolioId,
    type: type ?? this.type,
    name: name ?? this.name,
    customName: clearCustomName ? null : (customName ?? this.customName),
    currency: currency ?? this.currency,
    quantity: quantity ?? this.quantity,
    pricePerUnit: pricePerUnit ?? this.pricePerUnit,
    symbol: symbol ?? this.symbol,
    lastPrice: lastPrice ?? this.lastPrice,
    lastPriceTimestamp: lastPriceTimestamp ?? this.lastPriceTimestamp,
    manualValue: manualValue ?? this.manualValue,
    notes: notes ?? this.notes,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static String? _nonEmptyText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
