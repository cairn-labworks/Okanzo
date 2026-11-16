import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/dao/portfolio_dao.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/remote/stock/stock_search_service.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_theme.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/asset/stock_exchange_field.dart';
import 'package:okanzo/ui/asset/stock_search_field.dart';
import 'package:okanzo/ui/theme/theme.dart';

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
  if (label == 'Company or ticker' || label == 'Coin or ticker') {
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
                    child: TextButton(
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
              .widgetWithText(TextField, 'Company or ticker')
              .evaluate()
              .isNotEmpty,
          'asset editor',
        );

        await _enter(tester, 'Company or ticker', 'Apple');
        await _waitUntil(
          tester,
          () => _listing('AAPL').evaluate().isNotEmpty,
          'Apple company result',
        );
        expect(_listing('AAPL').hitTestable(), findsOneWidget);
        await _tap(tester, _listing('AAPL'));
        expect(_input(tester, 'Company or ticker'), 'AAPL');
        expect(_input(tester, 'Name').toLowerCase(), contains('apple'));
        expect(
          tester
              .widget<StockExchangeField>(find.byType(StockExchangeField))
              .selected,
          StockExchange.us,
        );
        checks['companySearchAndNameAutofill'] = true;
        debugPrint(
          'DEVICE CHECK: company name resolves to AAPL and fills the name',
        );

        await _enter(tester, 'Name', 'My search test holding');
        await _enter(tester, 'Company or ticker', 'Airbus');
        await _waitUntil(
          tester,
          () => _listing('AIR.PA').evaluate().isNotEmpty,
          'international listing',
        );
        await _tap(tester, _listing('AIR.PA'));
        expect(_input(tester, 'Company or ticker'), 'AIR.PA');
        expect(_input(tester, 'Name'), 'My search test holding');
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
        await _enter(tester, 'Company or ticker', 'Vanguard');
        await _waitUntil(
          tester,
          () => _listing('VOO').evaluate().isNotEmpty,
          'fund suggestions',
        );
        await _tap(tester, _listing('VOO'));
        expect(_input(tester, 'Company or ticker'), 'VOO');
        checks['fundSearch'] = true;
        debugPrint('DEVICE CHECK: fund search resolves Vanguard to VOO');

        await _tap(tester, find.byType(PopupMenuButton<AssetType>));
        await _tap(tester, find.text(AssetType.stock.displayName).last);
        await _enter(tester, 'Company or ticker', 'AAPL');
        await _waitUntil(
          tester,
          () => _listing('AAPL').evaluate().isNotEmpty,
          'ticker search',
        );
        await _tap(tester, _listing('AAPL'));
        await _enter(tester, 'Quantity', '2');
        await _tap(tester, find.text('Fetch latest price'));
        await _waitUntil(
          tester,
          () =>
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Save asset'),
                  )
                  .onPressed !=
              null,
          'live price fetch',
        );
        await _tap(tester, find.text('Save asset'));
        await _waitUntil(
          tester,
          () => find.byType(AssetEditScreen).evaluate().isEmpty,
          'saved asset',
        );
        final AssetEntity saved =
            (await container.assetRepository.getForPortfolio(testPortfolio))
                .single;
        expect(saved.symbol, 'AAPL');
        expect(saved.name, 'My search test holding');
        expect(saved.quantity, 2);
        expect(saved.lastPrice, greaterThan(0));
        checks['tickerSearchLivePriceAndSave'] = true;
        debugPrint(
          'DEVICE CHECK: ticker search, live quote and encrypted database save succeeded',
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
        expect(_input(tester, 'Name').toLowerCase(), contains('bitcoin'));
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
        await _waitUntil(
          tester,
          () =>
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Save asset'),
                  )
                  .onPressed !=
              null,
          'live crypto price',
        );
        await _tap(tester, find.text('Save asset'));
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
