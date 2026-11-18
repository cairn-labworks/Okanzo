import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/backup/backup_repository.dart';
import 'package:okanzo/data/local/app_database.dart';
import 'package:okanzo/data/local/dao/asset_dao.dart';
import 'package:okanzo/data/local/dao/fx_rate_dao.dart';
import 'package:okanzo/data/local/dao/portfolio_dao.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/remote/fx/fx_api.dart';
import 'package:okanzo/data/remote/stock/chart_response.dart';
import 'package:okanzo/data/remote/stock/stock_price_service.dart';
import 'package:okanzo/data/remote/stock/stock_search_service.dart';
import 'package:okanzo/data/repository/asset_repository.dart';
import 'package:okanzo/data/repository/fx_repository.dart';
import 'package:okanzo/data/repository/liability_repository.dart';
import 'package:okanzo/data/repository/portfolio_repository.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_theme.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/asset/stock_exchange_field.dart';
import 'package:okanzo/ui/asset/stock_search_field.dart';
import 'package:okanzo/ui/liability/liability_edit_screen.dart';
import 'package:okanzo/ui/theme/theme.dart';

class _OfflineContainer implements AppContainer {
  _OfflineContainer(this._inner)
    : _offlineClient = MockClient(
        (_) async => throw const SocketException('Network is unreachable'),
      );

  final AppContainer _inner;
  final http.Client _offlineClient;

  @override
  AppDatabase get database => _inner.database;
  @override
  SettingsRepository get settingsRepository => _inner.settingsRepository;
  @override
  PortfolioRepository get portfolioRepository => _inner.portfolioRepository;
  @override
  LiabilityRepository get liabilityRepository => _inner.liabilityRepository;
  @override
  BackupRepository get backupRepository => _inner.backupRepository;
  @override
  FxRepository get fxRepository =>
      FxRepository(FxRateDao(database), FxApi(client: _offlineClient));
  @override
  AssetRepository get assetRepository => AssetRepository(
    AssetDao(database),
    StockPriceService(StockApi(client: _offlineClient)),
    fxRepository,
  );
  @override
  StockSearchService get stockSearchService =>
      StockSearchService(client: _offlineClient);
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition,
  String description,
) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 40)) {
      final List<String> feedback = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text text) => text.data ?? '')
          .where(
            (String text) =>
                text.contains('Search unavailable') ||
                text.contains('No matches') ||
                text.contains(' · '),
          )
          .toList();
      fail('Timed out waiting for $description; search feedback: $feedback');
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: description);
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final Finder field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pump(const Duration(milliseconds: 400));
  if (label == 'Company or Ticker' || label == 'Coin or ticker') {
    expect(
      tester.widget<TextField>(field).focusNode!.hasFocus,
      isTrue,
      reason: 'Search input must have focus after entering $value',
    );
    debugPrint(
      'DEVICE CHECK: searching $value; progress=${find.byType(LinearProgressIndicator).evaluate().length}',
    );
  }
}

Finder _listing(String symbol) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is ListTile &&
      widget.subtitle is Text &&
      (((widget.subtitle! as Text).data ?? '') == symbol ||
          ((widget.subtitle! as Text).data ?? '').startsWith('$symbol · ')),
);

