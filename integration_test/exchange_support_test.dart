import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/util/currency_util.dart';

class _Listing {
  const _Listing(
    this.exchange,
    this.ticker,
    this.symbol,
    this.currency,
    this.name, {
    this.type = AssetType.stock,
  });

  final StockExchange exchange;
  final String ticker;
  final String symbol;
  final String currency;
  final String name;
  final AssetType type;
}

const bool _captureScreenshots = bool.fromEnvironment('CAPTURE_SCREENSHOTS');

const List<_Listing> _listings = <_Listing>[
  _Listing(StockExchange.hongKong, '0700', '0700.HK', 'HKD', 'Tencent'),
  _Listing(StockExchange.bse, 'RELIANCE', 'RELIANCE.BO', 'INR', 'Reliance'),
  _Listing(
    StockExchange.shanghai,
    '600519',
    '600519.SS',
    'CNY',
    'Kweichow Moutai',
  ),
  _Listing(StockExchange.tokyo, '7203', '7203.T', 'JPY', 'Toyota'),
  _Listing(StockExchange.euronextParis, 'AIR', 'AIR.PA', 'EUR', 'Airbus'),
  _Listing(StockExchange.euronextAmsterdam, 'ASML', 'ASML.AS', 'EUR', 'ASML'),
  _Listing(StockExchange.euronextBrussels, 'ABI', 'ABI.BR', 'EUR', 'AB InBev'),
  _Listing(StockExchange.euronextLisbon, 'EDP', 'EDP.LS', 'EUR', 'EDP'),
  _Listing(StockExchange.euronextDublin, 'KRX', 'KRX.IR', 'EUR', 'Kerry Group'),
  _Listing(StockExchange.euronextOslo, 'EQNR', 'EQNR.OL', 'NOK', 'Equinor'),
  _Listing(StockExchange.euronextMilan, 'ENI', 'ENI.MI', 'EUR', 'Eni'),
  _Listing(
    StockExchange.tokyo,
    '1306',
    '1306.T',
    'JPY',
    'TOPIX ETF',
    type: AssetType.mutualFund,
  ),
  _Listing(StockExchange.other, 'VOD.L', 'VOD.L', 'GBP', 'Vodafone'),
  _Listing(StockExchange.us, 'AAPL', 'AAPL', 'USD', 'Apple'),
];

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition,
  String description, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed >= timeout) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: description);
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _waitUntil(
    tester,
    () => finder.hitTestable().evaluate().isNotEmpty,
    'an unobstructed tap target',
  );
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final Finder field = find.widgetWithText(TextField, label);
  await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _select<T>(WidgetTester tester, String label) async {
  await _tap(tester, find.byType(DropdownMenu<T>));
  await _tap(tester, find.text(label).last);
}

Future<void> _newAsset(WidgetTester tester) async {
  await _tap(tester, find.byType(FloatingActionButton));
  await _tap(tester, find.text('New asset'));
  await _waitUntil(
    tester,
    () => find.byType(DropdownMenu<StockExchange>).evaluate().isNotEmpty,
    'new asset editor',
  );
}

AppContainer _container(WidgetTester tester) =>
    AppScope.of(tester.element(find.byType(HomeScreen)));

