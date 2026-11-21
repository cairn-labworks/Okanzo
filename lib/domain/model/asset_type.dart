/// How an asset's total value is derived from its stored fields.
enum ValuationMode {
  /// value = quantity * last fetched market price (e.g. stocks, crypto).
  market,

  /// value = quantity * a manually entered price per unit (e.g. gold grams).
  quantity,

  /// Grams multiplied by an indicative market rate adjusted for purity.
  metal,

  /// value = a single, manually entered total amount (e.g. cash, property).
  flat,
}

/// The category of an asset. Each type maps to a [ValuationMode] which drives the
/// input fields shown in the editor and how the total value is computed.
enum AssetType {
  stock('STOCK', 'Stock', ValuationMode.market),
  mutualFund('MUTUAL_FUND', 'Mutual fund / ETF', ValuationMode.market),
  crypto('CRYPTO', 'Cryptocurrency', ValuationMode.market),
  gold('GOLD', 'Gold', ValuationMode.quantity, unitLabel: 'g'),
  metals('METALS', 'Valuables', ValuationMode.metal, unitLabel: 'g'),
  cash('CASH', 'Cash', ValuationMode.flat),
  bankDeposit('BANK_DEPOSIT', 'Bank / deposit', ValuationMode.flat),
  realEstate('REAL_ESTATE', 'Real estate', ValuationMode.flat),
  vehicle('VEHICLE', 'Vehicle', ValuationMode.flat),
  bond('BOND', 'Bond', ValuationMode.flat),
  other('OTHER', 'Other', ValuationMode.flat);

  const AssetType(
    this.storageName,
    this.displayName,
    this.valuationMode, {
    this.unitLabel,
  });

  /// Name persisted in the database and in backups; kept identical to the
  /// Kotlin enum constants so existing data and backups stay readable.
  final String storageName;
  final String displayName;
  final ValuationMode valuationMode;

  /// Optional hint for the unit used in [ValuationMode.quantity] types.
  final String? unitLabel;

  bool get isMarketLinked => valuationMode == ValuationMode.market;

  bool get requiresQuote => isMarketLinked || this == AssetType.metals;

  AssetType get displayCategory => this == AssetType.gold ? metals : this;

  /// Short category hint shown beneath the label in selection pickers.
  String get pickerHint => switch (this) {
    AssetType.stock => 'Company shares',
    AssetType.mutualFund => 'Funds and indexes',
    AssetType.crypto => 'Coins and tokens',
    AssetType.gold => 'Weight in grams',
    AssetType.metals => 'Gold, silver, gemstones and jewellery',
    AssetType.cash => 'Money on hand',
    AssetType.bankDeposit => 'Savings and deposits',
    AssetType.realEstate => 'Property value',
    AssetType.vehicle => 'Current resale value',
    AssetType.bond => 'Current holding value',
    AssetType.other => 'Something else you own',
  };

  /// Contextual example name placeholder for this asset category.
  String get nameExample => switch (this) {
    AssetType.stock => 'e.g. Long-term shares',
    AssetType.mutualFund => 'e.g. Retirement index fund',
    AssetType.crypto => 'e.g. Cold wallet BTC',
    AssetType.gold || AssetType.metals => 'e.g. Family gold',
    AssetType.cash => 'e.g. Emergency fund',
    AssetType.bankDeposit => 'e.g. High-yield savings',
    AssetType.realEstate => 'e.g. Primary residence',
    AssetType.vehicle => 'e.g. Family car',
    AssetType.bond => 'e.g. Treasury bond',
    AssetType.other => 'e.g. Watch collection',
  };

  /// Unknown names fall back to [AssetType.other], as in the Android app.
  static AssetType fromName(String? name) {
    for (final type in values) {
      if (type.storageName == name) return type;
    }
    return AssetType.other;
  }
}
