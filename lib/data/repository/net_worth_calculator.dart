import '../../domain/model/net_worth_summary.dart';
import '../../util/collections.dart';
import '../local/entity/asset_entity.dart';
import '../local/entity/liability_entity.dart';
import 'currency_converter.dart';

/// Aggregates a portfolio's assets and liabilities into a [NetWorthSummary]
/// expressed in one base currency.
class NetWorthCalculator {
  const NetWorthCalculator();

  NetWorthSummary calculate({
    required List<AssetEntity> assets,
    required List<LiabilityEntity> liabilities,
    required String baseCurrency,
    required CurrencyConverter converter,
  }) {
    bool approximate = false;

    double convertValue(double value, String currency) {
      if (!converter.canConvertPair(currency, baseCurrency)) {
        approximate = true;
      }
      return converter.convert(value, currency, baseCurrency);
    }

    final Map<String, List<AssetEntity>> assetGroups =
        groupBy<String, AssetEntity>(
          assets,
          (AssetEntity asset) => asset.type.displayCategory.storageName,
        );
    final List<CategoryTotal> assetBreakdown =
        sortedByDescending<CategoryTotal>(
          assetGroups.entries.map((MapEntry<String, List<AssetEntity>> entry) {
            double total = 0;
            for (final AssetEntity asset in entry.value) {
              total += convertValue(asset.value, asset.currency);
            }
            return CategoryTotal(
              typeName: entry.key,
              label: entry.value.first.type.displayName,
              amount: total,
              count: entry.value.length,
            );
          }),
          (CategoryTotal total) => total.amount,
        );

    final Map<String, List<LiabilityEntity>> liabilityGroups =
        groupBy<String, LiabilityEntity>(
          liabilities,
          (LiabilityEntity liability) => liability.type.storageName,
        );
    final List<CategoryTotal> liabilityBreakdown =
        sortedByDescending<CategoryTotal>(
          liabilityGroups.entries.map((
            MapEntry<String, List<LiabilityEntity>> entry,
          ) {
            double total = 0;
            for (final LiabilityEntity liability in entry.value) {
              total += convertValue(liability.value, liability.currency);
            }
            return CategoryTotal(
              typeName: entry.key,
              label: entry.value.first.type.displayName,
              amount: total,
              count: entry.value.length,
            );
          }),
          (CategoryTotal total) => total.amount,
        );

    double sum(List<CategoryTotal> totals) {
      double result = 0;
      for (final CategoryTotal total in totals) {
        result += total.amount;
      }
      return result;
    }

    return NetWorthSummary(
      baseCurrency: baseCurrency,
      totalAssets: sum(assetBreakdown),
      totalLiabilities: sum(liabilityBreakdown),
      assetBreakdown: assetBreakdown,
      liabilityBreakdown: liabilityBreakdown,
      hasApproximateConversions: approximate,
    );
  }
}
