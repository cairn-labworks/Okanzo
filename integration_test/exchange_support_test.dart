import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/repository/currency_converter.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/asset/asset_edit_view_model.dart';
import 'package:okanzo/ui/asset/stock_exchange_field.dart';
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/home/home_view_model.dart';
import 'package:okanzo/util/currency_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

List<String> _exchangeLabels(WidgetTester tester) => tester
    .widget<DropdownMenu<Object>>(find.byType(DropdownMenu<Object>))
    .dropdownMenuEntries
    .map((DropdownMenuEntry<Object> entry) => entry.label)
    .toList();

Future<void> _openPreferences(WidgetTester tester) async {
  await _tap(tester, find.byType(DropdownMenu<Object>));
  await _tap(tester, find.text(StockExchangeField.manageLabel).last);
  expect(find.text('Preferred exchanges'), findsOneWidget);
}

Future<void> _togglePreference(
  WidgetTester tester,
  StockExchange exchange,
) async {
  final Finder checkbox = find.byKey(ValueKey<StockExchange>(exchange));
  await tester.scrollUntilVisible(
    checkbox,
    120,
    scrollable: find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Scrollable),
    ),
  );
  await _tap(tester, checkbox);
}

Future<void> _setPreferences(
  WidgetTester tester,
  List<StockExchange> desired, {
  Future<void> Function()? beforeSave,
}) async {
  final List<StockExchange> current = tester
      .widget<StockExchangeField>(find.byType(StockExchangeField))
      .preferredExchanges;
  await _openPreferences(tester);
  for (final StockExchange exchange in StockExchange.values) {
    if (desired.contains(exchange) != current.contains(exchange)) {
      await _togglePreference(tester, exchange);
    }
  }
  await beforeSave?.call();
  await _tap(
    tester,
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Save'),
    ),
  );
  expect(find.byType(AlertDialog), findsNothing);
  expect(_exchangeLabels(tester), <String>[
    for (final StockExchange exchange in StockExchange.values)
      if (desired.contains(exchange)) exchange.displayName,
    StockExchangeField.manageLabel,
  ]);
}

Future<void> _selectExchange(
  WidgetTester tester,
  StockExchange exchange,
) async {
  final List<StockExchange> preferred = tester
      .widget<StockExchangeField>(find.byType(StockExchangeField))
      .preferredExchanges;
  if (!preferred.contains(exchange)) {
    await _setPreferences(tester, <StockExchange>[...preferred, exchange]);
  }
  await _select<Object>(tester, exchange.displayName);
}

Future<void> _newAsset(WidgetTester tester) async {
  await _tap(tester, find.byType(FloatingActionButton));
  await _tap(tester, find.text('New asset'));
  await _waitUntil(
    tester,
    () => find.byType(StockExchangeField).evaluate().isNotEmpty,
    'new asset editor',
  );
}

AppContainer _container(WidgetTester tester) =>
    AppScope.of(tester.element(find.byType(HomeScreen)));

AssetEditViewModel _editor(WidgetTester tester) => tester
    .widgetList<ListenableBuilder>(
      find.descendant(
        of: find.byType(AssetEditScreen),
        matching: find.byType(ListenableBuilder),
      ),
    )
    .map((ListenableBuilder builder) => builder.listenable)
    .whereType<AssetEditViewModel>()
    .single;

