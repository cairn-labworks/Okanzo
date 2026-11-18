/// Serializable snapshot of one or more portfolios for encrypted export/import.
///
/// The JSON shape is byte-compatible with the Android app's Gson output: fields
/// appear in declaration order and null fields are omitted entirely.
class BackupFile {
  const BackupFile({
    this.schema = currentSchema,
    this.app = 'Okanzo',
    required this.exportedAt,
    required this.portfolios,
  });

  factory BackupFile.fromJson(Map<String, Object?> json) => BackupFile(
    schema: (json['schema'] as num?)?.toInt() ?? 0,
    app: json['app'] as String? ?? '',
    exportedAt: (json['exportedAt'] as num?)?.toInt() ?? 0,
    portfolios: (json['portfolios'] as List<Object?>?)
        ?.whereType<Map<String, Object?>>()
        .map(BackupPortfolio.fromJson)
        .toList(growable: false),
  );

  static const int currentSchema = 1;

  final int schema;
  final String app;
  final int exportedAt;
  final List<BackupPortfolio>? portfolios;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'app': app,
    'exportedAt': exportedAt,
    if (portfolios != null)
      'portfolios': <Object?>[
        for (final BackupPortfolio portfolio in portfolios!) portfolio.toJson(),
      ],
  };
}

class BackupPortfolio {
  const BackupPortfolio({
    required this.name,
    required this.isDefault,
    required this.assets,
    required this.liabilities,
  });

  factory BackupPortfolio.fromJson(Map<String, Object?> json) =>
      BackupPortfolio(
        name: json['name'] as String? ?? '',
        isDefault: json['isDefault'] as bool? ?? false,
        assets: (json['assets'] as List<Object?>?)
            ?.whereType<Map<String, Object?>>()
            .map(BackupAsset.fromJson)
            .toList(growable: false),
        liabilities: (json['liabilities'] as List<Object?>?)
            ?.whereType<Map<String, Object?>>()
            .map(BackupLiability.fromJson)
            .toList(growable: false),
      );

  final String name;
  final bool isDefault;
  final List<BackupAsset>? assets;
  final List<BackupLiability>? liabilities;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'isDefault': isDefault,
    if (assets != null)
      'assets': <Object?>[
        for (final BackupAsset asset in assets!) asset.toJson(),
      ],
    if (liabilities != null)
      'liabilities': <Object?>[
        for (final BackupLiability liability in liabilities!)
          liability.toJson(),
      ],
  };
}

class BackupAsset {
  const BackupAsset({
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
  });

  factory BackupAsset.fromJson(Map<String, Object?> json) => BackupAsset(
    type: json['type'] as String? ?? '',
    name: json['name'] as String? ?? '',
    customName: _nonEmptyText(json['customName']),
    currency: json['currency'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toDouble(),
    pricePerUnit: (json['pricePerUnit'] as num?)?.toDouble(),
    symbol: json['symbol'] as String?,
    lastPrice: (json['lastPrice'] as num?)?.toDouble(),
    lastPriceTimestamp: (json['lastPriceTimestamp'] as num?)?.toInt(),
    manualValue: (json['manualValue'] as num?)?.toDouble(),
    notes: json['notes'] as String?,
    position: (json['position'] as num?)?.toInt() ?? 0,
  );

  final String type;
  final String name;
  final String? customName;
  final String currency;
  final double? quantity;
  final double? pricePerUnit;
  final String? symbol;
  final double? lastPrice;
  final int? lastPriceTimestamp;
  final double? manualValue;
  final String? notes;
  final int position;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'name': name,
    if (customName != null) 'customName': customName,
    'currency': currency,
    if (quantity != null) 'quantity': quantity,
    if (pricePerUnit != null) 'pricePerUnit': pricePerUnit,
    if (symbol != null) 'symbol': symbol,
    if (lastPrice != null) 'lastPrice': lastPrice,
    if (lastPriceTimestamp != null) 'lastPriceTimestamp': lastPriceTimestamp,
    if (manualValue != null) 'manualValue': manualValue,
    if (notes != null) 'notes': notes,
    'position': position,
  };

  static String? _nonEmptyText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

class BackupLiability {
  const BackupLiability({
    required this.type,
    required this.name,
    required this.currency,
    required this.amount,
    this.notes,
    this.position = 0,
  });

  factory BackupLiability.fromJson(Map<String, Object?> json) =>
      BackupLiability(
        type: json['type'] as String? ?? '',
        name: json['name'] as String? ?? '',
        currency: json['currency'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        notes: json['notes'] as String?,
        position: (json['position'] as num?)?.toInt() ?? 0,
      );

  final String type;
  final String name;
  final String currency;
  final double amount;
  final String? notes;
  final int position;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'name': name,
    'currency': currency,
    'amount': amount,
    if (notes != null) 'notes': notes,
    'position': position,
  };
}

/// Counts of everything created by an import.
class ImportResult {
  const ImportResult({
    required this.portfolios,
    required this.assets,
    required this.liabilities,
  });

  final int portfolios;
  final int assets;
  final int liabilities;
}
