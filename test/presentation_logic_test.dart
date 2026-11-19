import 'package:okanzo/data/local/entity/portfolio_entity.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/data/repository/currency_converter.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/ui/home/category_groups.dart';
import 'package:okanzo/ui/statistics/chart_format.dart';
import 'package:okanzo/util/category_order.dart';
import 'package:okanzo/util/collections.dart';
import 'package:test/test.dart';

PortfolioEntity portfolio(int id, String name, {bool isDefault = false}) =>
    PortfolioEntity(
      id: id,
      name: name,
      isDefault: isDefault,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  group('orderTypes', () {
    test('follows the saved order and appends new types', () {
      final List<AssetType> ordered = orderTypes<AssetType>(
        <AssetType>[AssetType.cash, AssetType.stock, AssetType.gold],
        <String>['GOLD', 'CASH'],
        AssetType.fromName,
      );
      expect(ordered, <AssetType>[
        AssetType.gold,
        AssetType.cash,
        AssetType.stock,
      ]);
    });

    test('ignores saved types that are not present', () {
      final List<AssetType> ordered = orderTypes<AssetType>(
        <AssetType>[AssetType.cash],
        <String>['STOCK', 'CASH'],
        AssetType.fromName,
      );
      expect(ordered, <AssetType>[AssetType.cash]);
    });

    test('unknown saved names resolve to the fallback type', () {
      final List<LiabilityType> ordered = orderTypes<LiabilityType>(
        <LiabilityType>[LiabilityType.other, LiabilityType.loan],
        <String>['NOT_A_TYPE'],
        LiabilityType.fromName,
      );
      // "NOT_A_TYPE" parses to OTHER, which is present and therefore first.
      expect(ordered, <LiabilityType>[LiabilityType.other, LiabilityType.loan]);
    });

    test('an empty saved order keeps the natural enum order', () {
      final List<AssetType> ordered = orderTypes<AssetType>(
        <AssetType>[AssetType.other, AssetType.stock, AssetType.cash],
        const <String>[],
        AssetType.fromName,
      );
      expect(ordered, <AssetType>[
        AssetType.stock,
        AssetType.cash,
        AssetType.other,
      ]);
    });
  });

  group('resolveActivePortfolio', () {
    final List<PortfolioEntity> portfolios = <PortfolioEntity>[
      portfolio(1, 'First'),
      portfolio(2, 'Main', isDefault: true),
      portfolio(3, 'Side'),
    ];

    test('prefers the explicitly selected portfolio', () {
      expect(resolveActivePortfolio(portfolios, 3)?.id, 3);
    });

    test('falls back to the default when the selection is gone', () {
      expect(resolveActivePortfolio(portfolios, 99)?.id, 2);
    });

    test('falls back to the first portfolio when none is default', () {
      final List<PortfolioEntity> plain = <PortfolioEntity>[
        portfolio(5, 'A'),
        portfolio(6, 'B'),
      ];
      expect(resolveActivePortfolio(plain, null)?.id, 5);
    });

    test('returns null when there are no portfolios', () {
      expect(resolveActivePortfolio(const <PortfolioEntity>[], 1), isNull);
    });
  });

  group('collection helpers', () {
    test('groupBy preserves insertion order of keys and items', () {
      final Map<String, List<int>> grouped = groupBy<String, int>(<int>[
        1,
        2,
        3,
        4,
      ], (int value) => value.isEven ? 'even' : 'odd');
      expect(grouped.keys.toList(), <String>['odd', 'even']);
      expect(grouped['odd'], <int>[1, 3]);
    });

    test('sortedByDescending is stable for equal keys', () {
      final List<String> sorted = sortedByDescending<String>(<String>[
        'a',
        'b',
        'c',
      ], (String _) => 0);
      expect(sorted, <String>['a', 'b', 'c']);
    });
  });

  group('home list labels', () {
    AssetEntity asset({
      required AssetType type,
      double? quantity,
      String? symbol,
      String currency = 'USD',
    }) => AssetEntity(
      portfolioId: 1,
      type: type,
      name: 'X',
      currency: currency,
      quantity: quantity,
      symbol: symbol,
      createdAt: 0,
      updatedAt: 0,
    );

    test('market assets show quantity x ticker', () {
      expect(
        assetSubtitle(
          asset(type: AssetType.stock, quantity: 3, symbol: 'aapl'),
          'USD',
        ),
        '3 × AAPL',
      );
    });

    test('market assets without a ticker show units', () {
      expect(
        assetSubtitle(asset(type: AssetType.stock, quantity: 2.5), 'USD'),
        '2.5 units',
      );
    });

    test('quantity assets show the unit label', () {
      expect(
        assetSubtitle(asset(type: AssetType.gold, quantity: 10), 'USD'),
        '10 g',
      );
    });

    test('flat assets have no core subtitle', () {
      expect(assetSubtitle(asset(type: AssetType.cash), 'USD'), '');
    });

    test('a foreign currency is appended', () {
      expect(
        assetSubtitle(asset(type: AssetType.cash, currency: 'EUR'), 'USD'),
        '·  EUR',
      );
      expect(
        assetSubtitle(
          asset(type: AssetType.gold, quantity: 1, currency: 'EUR'),
          'USD',
        ),
        '1 g  ·  EUR',
      );
    });

    test('missing quantities render as a dash', () {
      expect(
        assetSubtitle(asset(type: AssetType.stock, symbol: 'AAPL'), 'USD'),
        '— × AAPL',
      );
    });

    test(
      'hideBalances omits quantities while keeping tickers and currency notes',
      () {
        expect(
          assetSubtitle(
            asset(type: AssetType.crypto, quantity: 1.25, symbol: 'btc-usd'),
            'USD',
            hideBalances: true,
          ),
          'BTC-USD',
        );
        expect(
          assetSubtitle(
            asset(
              type: AssetType.stock,
              quantity: 10,
              symbol: 'mc.pa',
              currency: 'EUR',
            ),
            'USD',
            hideBalances: true,
          ),
          'MC.PA  ·  EUR',
        );
        expect(
          assetSubtitle(
            asset(type: AssetType.stock, symbol: 'AAPL'),
            'USD',
            hideBalances: true,
          ),
          'AAPL',
        );
        expect(
          assetSubtitle(
            asset(type: AssetType.stock, quantity: 2.5),
            'USD',
            hideBalances: true,
          ),
          '',
        );
        expect(
          assetSubtitle(
            asset(type: AssetType.stock, quantity: 2.5, currency: 'EUR'),
            'USD',
            hideBalances: true,
          ),
          '·  EUR',
        );
        expect(
          assetSubtitle(
            asset(type: AssetType.gold, quantity: 250),
            'USD',
            hideBalances: true,
          ),
          '',
        );
        expect(
          assetSubtitle(
            asset(type: AssetType.gold, quantity: 250, currency: 'EUR'),
            'USD',
            hideBalances: true,
          ),
          '·  EUR',
        );
        expect(
          assetSubtitle(
            asset(type: AssetType.cash, currency: 'EUR'),
            'USD',
            hideBalances: true,
          ),
          '·  EUR',
        );
      },
    );

    test('item counts are singular for one', () {
      expect(itemCountLabel(1), '1 item');
      expect(itemCountLabel(0), '0 items');
      expect(itemCountLabel(4), '4 items');
    });

    test('quantities drop a trailing .0', () {
      expect(formatQuantity(7.0), '7');
      expect(formatQuantity(7.25), '7.25');
    });

    test('the currency note is omitted for the base currency', () {
      expect(currencyNote('USD', 'USD'), '');
      expect(currencyNote('EUR', 'USD'), '  \u00b7  EUR');
    });
  });

  group('percentageLabel', () {
    test('uses whole numbers from ten percent up', () {
      expect(percentageLabel(50, 100), '50%');
      expect(percentageLabel(10, 100), '10%');
      expect(percentageLabel(99.9, 100), '99%');
    });

    test('uses one decimal below ten percent', () {
      expect(percentageLabel(5, 100), '5.0%');
      expect(percentageLabel(0.05, 100), '0.1%');
    });

    test('is empty when there is nothing to divide by', () {
      expect(percentageLabel(5, 0), '');
      expect(percentageLabel(5, -1), '');
    });
  });

  group('selectDonutCenterAmount', () {
    test('keeps exact text when scaling stays readable in the donut hole', () {
      expect(
        selectDonutCenterAmount(
          fullText: '₹9,18,543',
          compactText: '₹9.18 L',
          fullTextWidth: 96,
          maxWidth: 103,
        ),
        '₹9,18,543',
      );
      expect(
        selectDonutCenterAmount(
          fullText: '₹1,65,34,234',
          compactText: '₹1.65 Cr',
          fullTextWidth: 128,
          maxWidth: 103,
        ),
        '₹1,65,34,234',
      );
    });

    test('switches to compact units when full digits would shrink too far', () {
      expect(
        selectDonutCenterAmount(
          fullText: '₹68,73,17,27,181',
          compactText: '₹6,873.17 Cr',
          fullTextWidth: 170,
          maxWidth: 103,
        ),
        '₹6,873.17 Cr',
      );
    });

    test('never replaces text when compact form is not shorter', () {
      expect(
        selectDonutCenterAmount(
          fullText: '₹999',
          compactText: '₹999',
          fullTextWidth: 200,
          maxWidth: 103,
        ),
        '₹999',
      );
    });
  });

  group('expanded rows convert to the base currency', () {
    // 1 USD = 0.5 GBP, 1 USD = 80 INR.
    const CurrencyConverter converter = CurrencyConverter(<String, double>{
      'GBP': 0.5,
      'INR': 80.0,
    });

    AssetEntity cashAsset(double amount, String currency) => AssetEntity(
      portfolioId: 1,
      type: AssetType.cash,
      name: 'Wallet',
      currency: currency,
      manualValue: amount,
      createdAt: 0,
      updatedAt: 0,
    );

    LiabilityEntity loan(double amount, String currency) => LiabilityEntity(
      portfolioId: 1,
      type: LiabilityType.loan,
      name: 'Loan',
      currency: currency,
      amount: amount,
      createdAt: 0,
      updatedAt: 0,
    );

    test('each asset line carries its value in the base currency', () {
      // 100 USD -> 50 GBP, 40 GBP stays 40 GBP.
      final List<AssetLine> lines = buildAssetLines(
        <AssetEntity>[cashAsset(100, 'USD'), cashAsset(40, 'GBP')],
        converter,
        'GBP',
      );
      expect(lines[0].convertedValue, 50);
      expect(lines[1].convertedValue, 40);
      // The underlying entity keeps its original currency for the subtitle note.
      expect(lines[0].asset.currency, 'USD');
    });

    test('asset line total matches the sum of converted values', () {
      final List<AssetLine> lines = buildAssetLines(
        <AssetEntity>[cashAsset(100, 'USD'), cashAsset(40, 'GBP')],
        converter,
        'GBP',
      );
      expect(sumAssetLines(lines), 90);
    });

    test('each liability line carries its value in the base currency', () {
      // 800 INR -> 10 USD, keeping USD as 5 USD.
      final List<LiabilityLine> lines = buildLiabilityLines(
        <LiabilityEntity>[loan(800, 'INR'), loan(5, 'USD')],
        converter,
        'USD',
      );
      expect(lines[0].convertedValue, 10);
      expect(lines[1].convertedValue, 5);
      expect(sumLiabilityLines(lines), 15);
    });

    test('an unknown rate falls back to the original amount', () {
      final List<AssetLine> lines = buildAssetLines(
        <AssetEntity>[cashAsset(100, 'JPY')],
        converter,
        'GBP',
      );
      // No JPY rate cached, so the amount passes through 1:1.
      expect(lines.single.convertedValue, 100);
    });
  });
}