void _verifyHolding(AssetEntity asset, _Listing listing) {
  expect(asset.symbol, listing.symbol);
  expect(asset.currency, listing.currency);
  expect(asset.type, listing.type);
  expect(asset.quantity, 2);
  expect(asset.lastPrice, greaterThan(0));
  expect(asset.lastPriceTimestamp, greaterThan(0));
  expect(asset.value, asset.lastPrice! * 2);
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live exchange quotes survive saving, reopening and portfolio refresh',
    (WidgetTester tester) async {
      await app.main();
      await _waitUntil(
        tester,
        () => find.byType(FloatingActionButton).evaluate().isNotEmpty,
        'home portfolio',
      );
      final AppContainer container = _container(tester);
      final String portfolioName = _captureScreenshots
          ? 'Global demo'
          : 'Exchange smoke ${DateTime.now().millisecondsSinceEpoch}';
      final int portfolioId = await container.portfolioRepository.create(
        portfolioName,
      );
      await container.settingsRepository.setSelectedPortfolioId(portfolioId);
      await _waitUntil(
        tester,
        () => find.text(portfolioName).evaluate().isNotEmpty,
        'test portfolio selection',
      );
      if (_captureScreenshots) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
      }
      final List<Map<String, Object?>> cipher = await container.database.db
          .rawQuery('PRAGMA cipher_version');
      expect(cipher, isNotEmpty);
      expect(cipher.first.values.single, isNotEmpty);

      final Map<String, AssetEntity> saved = <String, AssetEntity>{};
      for (final _Listing listing in _listings) {
        await _newAsset(tester);
        if (listing.type != AssetType.stock) {
          await _select<AssetType>(tester, listing.type.displayName);
        }
        await _select<StockExchange>(tester, listing.exchange.displayName);
        await _enter(tester, 'Name', listing.name);
        await _enter(tester, 'Ticker symbol', listing.ticker);
        await _enter(tester, 'Quantity', '2');
        if (_captureScreenshots && listing.exchange == StockExchange.bse) {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await _tap(tester, find.byType(DropdownMenu<StockExchange>));
          await Scrollable.ensureVisible(
            tester.element(find.text(StockExchange.hongKong.displayName).last),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          await binding.takeScreenshot('exchange-picker');
          await _tap(tester, find.text(StockExchange.bse.displayName).last);
        }
        await _tap(tester, find.text('Fetch latest price'));
        await _waitUntil(
          tester,
          () =>
              find.textContaining('Last price:').evaluate().isNotEmpty ||
              find
                  .textContaining("Couldn't fetch price:")
                  .evaluate()
                  .isNotEmpty,
          'live ${listing.symbol} quote',
        );
        expect(
          find.textContaining("Couldn't fetch price:"),
          findsNothing,
          reason: 'Live quote failed for ${listing.symbol}',
        );
        if (_captureScreenshots && listing.exchange == StockExchange.bse) {
          await Scrollable.ensureVisible(
            tester.element(find.byType(DropdownMenu<StockExchange>)),
            alignment: 0.1,
          );
          await tester.pumpAndSettle();
          await binding.takeScreenshot('bse-quote');
        }
        await _tap(tester, find.widgetWithText(TextButton, 'Save'));
        await _waitUntil(
          tester,
          () => find.byType(AssetEditScreen).evaluate().isEmpty,
          'saving ${listing.symbol}',
        );
        final AssetEntity asset =
            (await container.assetRepository.getForPortfolio(portfolioId))
                .singleWhere((AssetEntity row) => row.name == listing.name);
        _verifyHolding(asset, listing);
        saved[listing.symbol] = asset;
        debugPrint('ANDROID SAVED ${asset.symbol} ${asset.currency}');
      }

      if (_captureScreenshots) {
        await _tap(tester, find.text(AssetType.stock.displayName));
        await Scrollable.ensureVisible(
          tester.element(find.text(AssetType.stock.displayName)),
          alignment: 0.25,
        );
        await tester.pumpAndSettle();
        await binding.takeScreenshot('global-portfolio');
        await _tap(tester, find.text(AssetType.stock.displayName));
      }

      final Set<AssetType> expanded = <AssetType>{};
      for (final _Listing listing in _listings) {
        if (expanded.add(listing.type)) {
          await _tap(tester, find.text(listing.type.displayName));
        }
        await _tap(tester, find.text(listing.name));
        await _waitUntil(
          tester,
          () => find.byType(DropdownMenu<StockExchange>).evaluate().isNotEmpty,
          'reopening ${listing.symbol}',
        );
        expect(
          tester
              .widget<DropdownMenu<StockExchange>>(
                find.byType(DropdownMenu<StockExchange>),
              )
              .initialSelection,
          listing.exchange,
        );
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'Ticker symbol'),
              )
              .controller
              ?.text,
          listing.symbol,
        );
        final AssetEntity asset = saved[listing.symbol]!;
        expect(
          find.text(
            'Last price: ${CurrencyUtil.format(asset.lastPrice!, asset.currency)}',
          ),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await _tap(tester, find.byTooltip('Refresh prices'));
      await _waitUntil(
        tester,
        () => find.textContaining('Updated ').evaluate().isNotEmpty,
        'portfolio price refresh',
        timeout: const Duration(minutes: 4),
      );
      expect(find.text('Updated ${_listings.length} price(s)'), findsOneWidget);
      final List<AssetEntity> refreshed = await container.assetRepository
          .getForPortfolio(portfolioId);
      expect(refreshed, hasLength(_listings.length));
      for (final _Listing listing in _listings) {
        final AssetEntity asset = refreshed.singleWhere(
          (AssetEntity row) => row.symbol == listing.symbol,
        );
        _verifyHolding(asset, listing);
        expect(
          asset.lastPriceTimestamp,
          greaterThan(saved[listing.symbol]!.lastPriceTimestamp!),
        );
      }

      await _newAsset(tester);
      await _select<StockExchange>(tester, StockExchange.bse.displayName);
      await _tap(tester, find.text('Fetch latest price'));
      expect(find.text('Enter a ticker symbol first'), findsOneWidget);
      await _select<AssetType>(tester, AssetType.crypto.displayName);
      expect(find.byType(DropdownMenu<StockExchange>), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await container.settingsRepository.dispose();
      await container.database.close();
      await app.main();
      await _waitUntil(
        tester,
        () => find.text(portfolioName).evaluate().isNotEmpty,
        'relaunching with the saved portfolio',
      );
      final List<AssetEntity> reopened = await _container(tester)
          .assetRepository
          .getForPortfolio(portfolioId);
      expect(reopened, hasLength(_listings.length));
      for (final _Listing listing in _listings) {
        _verifyHolding(
          reopened.singleWhere(
            (AssetEntity row) => row.symbol == listing.symbol,
          ),
          listing,
        );
      }
      binding.reportData = <String, Object?>{
        ...?binding.reportData,
        'holdingsSavedReopenedAndRefreshed': _listings.length,
        'symbols': <String>[
          for (final _Listing listing in _listings) listing.symbol,
        ],
        'sqlcipherVersion': cipher.first.values.single,
        'databaseReopened': true,
      };
      debugPrint('ANDROID EXCHANGE SMOKE PASSED: ${_listings.length} holdings');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