Future<void> _pickCurrency(WidgetTester tester, String currency) async {
  final String current = _editor(tester).form.currency;
  if (current == currency) return;
  FocusManager.instance.primaryFocus?.unfocus();
  tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(AssetEditScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  await _tap(
    tester,
    find.text('$current — ${CurrencyUtil.displayName(current)}'),
  );
  await _tap(
    tester,
    find.text('$currency — ${CurrencyUtil.displayName(currency)}').last,
  );
  await _waitUntil(
    tester,
    () => !_editor(tester).form.isFetchingPrice,
    'conversion to $currency',
  );
  expect(_editor(tester).form.currency, currency);
  expect(find.textContaining("Couldn't convert currency:"), findsNothing);
}

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
      if (find.text('Got it').evaluate().isNotEmpty) {
        await _tap(tester, find.text('Got it'));
      }
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

      expect(
        container.settingsRepository.current.preferredExchanges,
        <StockExchange>[StockExchange.us],
      );
      await _newAsset(tester);
      expect(_exchangeLabels(tester), <String>[
        StockExchange.us.displayName,
        StockExchangeField.manageLabel,
      ]);
      await _openPreferences(tester);
      await _togglePreference(tester, StockExchange.us);
      await _tap(tester, find.text('Cancel'));
      expect(
        container.settingsRepository.current.preferredExchanges,
        <StockExchange>[StockExchange.us],
      );
      await _setPreferences(
        tester,
        <StockExchange>[
          StockExchange.us,
          StockExchange.hongKong,
          StockExchange.bse,
        ],
        beforeSave: () async {
          if (_captureScreenshots) {
            await binding.takeScreenshot('preferred-exchanges');
          }
        },
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      final Map<String, AssetEntity> saved = <String, AssetEntity>{};
      for (final _Listing listing in _listings) {
        await _newAsset(tester);
        if (listing.type != AssetType.stock) {
          await _select<AssetType>(tester, listing.type.displayName);
        }
        await _selectExchange(tester, listing.exchange);
        await _enter(tester, 'Name', listing.name);
        await _enter(tester, 'Ticker symbol', listing.ticker);
        await _enter(tester, 'Quantity', '2');
        await _pickCurrency(tester, listing.currency);
        if (_captureScreenshots && listing.exchange == StockExchange.bse) {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await _tap(tester, find.byType(DropdownMenu<Object>));
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
            tester.element(find.byType(StockExchangeField)),
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
          () => find.byType(StockExchangeField).evaluate().isNotEmpty,
          'reopening ${listing.symbol}',
        );
        expect(
          tester
              .widget<StockExchangeField>(find.byType(StockExchangeField))
              .selected,
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
      await _selectExchange(tester, StockExchange.bse);
      await _tap(tester, find.text('Fetch latest price'));
      expect(find.text('Enter a ticker symbol first'), findsOneWidget);
      await _select<AssetType>(tester, AssetType.crypto.displayName);
      expect(find.byType(StockExchangeField), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _tap(tester, find.text(_listings.first.name));
      await _waitUntil(
        tester,
        () => find.byType(StockExchangeField).evaluate().isNotEmpty,
        'saved Hong Kong holding',
      );
      await _setPreferences(tester, const <StockExchange>[]);
      expect(
        tester
            .widget<StockExchangeField>(find.byType(StockExchangeField))
            .selected,
        StockExchange.hongKong,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Ticker symbol'))
            .controller
            ?.text,
        '0700.HK',
      );
      expect(find.textContaining('Last price:'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await (await SharedPreferences.getInstance()).reload();
      expect(container.settingsRepository.current.preferredExchanges, isEmpty);
      await _newAsset(tester);
      expect(_exchangeLabels(tester), <String>[StockExchangeField.manageLabel]);
      expect(
        tester
            .widget<StockExchangeField>(find.byType(StockExchangeField))
            .selected,
        isNull,
      );
      if (_captureScreenshots) {
        await _tap(tester, find.byType(DropdownMenu<Object>));
        await binding.takeScreenshot('empty-exchanges');
        await _tap(tester, find.text(StockExchangeField.manageLabel).last);
        await _tap(tester, find.text('Cancel'));
      }
      await _setPreferences(tester, <StockExchange>[
        StockExchange.us,
        StockExchange.bse,
      ]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await (await SharedPreferences.getInstance()).reload();
      expect(
        container.settingsRepository.current.preferredExchanges,
        <StockExchange>[StockExchange.us, StockExchange.bse],
      );

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
      expect(
        _container(tester).settingsRepository.current.preferredExchanges,
        <StockExchange>[StockExchange.us, StockExchange.bse],
      );
      await _newAsset(tester);
      expect(_exchangeLabels(tester), <String>[
        StockExchange.us.displayName,
        StockExchange.bse.displayName,
        StockExchangeField.manageLabel,
      ]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      binding.reportData = <String, Object?>{
        ...?binding.reportData,
        'holdingsSavedReopenedAndRefreshed': _listings.length,
        'symbols': <String>[
          for (final _Listing listing in _listings) listing.symbol,
        ],
        'sqlcipherVersion': cipher.first.values.single,
        'databaseReopened': true,
        'preferredExchangesPersisted': true,
        'emptyPreferencesVerified': true,
        'unpreferredHoldingPreserved': true,
      };
      debugPrint('ANDROID EXCHANGE SMOKE PASSED: ${_listings.length} holdings');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'market currency conversion survives saving, refresh and relaunch',
    (WidgetTester tester) async {
      await app.main();
      await _waitUntil(
        tester,
        () => find.byType(FloatingActionButton).evaluate().isNotEmpty,
        'home portfolio',
      );
      if (find.text('Got it').evaluate().isNotEmpty) {
        await _tap(tester, find.text('Got it'));
      }
      final AppContainer container = _container(tester);
      final String portfolioName =
          'Currency smoke ${DateTime.now().millisecondsSinceEpoch}';
      final int portfolioId = await container.portfolioRepository.create(
        portfolioName,
      );
      await container.settingsRepository.setBaseCurrency('EUR');
      await container.settingsRepository.setSelectedPortfolioId(portfolioId);
      await _waitUntil(
        tester,
        () => find.text(portfolioName).evaluate().isNotEmpty,
        'currency test portfolio',
      );
      final ratesResult = await container.fxRepository.ensureFreshRates();
      expect(ratesResult.isSuccess, isTrue, reason: ratesResult.errorMessage);
      final CurrencyConverter rates = await container.fxRepository
          .currentConverter();
      expect(rates.canConvert('EUR'), isTrue);
      expect(rates.canConvert('GBP'), isTrue);
      final double eurRate = rates.unitsPerUsd['EUR']!;
      final double gbpRate = rates.unitsPerUsd['GBP']!;
      final List<Map<String, Object?>> cipher = await container.database.db
          .rawQuery('PRAGMA cipher_version');
      expect(cipher.first.values.single, isNotEmpty);
      const List<(AssetType, String, String)> holdings =
          <(AssetType, String, String)>[
            (AssetType.crypto, 'BTC-USD', 'Bitcoin currency test'),
            (AssetType.stock, 'AAPL', 'Apple currency test'),
            (AssetType.mutualFund, 'VTI', 'Fund currency test'),
          ];
      final Map<int, AssetEntity> saved = <int, AssetEntity>{};
      for (final (AssetType type, String symbol, String name) in holdings) {
        await _newAsset(tester);
        if (type != AssetType.stock) {
          await _select<AssetType>(tester, type.displayName);
        }
        await _enter(tester, 'Name', name);
        await _enter(tester, 'Ticker symbol', symbol);
        await _enter(tester, 'Quantity', '2');
        await _pickCurrency(tester, 'USD');
        await _tap(tester, find.text('Fetch latest price'));
        await _waitUntil(
          tester,
          () => !_editor(tester).form.isFetchingPrice,
          'USD quote for $symbol',
        );
        expect(_editor(tester).form.lastPrice, greaterThan(0));
        final double usdPrice = _editor(tester).form.lastPrice!;

        await _pickCurrency(tester, 'EUR');
        final double expectedEur = usdPrice * eurRate;
        expect(
          _editor(tester).form.lastPrice,
          closeTo(expectedEur, expectedEur * 1e-12),
        );
        expect(_editor(tester).form.estimatedValue, expectedEur * 2);
        expect(
          find.text('Last price: ${CurrencyUtil.format(expectedEur, 'EUR')}'),
          findsOneWidget,
        );
        await _tap(tester, find.text('Fetch latest price'));
        await _waitUntil(
          tester,
          () => !_editor(tester).form.isFetchingPrice,
          'repeat quote for $symbol',
        );
        expect(_editor(tester).form.currency, 'EUR');
        expect(_editor(tester).form.lastPrice, greaterThan(0));
        final double fetchedEur = _editor(tester).form.lastPrice!;
        await _tap(tester, find.widgetWithText(TextButton, 'Save'));
        await _waitUntil(
          tester,
          () => find.byType(AssetEditScreen).evaluate().isEmpty,
          'saving $symbol in EUR',
        );
        final AssetEntity asset =
            (await container.assetRepository.getForPortfolio(portfolioId))
                .singleWhere((AssetEntity row) => row.name == name);
        expect(asset.currency, 'EUR');
        expect(asset.lastPrice, fetchedEur);
        expect(asset.symbol, symbol);
        expect(asset.quantity, 2);

        if (find.text(name).evaluate().isEmpty) {
          await _tap(tester, find.text(type.displayName));
        }
        await _tap(tester, find.text(name));
        await _waitUntil(
          tester,
          () => !_editor(tester).form.loading,
          'reopening $symbol',
        );
        expect(_editor(tester).form.currency, 'EUR');
        expect(_editor(tester).form.lastPrice, fetchedEur);
        await _pickCurrency(tester, 'GBP');
        final double expectedGbp = fetchedEur / eurRate * gbpRate;
        expect(
          _editor(tester).form.lastPrice,
          closeTo(expectedGbp, expectedGbp * 1e-12),
        );
        await _tap(tester, find.widgetWithText(TextButton, 'Save'));
        await _waitUntil(
          tester,
          () => find.byType(AssetEditScreen).evaluate().isEmpty,
          'saving $symbol in GBP',
        );
        final AssetEntity updated = (await container.assetRepository.getById(
          asset.id,
        ))!;
        expect(updated.currency, 'GBP');
        expect(updated.lastPrice, closeTo(expectedGbp, expectedGbp * 1e-12));
        saved[updated.id] = updated;
        debugPrint(
          'ANDROID CURRENCY SAVED $symbol USD=$usdPrice GBP=$expectedGbp',
        );
      }

      await _tap(tester, find.byTooltip('Refresh prices'));
      await _waitUntil(
        tester,
        () => find.text('Updated 3 price(s)').evaluate().isNotEmpty,
        'refreshing converted market holdings',
        timeout: const Duration(minutes: 3),
      );
      final List<AssetEntity> refreshed = await container.assetRepository
          .getForPortfolio(portfolioId);
      expect(refreshed, hasLength(3));
      for (final AssetEntity asset in refreshed) {
        expect(asset.currency, 'GBP');
        expect(asset.lastPrice, greaterThan(0));
        expect(
          asset.lastPriceTimestamp,
          greaterThan(saved[asset.id]!.lastPriceTimestamp!),
        );
      }
      final CurrencyConverter refreshedRates = await container.fxRepository
          .currentConverter();
      final double expectedTotal = refreshed.fold<double>(
        0,
        (double total, AssetEntity asset) =>
            total +
            asset.lastPrice! /
                refreshedRates.unitsPerUsd['GBP']! *
                refreshedRates.unitsPerUsd['EUR']! *
                asset.quantity!,
      );
      final HomeViewModel home = tester
          .widgetList<ListenableBuilder>(find.byType(ListenableBuilder))
          .map((ListenableBuilder builder) => builder.listenable)
          .whereType<HomeViewModel>()
          .single;
      expect(home.state.baseCurrency, 'EUR');
      expect(
        home.state.summary.totalAssets,
        closeTo(expectedTotal, expectedTotal * 1e-12),
      );
      expect(home.state.summary.hasApproximateConversions, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await container.settingsRepository.dispose();
      await container.database.close();
      await app.main();
      await _waitUntil(
        tester,
        () => find.text(portfolioName).evaluate().isNotEmpty,
        'relaunching the currency portfolio',
      );
      final List<AssetEntity> reopened = await _container(tester)
          .assetRepository
          .getForPortfolio(portfolioId);
      expect(reopened, hasLength(3));
      for (final AssetEntity asset in reopened) {
        final AssetEntity previous = refreshed.singleWhere(
          (AssetEntity row) => row.id == asset.id,
        );
        expect(asset.currency, 'GBP');
        expect(asset.lastPrice, previous.lastPrice);
        expect(asset.lastPriceTimestamp, previous.lastPriceTimestamp);
      }
      binding.reportData = <String, Object?>{
        ...?binding.reportData,
        'convertedMarketHoldings': 3,
        'currencies': <String>['USD', 'EUR', 'GBP'],
        'baseCurrencyTotalVerified': true,
        'databaseReopened': true,
        'sqlcipherVersion': cipher.first.values.single,
      };
      debugPrint('ANDROID CURRENCY SMOKE PASSED: crypto, stock and fund');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
