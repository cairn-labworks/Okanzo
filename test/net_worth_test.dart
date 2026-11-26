import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/data/repository/currency_converter.dart';
import 'package:okanzo/data/repository/net_worth_calculator.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/domain/model/net_worth_summary.dart';
import 'package:test/test.dart';

AssetEntity asset({
  required AssetType type,
  String currency = 'USD',
  double? quantity,
  double? pricePerUnit,
  double? lastPrice,
  double? manualValue,
  String name = 'Item',
}) => AssetEntity(
  portfolioId: 1,
  type: type,
  name: name,
  currency: currency,
  quantity: quantity,
  pricePerUnit: pricePerUnit,
  lastPrice: lastPrice,
  manualValue: manualValue,
  createdAt: 0,
  updatedAt: 0,
);

LiabilityEntity liability({
  required LiabilityType type,
  required double amount,
  String currency = 'USD',
  String name = 'Debt',
}) => LiabilityEntity(
  portfolioId: 1,
  type: type,
  name: name,
  currency: currency,
  amount: amount,
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  const NetWorthCalculator calculator = NetWorthCalculator();

  group('CurrencyConverter', () {
    const CurrencyConverter converter = CurrencyConverter(<String, double>{
      'EUR': 0.5,
      'INR': 80.0,
      'ZERO': 0.0,
    });

    test('passes through when both sides match', () {
      expect(converter.convert(10.0, 'EUR', 'EUR'), 10.0);
    });

    test('converts through USD', () {
      expect(converter.convert(10.0, 'EUR', 'USD'), 20.0);
      expect(converter.convert(10.0, 'USD', 'EUR'), 5.0);
      expect(converter.convert(10.0, 'EUR', 'INR'), 1600.0);
    });

    test('returns the amount unchanged when a rate is missing', () {
      expect(converter.convert(10.0, 'XYZ', 'USD'), 10.0);
      expect(converter.convert(10.0, 'USD', 'XYZ'), 10.0);
    });

    test('guards against a zero rate', () {
      expect(converter.convert(10.0, 'ZERO', 'USD'), 10.0);
    });

    test('USD is always convertible, unknown codes are not', () {
      expect(converter.canConvert('USD'), isTrue);
      expect(converter.canConvert('EUR'), isTrue);
      expect(converter.canConvert('XYZ'), isFalse);
      expect(const CurrencyConverter.empty().isEmpty, isTrue);
    });
  });

  group('asset valuation', () {
    test('market assets use quantity x last price', () {
      expect(
        asset(type: AssetType.stock, quantity: 3, lastPrice: 10).value,
        30.0,
      );
      expect(asset(type: AssetType.stock, quantity: 3).value, 0.0);
    });

    test('quantity assets use quantity x price per unit', () {
      expect(
        asset(type: AssetType.gold, quantity: 4, pricePerUnit: 25).value,
        100.0,
      );
    });

    test('flat assets use the manual value', () {
      expect(asset(type: AssetType.cash, manualValue: 42).value, 42.0);
      expect(asset(type: AssetType.cash).value, 0.0);
    });
  });

  group('NetWorthCalculator', () {
    test('totals assets and liabilities in the base currency', () {
      final NetWorthSummary summary = calculator.calculate(
        assets: <AssetEntity>[
          asset(type: AssetType.cash, manualValue: 100),
          asset(type: AssetType.stock, quantity: 2, lastPrice: 50),
          asset(type: AssetType.cash, manualValue: 100, currency: 'EUR'),
        ],
        liabilities: <LiabilityEntity>[
          liability(type: LiabilityType.loan, amount: 60),
        ],
        baseCurrency: 'USD',
        converter: const CurrencyConverter(<String, double>{'EUR': 0.5}),
      );

      expect(summary.totalAssets, 400.0);
      expect(summary.totalLiabilities, 60.0);
      expect(summary.netWorth, 340.0);
      expect(summary.hasApproximateConversions, isFalse);
    });

    test('groups by type and sorts categories by descending amount', () {
      final NetWorthSummary summary = calculator.calculate(
        assets: <AssetEntity>[
          asset(type: AssetType.cash, manualValue: 10),
          asset(type: AssetType.cash, manualValue: 5),
          asset(type: AssetType.realEstate, manualValue: 1000),
        ],
        liabilities: <LiabilityEntity>[
          liability(type: LiabilityType.tax, amount: 10),
          liability(type: LiabilityType.mortgage, amount: 700),
        ],
        baseCurrency: 'USD',
        converter: const CurrencyConverter.empty(),
      );

      expect(
        summary.assetBreakdown.map((CategoryTotal t) => t.typeName).toList(),
        <String>['REAL_ESTATE', 'CASH'],
      );
      expect(summary.assetBreakdown.first.label, 'Real estate');
      expect(summary.assetBreakdown.last.count, 2);
      expect(summary.assetBreakdown.last.amount, 15.0);
      expect(
        summary.liabilityBreakdown
            .map((CategoryTotal t) => t.typeName)
            .toList(),
        <String>['MORTGAGE', 'TAX'],
      );
    });

    test('flags approximate totals when a rate is missing', () {
      final NetWorthSummary summary = calculator.calculate(
        assets: <AssetEntity>[
          asset(type: AssetType.cash, manualValue: 100, currency: 'XYZ'),
        ],
        liabilities: const <LiabilityEntity>[],
        baseCurrency: 'USD',
        converter: const CurrencyConverter.empty(),
      );

      expect(summary.hasApproximateConversions, isTrue);
      // The unconverted amount is still counted 1:1.
      expect(summary.totalAssets, 100.0);

      final NetWorthSummary missingBaseRate = calculator.calculate(
        assets: <AssetEntity>[
          asset(type: AssetType.cash, manualValue: 100, currency: 'USD'),
        ],
        liabilities: const <LiabilityEntity>[],
        baseCurrency: 'INR',
        converter: const CurrencyConverter.empty(),
      );
      expect(missingBaseRate.hasApproximateConversions, isTrue);
    });

    test('does not flag items already in the base currency', () {
      final NetWorthSummary summary = calculator.calculate(
        assets: <AssetEntity>[
          asset(type: AssetType.cash, manualValue: 100, currency: 'XYZ'),
        ],
        liabilities: const <LiabilityEntity>[],
        baseCurrency: 'XYZ',
        converter: const CurrencyConverter.empty(),
      );

      expect(summary.hasApproximateConversions, isFalse);
    });

    test('an empty portfolio has a zero net worth', () {
      final NetWorthSummary summary = calculator.calculate(
        assets: const <AssetEntity>[],
        liabilities: const <LiabilityEntity>[],
        baseCurrency: 'USD',
        converter: const CurrencyConverter.empty(),
      );

      expect(summary.netWorth, 0.0);
      expect(summary.assetBreakdown, isEmpty);
      expect(summary.liabilityBreakdown, isEmpty);
    });

    test('a negative net worth is reported as-is', () {
      final NetWorthSummary summary = calculator.calculate(
        assets: <AssetEntity>[asset(type: AssetType.cash, manualValue: 10)],
        liabilities: <LiabilityEntity>[
          liability(type: LiabilityType.loan, amount: 110),
        ],
        baseCurrency: 'USD',
        converter: const CurrencyConverter.empty(),
      );

      expect(summary.netWorth, -100.0);
    });
  });
}
