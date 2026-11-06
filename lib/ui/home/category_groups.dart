import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/repository/currency_converter.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/liability_type.dart';

/// A single asset within a category, paired with its value already converted to
/// the portfolio's base currency so the expanded row can show the same currency
/// as the group total.
class AssetLine {
  const AssetLine({required this.asset, required this.convertedValue});

  final AssetEntity asset;

  /// [asset.value] expressed in the base currency.
  final double convertedValue;
}

/// A single liability within a category, paired with its value converted to the
/// base currency.
class LiabilityLine {
  const LiabilityLine({required this.liability, required this.convertedValue});

  final LiabilityEntity liability;

  /// [liability.value] expressed in the base currency.
  final double convertedValue;
}

/// Pairs each asset with its value converted to [baseCurrency], so the expanded
/// rows and the group total both read in the portfolio's currency.
List<AssetLine> buildAssetLines(
  Iterable<AssetEntity> assets,
  CurrencyConverter converter,
  String baseCurrency,
) => <AssetLine>[
  for (final AssetEntity asset in assets)
    AssetLine(
      asset: asset,
      convertedValue: converter.convert(
        asset.value,
        asset.currency,
        baseCurrency,
      ),
    ),
];

/// Pairs each liability with its value converted to [baseCurrency].
List<LiabilityLine> buildLiabilityLines(
  Iterable<LiabilityEntity> liabilities,
  CurrencyConverter converter,
  String baseCurrency,
) => <LiabilityLine>[
  for (final LiabilityEntity liability in liabilities)
    LiabilityLine(
      liability: liability,
      convertedValue: converter.convert(
        liability.value,
        liability.currency,
        baseCurrency,
      ),
    ),
];

/// Sum of the already-converted values of [lines].
double sumAssetLines(Iterable<AssetLine> lines) {
  double total = 0;
  for (final AssetLine line in lines) {
    total += line.convertedValue;
  }
  return total;
}

/// Sum of the already-converted values of [lines].
double sumLiabilityLines(Iterable<LiabilityLine> lines) {
  double total = 0;
  for (final LiabilityLine line in lines) {
    total += line.convertedValue;
  }
  return total;
}

/// One collapsible asset category (all assets sharing a type) shown on Home.
class AssetCategoryGroup {
  const AssetCategoryGroup({
    required this.type,
    required this.total,
    required this.baseCurrency,
    required this.items,
  });

  final AssetType type;

  /// Total value of the group, converted to the base currency.
  final double total;
  final String baseCurrency;
  final List<AssetLine> items;
}

/// One collapsible liability category (all liabilities sharing a type).
class LiabilityCategoryGroup {
  const LiabilityCategoryGroup({
    required this.type,
    required this.total,
    required this.baseCurrency,
    required this.items,
  });

  final LiabilityType type;
  final double total;
  final String baseCurrency;
  final List<LiabilityLine> items;
}

/// The secondary line under an asset row: quantity, symbol and, when it differs
/// from the base currency, the asset's own currency.
String assetSubtitle(
  AssetEntity asset,
  String baseCurrency, {
  String unitsLabel = 'units',
}) {
  String core;
  switch (asset.type.valuationMode) {
    case ValuationMode.market:
      final String qty = asset.quantity == null
          ? '—'
          : formatQuantity(asset.quantity!);
      final String symbol = asset.symbol?.toUpperCase() ?? '';
      core = symbol.isNotEmpty ? '$qty × $symbol' : '$qty $unitsLabel';
    case ValuationMode.quantity:
      final String qty = asset.quantity == null
          ? '—'
          : formatQuantity(asset.quantity!);
      core = '$qty ${asset.type.unitLabel ?? ''}'.trim();
    case ValuationMode.flat:
      core = '';
  }
  return (core + currencyNote(asset.currency, baseCurrency)).trim();
}

String currencyNote(String currency, String baseCurrency) =>
    currency != baseCurrency ? '  ·  $currency' : '';

String formatQuantity(double value) =>
    value % 1.0 == 0.0 ? value.truncate().toString() : value.toString();

/// "1 item" / "N items".
String itemCountLabel(int count) => count == 1 ? '1 item' : '$count items';