String _input(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live company and ticker search works on Android without changing existing data',
    (WidgetTester tester) async {
      final AppContainer container = await AppContainer.create();
      int? testPortfolio;
      final List<int> originalPortfolios =
          (await container.portfolioRepository.getAll())
              .map((portfolio) => portfolio.id)
              .toList();
      final int? originalDefault =
          (await container.portfolioRepository.getDefault())?.id;
      final Map<String, Object?> checks = <String, Object?>{};
      try {
        testPortfolio = await container.portfolioRepository.create(
          'Stock search device test ${DateTime.now().millisecondsSinceEpoch}',
        );
        await tester.pumpWidget(
          AppScope(
            container: container,
            child: MaterialApp(
              theme: buildTheme(
                brightness: Brightness.dark,
                appTheme: AppTheme.midnight,
              ),
              locale: const Locale('en'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Builder(
                builder: (BuildContext context) => Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AssetEditScreen(
                                portfolioId: testPortfolio!,
                                assetId: 0,
                              ),
                            ),
                          ),
                          child: const Text('Open search test editor'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LiabilityEditScreen(
                                portfolioId: testPortfolio!,
                                liabilityId: 0,
                              ),
                            ),
                          ),
                          child: const Text('Open liability test editor'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Open search test editor'));
        await _waitUntil(
          tester,
          () => find
              .widgetWithText(TextField, 'Company or Ticker')
              .evaluate()
              .isNotEmpty,
          'asset editor',
        );

        await _enter(tester, 'Company or Ticker', 'Apple');
        await _waitUntil(
          tester,
          () => _listing('AAPL').evaluate().isNotEmpty,
          'Apple company result',
        );
        expect(_listing('AAPL').hitTestable(), findsOneWidget);
        await _tap(tester, _listing('AAPL'));
        expect(_input(tester, 'Company or Ticker'), 'AAPL');
        expect(_input(tester, 'Custom name (optional)'), isEmpty);
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'Custom name (optional)'),
              )
              .decoration
              ?.hintText
              ?.toLowerCase(),
          contains('apple'),
        );
        expect(
          tester
              .widget<StockExchangeField>(find.byType(StockExchangeField))
              .selected,
          StockExchange.us,
        );
        checks['companySearchAndNameAutofill'] = true;
        debugPrint(
          'DEVICE CHECK: company name resolves to AAPL and hints fetched name while custom name stays optional',
        );

        await _enter(
          tester,
          'Custom name (optional)',
          'My search test holding',
        );
        await _enter(tester, 'Company or Ticker', 'Airbus');
        await _waitUntil(
          tester,
          () => _listing('AIR.PA').evaluate().isNotEmpty,
          'international listing',
        );
        await _tap(tester, _listing('AIR.PA'));
        expect(_input(tester, 'Company or Ticker'), 'AIR.PA');
        expect(
          _input(tester, 'Custom name (optional)'),
          'My search test holding',
        );
        expect(
          tester
              .widget<StockExchangeField>(find.byType(StockExchangeField))
              .selected,
          StockExchange.euronextParis,
        );
        checks['internationalListingAndCustomName'] = true;
        debugPrint(
          'DEVICE CHECK: international result sets Paris and preserves a custom name',
        );

        await _tap(tester, find.byType(PopupMenuButton<AssetType>));
        await _tap(tester, find.text(AssetType.mutualFund.displayName).last);
        expect(
          tester.widget<StockSearchField>(find.byType(StockSearchField)).type,
          StockSearchType.fund,
        );
        await _enter(tester, 'Company or Ticker', 'Vanguard');
        await _waitUntil(
          tester,
          () => _listing('VOO').evaluate().isNotEmpty,
          'fund suggestions',
        );
        await _tap(tester, _listing('VOO'));
        expect(_input(tester, 'Company or Ticker'), 'VOO');
        checks['fundSearch'] = true;
        debugPrint('DEVICE CHECK: fund search resolves Vanguard to VOO');

        await _tap(tester, find.byType(PopupMenuButton<AssetType>));
        await _tap(tester, find.text(AssetType.stock.displayName).last);
        await _enter(tester, 'Company or Ticker', 'AAPL');
        await _waitUntil(
          tester,
          () => _listing('AAPL').evaluate().isNotEmpty,
          'ticker search',
        );
        await _tap(tester, _listing('AAPL'));
        await _enter(tester, 'Quantity', '2');
        await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
        await _waitUntil(
          tester,
          () => find.byType(AssetEditScreen).evaluate().isEmpty,
          'saved asset with automatic price fetch',
        );
        final AssetEntity saved =
            (await container.assetRepository.getForPortfolio(testPortfolio))
                .single;
        expect(saved.symbol, 'AAPL');
        expect(saved.name.toLowerCase(), contains('apple'));
        expect(saved.customName, 'My search test holding');
        expect(saved.displayName, 'My search test holding');
        expect(saved.quantity, 2);
        expect(saved.lastPrice, greaterThan(0));
        checks['tickerSearchLivePriceAndSave'] = true;
        checks['autoFetchPriceOnSave'] = true;
        debugPrint(
          'DEVICE CHECK: ticker search, automatic live quote on Save and encrypted database save succeeded',
        );

        await _tap(tester, find.text('Open search test editor'));
        await _tap(tester, find.byType(PopupMenuButton<AssetType>));
        await _tap(tester, find.text(AssetType.crypto.displayName).last);
        expect(find.byType(StockExchangeField), findsNothing);
        await _enter(tester, 'Coin or ticker', 'Bitcoin');
        await _waitUntil(
          tester,
          () => _listing('BTC-USD').evaluate().isNotEmpty,
          'Bitcoin name search',
        );
        await _tap(tester, _listing('BTC-USD'));
        expect(_input(tester, 'Coin or ticker'), 'BTC-USD');
        expect(_input(tester, 'Custom name (optional)'), isEmpty);
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'Custom name (optional)'),
              )
              .decoration
              ?.hintText
              ?.toLowerCase(),
          contains('bitcoin'),
        );
        await _enter(tester, 'Coin or ticker', 'BTC-EUR');
        await _waitUntil(
          tester,
          () => _listing('BTC-EUR').evaluate().isNotEmpty,
          'explicit non-USD crypto pair',
        );
        await _tap(tester, _listing('BTC-EUR'));
        expect(_input(tester, 'Coin or ticker'), 'BTC-EUR');
        await _enter(tester, 'Quantity', '0.25');
        await _tap(tester, find.text('Fetch latest price'));
        final Finder cryptoSave = find.widgetWithText(FilledButton, 'Save');
        if (cryptoSave.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            cryptoSave,
            120,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await _waitUntil(
          tester,
          () => tester.widget<FilledButton>(cryptoSave).onPressed != null,
          'live crypto price',
        );
        await _tap(tester, cryptoSave);
        await _waitUntil(
          tester,
          () => find.byType(AssetEditScreen).evaluate().isEmpty,
          'saved cryptocurrency',
        );
        final AssetEntity crypto =
            (await container.assetRepository.getForPortfolio(testPortfolio))
                .singleWhere(
                  (AssetEntity asset) => asset.type == AssetType.crypto,
                );
        expect(crypto.symbol, 'BTC-EUR');
        expect(crypto.quantity, 0.25);
        expect(crypto.lastPrice, greaterThan(0));
        checks['cryptoNamePairLivePriceAndSave'] = true;
        debugPrint(
          'DEVICE CHECK: crypto name and non-USD pair search, live price and save succeeded',
        );

        await _tap(tester, find.text('Open search test editor'));
        expect(find.text('Save asset'), findsNothing);
        await _enter(tester, 'Custom name (optional)', 'Unsaved asset');
        await _enter(tester, 'Company or Ticker', 'MSFT');
        await _enter(tester, 'Quantity', '5');
        await _tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
        expect(find.byType(AssetEditScreen), findsNothing);
        expect(
          await container.assetRepository.getForPortfolio(testPortfolio),
          hasLength(2),
        );

        await _tap(tester, find.text('Open liability test editor'));
        expect(find.text('Save liability'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
        await _enter(tester, 'Outstanding amount', '500');
        await _enter(tester, 'Name', 'Unsaved loan');
        await _tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
        expect(find.byType(LiabilityEditScreen), findsNothing);
        expect(
          await container.liabilityRepository.getForPortfolio(testPortfolio),
          isEmpty,
        );
        checks['cancelAndSaveButtonsVerified'] = true;
        debugPrint('DEVICE CHECK: Cancel and Save verified on both forms');

        await tester.pumpWidget(
          AppScope(
            container: _OfflineContainer(container),
            child: MaterialApp(
              theme: buildTheme(
                brightness: Brightness.dark,
                appTheme: AppTheme.midnight,
              ),
              locale: const Locale('en'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Builder(
                builder: (BuildContext context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AssetEditScreen(
                            portfolioId: testPortfolio!,
                            assetId: 0,
                          ),
                        ),
                      ),
                      child: const Text('Open offline editor'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Open offline editor'));
        await _enter(tester, 'Custom name (optional)', 'Offline Microsoft');
        await _enter(tester, 'Company or Ticker', 'MSFT');
        await _waitUntil(
          tester,
          () => find
              .text(
                'No internet connection. Enter a ticker manually to save offline.',
              )
              .evaluate()
              .isNotEmpty,
          'offline search notice',
        );
        await _enter(tester, 'Quantity', '3');
        await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
        await _waitUntil(
          tester,
          () => find.byType(AssetEditScreen).evaluate().isEmpty,
          'offline asset save',
        );
        expect(
          find.text(
            'No internet connection. Saved without latest price — refresh when online.',
          ),
          findsOneWidget,
        );
        final AssetEntity offlineSaved =
            (await container.assetRepository.getForPortfolio(testPortfolio))
                .singleWhere(
                  (AssetEntity asset) =>
                      asset.displayName == 'Offline Microsoft',
                );
        expect(offlineSaved.symbol, 'MSFT');
        expect(offlineSaved.quantity, 3);
        expect(offlineSaved.lastPrice, isNull);
        checks['offlineSaveAndNoticeVerified'] = true;
        debugPrint(
          'DEVICE CHECK: offline manual ticker save and non-intrusive notice succeeded',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        if (testPortfolio != null) {
          await PortfolioDao(container.database).deleteById(testPortfolio);
        }
        expect(
          (await container.portfolioRepository.getAll()).map(
            (portfolio) => portfolio.id,
          ),
          originalPortfolios,
        );
        expect(
          (await container.portfolioRepository.getDefault())?.id,
          originalDefault,
        );
        checks['temporaryDataRemoved'] = true;
        binding.reportData = checks;
        await container.settingsRepository.dispose();
        await container.database.close();
      }
    },
  );
}
