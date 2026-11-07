import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:okanzo/data/local/app_database.dart';
import 'package:okanzo/data/local/dao/asset_dao.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/remote/stock/chart_response.dart';
import 'package:okanzo/data/remote/stock/stock_price_service.dart';
import 'package:okanzo/data/repository/asset_repository.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/asset/asset_edit_view_model.dart';
import 'package:okanzo/ui/asset/stock_exchange_field.dart';
import 'package:okanzo/util/currency_util.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'helpers/fx_test_helpers.dart';

class _AssetDao extends Fake implements AssetDao {
  final List<AssetEntity> assets = <AssetEntity>[];

  @override
  Future<List<AssetEntity>> getForPortfolio(int portfolioId) async => assets
      .where((AssetEntity asset) => asset.portfolioId == portfolioId)
      .toList();

  @override
  Future<AssetEntity?> getById(int id) async {
    for (final AssetEntity asset in assets) {
      if (asset.id == id) return asset;
    }
    return null;
  }

  @override
  Future<int> maxPosition(int portfolioId, AssetType type) async => -1;

  @override
  Future<int> insert(AssetEntity asset) async {
    final int id = assets.length + 1;
    assets.add(asset.copyWith(id: id));
    return id;
  }

  @override
  Future<void> update(AssetEntity asset) async {
    assets[assets.indexWhere((AssetEntity row) => row.id == asset.id)] = asset;
  }

  @override
  Future<void> updatePrice(
    int id,
    double price,
    int timestamp, {
    String? currency,
  }) async {
    final int index = assets.indexWhere((AssetEntity row) => row.id == id);
    assets[index] = assets[index].copyWith(
      lastPrice: price,
      lastPriceTimestamp: timestamp,
      currency: currency,
      updatedAt: timestamp,
    );
  }

  @override
  Future<void> updatePrices(
    List<({int id, double price, int timestamp, String? currency})> updates,
  ) async {
    for (final ({int id, double price, int timestamp, String? currency}) update
        in updates) {
      await updatePrice(
        update.id,
        update.price,
        update.timestamp,
        currency: update.currency,
      );
    }
  }
}

class _Database extends Fake implements Database {
  final List<Map<String, Object?>> updates = <Map<String, Object?>>[];

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    expect(table, Tables.assets);
    expect(where, 'id = ?');
    expect(whereArgs, <Object?>[1]);
    updates.add(values);
    return 1;
  }

  @override
  Future<void> close() async {}
}

class _Container extends Fake implements AppContainer {
  _Container(this.assetRepository, this.settingsRepository);

  @override
  final AssetRepository assetRepository;

  @override
  final SettingsRepository settingsRepository;
}

class _FailingSettingsRepository extends SettingsRepository {
  _FailingSettingsRepository(super.preferences);

  @override
  Future<void> setPreferredExchanges(List<StockExchange> exchanges) async {
    throw StateError('Storage unavailable');
  }
}

AssetEntity _holding(int id, String symbol) => AssetEntity(
  id: id,
  portfolioId: 1,
  type: AssetType.stock,
  name: symbol,
  currency: 'USD',
  symbol: symbol,
  quantity: 2,
  lastPrice: 10,
  createdAt: 1,
  updatedAt: 2,
);

http.Response _quote(double price, [String? currency]) => http.Response(
  jsonEncode(<String, Object?>{
    'chart': <String, Object?>{
      'result': <Object?>[
        <String, Object?>{
          'meta': <String, Object?>{
            'regularMarketPrice': price,
            'currency': ?currency,
          },
        },
      ],
    },
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AssetDao dao;
  late SettingsRepository settings;
  late AssetRepository repository;
  late List<String> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'EUR',
    });
    settings = SettingsRepository(await SharedPreferences.getInstance());
    addTearDown(settings.dispose);
    dao = _AssetDao();
    requests = <String>[];
    repository = AssetRepository(
      dao,
      StockPriceService(
        StockApi(
          client: MockClient((http.Request request) async {
            final String symbol = request.url.pathSegments.last;
            requests.add(symbol);
            for (final StockExchange exchange in StockExchange.values) {
              if (symbol == exchange.qualify(exchange.example)) {
                return _quote(100, exchange.currency);
              }
            }
            return http.Response(
              '{"chart":{"error":{"description":"Symbol not found"}}}',
              404,
            );
          }),
        ),
      ),
      fxRepositoryForTest(),
    );
  });

  AssetEditViewModel editor({int assetId = 0}) {
    final AssetEditViewModel viewModel = AssetEditViewModel(
      assetRepository: repository,
      settingsRepository: settings,
      portfolioId: 1,
      assetId: assetId,
    );
    addTearDown(viewModel.dispose);
    return viewModel;
  }

  test('stock and fund editors fetch and save each exchange listing', () async {
    for (final AssetType type in <AssetType>[
      AssetType.stock,
      AssetType.mutualFund,
    ]) {
      for (final StockExchange exchange in StockExchange.values) {
        if (exchange == StockExchange.other) continue;
        final AssetEditViewModel viewModel = editor();
        viewModel.onTypeChange(type);
        viewModel.onNameChange('Holding');
        viewModel.onQuantityChange('2');
        viewModel.onExchangeChange(exchange);
        await viewModel.onCurrencyChange(exchange.currency!);
        viewModel.onSymbolChange(exchange.example);

        await viewModel.fetchPrice();
        await viewModel.save();

        expect(requests.last, exchange.qualify(exchange.example));
        expect(viewModel.form.lastPrice, 100);
        expect(viewModel.form.estimatedValue, 200);
        expect(viewModel.form.currency, exchange.currency);
        expect(dao.assets.last.symbol, requests.last);
        expect(dao.assets.last.currency, exchange.currency);
        expect(dao.assets.last.type, type);
        expect(viewModel.event?.type, AssetEditEventType.saved);
      }
    }
  });

  test(
    'editing a saved listing retains its exchange and full ticker',
    () async {
      dao.assets.add(_holding(1, '0700.HK').copyWith(currency: 'HKD'));
      final AssetEditViewModel viewModel = editor(assetId: 1);
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.form.exchange, StockExchange.hongKong);
      await viewModel.fetchPrice();
      await viewModel.save();

      expect(requests, <String>['0700.HK']);
      expect(dao.assets.single.symbol, '0700.HK');
      expect(dao.assets.single.currency, 'HKD');
      expect(dao.assets.single.lastPrice, 100);
    },
  );

  test(
    'bulk refresh preserves selected currencies and failed prices',
    () async {
      dao.assets.addAll(<AssetEntity>[
        _holding(1, '0700.HK').copyWith(currency: 'HKD'),
        _holding(2, 'RELIANCE.BO').copyWith(currency: 'INR'),
        _holding(3, 'DELISTED.BO'),
      ]);

      final PriceRefreshResult result = await repository.refreshAllPrices(1);

      expect(result.total, 3);
      expect(result.updated, 2);
      expect(result.failed, 1);
      expect(requests, <String>['0700.HK', 'RELIANCE.BO', 'DELISTED.BO']);
      expect(dao.assets[0].currency, 'HKD');
      expect(dao.assets[1].currency, 'INR');
      expect(dao.assets[0].lastPrice, 100);
      expect(dao.assets[1].lastPriceTimestamp, greaterThan(2));
      expect(dao.assets[2].lastPrice, 10);
      expect(dao.assets[2].currency, 'USD');
      expect(dao.assets[2].updatedAt, 2);
    },
  );

  test(
    'refresh without a quote currency keeps the previous price and currency',
    () async {
      dao.assets.add(_holding(1, '0700.HK').copyWith(currency: 'HKD'));
      final AssetRepository noCurrency = AssetRepository(
        dao,
        StockPriceService(
          StockApi(client: MockClient((http.Request _) async => _quote(200))),
        ),
        fxRepositoryForTest(),
      );

      final result = await noCurrency.refreshPrice(dao.assets.single);

      expect(result.isFailure, isTrue);
      expect(dao.assets.single.currency, 'HKD');
      expect(dao.assets.single.lastPrice, 10);
    },
  );

  test(
    'manual London tickers are saved and refreshed in pounds, not pence',
    () async {
      repository = AssetRepository(
        dao,
        StockPriceService(
          StockApi(
            client: MockClient((http.Request request) async {
              expect(request.url.pathSegments.last, 'VOD.L');
              return _quote(125, 'GBp');
            }),
          ),
        ),
        fxRepositoryForTest(),
      );
      final AssetEditViewModel viewModel = editor();
      viewModel.onNameChange('Vodafone');
      viewModel.onSymbolChange('VOD.L');
      await viewModel.onCurrencyChange('GBP');
      viewModel.onQuantityChange('2');

      await viewModel.fetchPrice();
      await viewModel.save();
      expect(viewModel.form.exchange, StockExchange.other);
      expect(viewModel.form.currency, 'GBP');
      expect(viewModel.form.lastPrice, 1.25);
      expect(dao.assets.single.value, 2.5);

      final AssetEntity cached = dao.assets.single.copyWith(
        lastPrice: 100,
        currency: 'GBP',
      );
      await dao.update(cached);
      await repository.refreshPrice(cached);
      expect(dao.assets.single.lastPrice, 1.25);
      expect(dao.assets.single.currency, 'GBP');
      expect(dao.assets.single.value, 2.5);
    },
  );

  test('failed editor lookup surfaces the error', () async {
    final AssetEditViewModel viewModel = editor();
    viewModel.onExchangeChange(StockExchange.bse);
    viewModel.onSymbolChange('DELISTED');

    await viewModel.fetchPrice();

    expect(requests, <String>['DELISTED.BO']);
    expect(viewModel.form.lastPrice, isNull);
    expect(viewModel.form.isFetchingPrice, isFalse);
    expect(viewModel.event?.type, AssetEditEventType.error);
    expect(viewModel.event?.message, contains('Symbol not found'));
  });

  test('an exchange change discards an in-flight quote', () async {
    final Completer<http.Response> response = Completer<http.Response>();
    repository = AssetRepository(
      dao,
      StockPriceService(
        StockApi(client: MockClient((http.Request _) => response.future)),
      ),
      fxRepositoryForTest(),
    );
    final AssetEditViewModel viewModel = editor();
    viewModel.onExchangeChange(StockExchange.hongKong);
    viewModel.onSymbolChange('0700');
    final Future<void> fetching = viewModel.fetchPrice();
    viewModel.onExchangeChange(StockExchange.bse);
    response.complete(_quote(100, 'HKD'));
    await fetching;

    expect(viewModel.form.quoteSymbol, '0700.BO');
    expect(viewModel.form.currency, 'INR');
    expect(viewModel.form.lastPrice, isNull);
    expect(viewModel.form.isFetchingPrice, isFalse);
    expect(viewModel.event?.message, contains('exchange changed'));
  });

  test(
    'DAO updates currency atomically with the quote, only when supplied',
    () async {
      final _Database database = _Database();
      final AppDatabase appDatabase = AppDatabase(database);
      addTearDown(appDatabase.close);
      final AssetDao assetDao = AssetDao(appDatabase);

      await assetDao.updatePrice(1, 100, 123, currency: 'HKD');
      await assetDao.updatePrice(1, 200, 456);

      expect(database.updates[0], <String, Object?>{
        'lastPrice': 100.0,
        'lastPriceTimestamp': 123,
        'updatedAt': 123,
        'currency': 'HKD',
      });
      expect(database.updates[1], <String, Object?>{
        'lastPrice': 200.0,
        'lastPriceTimestamp': 456,
        'updatedAt': 456,
      });
    },
  );

  testWidgets('editor dropdown qualifies BSE and recognizes full HK tickers', (
    WidgetTester tester,
  ) async {
    await settings.setPreferredExchanges(<StockExchange>[
      StockExchange.us,
      StockExchange.bse,
    ]);
    await tester.pumpWidget(
      AppScope(
        container: _Container(repository, settings),
        child: const MaterialApp(
          home: AssetEditScreen(portfolioId: 1, assetId: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Finder exchangeMenu = find.byType(DropdownMenu<Object>);
    await tester.ensureVisible(exchangeMenu);
    await tester.tap(exchangeMenu);
    await tester.pumpAndSettle();
    final Finder bse = find.text('BSE (India)').last;
    await tester.ensureVisible(bse);
    await tester.tap(bse);
    await tester.pumpAndSettle();

    final Finder ticker = find.widgetWithText(TextField, 'Ticker symbol');
    await tester.ensureVisible(ticker);
    await tester.enterText(ticker, 'RELIANCE');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StockExchangeField>(find.byType(StockExchangeField))
          .selected,
      StockExchange.bse,
    );
    final Finder fetch = find.text('Fetch latest price');
    await tester.ensureVisible(fetch);
    await tester.tap(fetch);
    await tester.pumpAndSettle();
    expect(requests, <String>['RELIANCE.BO']);
    expect(
      find.text('Last price: ${CurrencyUtil.format(100, 'INR')}'),
      findsOneWidget,
    );

    await tester.ensureVisible(ticker);
    await tester.enterText(ticker, '0700.HK');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StockExchangeField>(find.byType(StockExchangeField))
          .selected,
      StockExchange.hongKong,
    );
  });

  testWidgets('cryptocurrency editor has no stock exchange selector', (
    WidgetTester tester,
  ) async {
    dao.assets.add(_holding(1, 'BTC-USD').copyWith(type: AssetType.crypto));
    await tester.pumpWidget(
      AppScope(
        container: _Container(repository, settings),
        child: const MaterialApp(
          home: AssetEditScreen(portfolioId: 1, assetId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StockExchangeField), findsNothing);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Ticker symbol'))
          .controller
          ?.text,
      'BTC-USD',
    );
  });

  testWidgets(
    'currency picker converts the price and fetch preserves selection',
    (WidgetTester tester) async {
      dao.assets.add(_holding(1, 'AAPL'));
      await tester.pumpWidget(
        AppScope(
          container: _Container(repository, settings),
          child: const MaterialApp(
            home: AssetEditScreen(portfolioId: 1, assetId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final Finder currency = find.text(
        'USD — ${CurrencyUtil.displayName('USD')}',
      );
      await tester.ensureVisible(currency);
      await tester.tap(currency);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('EUR — ${CurrencyUtil.displayName('EUR')}').last,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('EUR — ${CurrencyUtil.displayName('EUR')}'),
        findsOneWidget,
      );
      expect(
        find.text('Last price: ${CurrencyUtil.format(5, 'EUR')}'),
        findsOneWidget,
      );
      final Finder fetch = find.text('Fetch latest price');
      await tester.ensureVisible(fetch);
      await tester.tap(fetch);
      await tester.pumpAndSettle();

      expect(requests, <String>['AAPL']);
      expect(
        find.text('Last price: ${CurrencyUtil.format(50, 'EUR')}'),
        findsOneWidget,
      );
      expect(
        find.text('EUR — ${CurrencyUtil.displayName('EUR')}'),
        findsOneWidget,
      );
      expect(find.text(CurrencyUtil.format(100, 'EUR')), findsOneWidget);
    },
  );

  Future<void> openEditor(WidgetTester tester, {int assetId = 0}) async {
    await tester.pumpWidget(
      AppScope(
        container: _Container(repository, settings),
        child: MaterialApp(
          home: AssetEditScreen(portfolioId: 1, assetId: assetId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> menuLabels(WidgetTester tester) => tester
      .widget<DropdownMenu<Object>>(find.byType(DropdownMenu<Object>))
      .dropdownMenuEntries
      .map((DropdownMenuEntry<Object> entry) => entry.label)
      .toList();

  Future<void> openPreferences(WidgetTester tester) async {
    final Finder menu = find.byType(DropdownMenu<Object>);
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text(StockExchangeField.manageLabel).last);
    await tester.pumpAndSettle();
    expect(find.text('Preferred exchanges'), findsOneWidget);
  }

  Future<void> togglePreference(
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
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
  }

  Future<void> savePreferences(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Save'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('default dropdown has only US and the final preference action', (
    WidgetTester tester,
  ) async {
    await openEditor(tester);

    expect(menuLabels(tester), <String>[
      StockExchange.us.displayName,
      StockExchangeField.manageLabel,
    ]);
  });

  testWidgets('checkbox preferences update the dropdown and persist', (
    WidgetTester tester,
  ) async {
    await openEditor(tester);
    await openPreferences(tester);
    await togglePreference(tester, StockExchange.bse);
    await savePreferences(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(menuLabels(tester), <String>[
      StockExchange.us.displayName,
      StockExchange.bse.displayName,
      StockExchangeField.manageLabel,
    ]);
    expect(settings.current.preferredExchanges, <StockExchange>[
      StockExchange.us,
      StockExchange.bse,
    ]);
    expect(
      tester
          .widget<DropdownMenu<Object>>(find.byType(DropdownMenu<Object>))
          .controller
          ?.text,
      StockExchange.us.displayName,
    );
  });

  testWidgets('cancel and dismiss do not save checkbox changes', (
    WidgetTester tester,
  ) async {
    await openEditor(tester);
    await openPreferences(tester);
    await togglePreference(tester, StockExchange.us);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.current.preferredExchanges, <StockExchange>[
      StockExchange.us,
    ]);

    await openPreferences(tester);
    await togglePreference(tester, StockExchange.us);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(settings.current.preferredExchanges, <StockExchange>[
      StockExchange.us,
    ]);
  });

  testWidgets(
    'none selected leaves only the management option and no selection',
    (WidgetTester tester) async {
      await openEditor(tester);
      await openPreferences(tester);
      await togglePreference(tester, StockExchange.us);
      await savePreferences(tester);

      expect(settings.current.preferredExchanges, isEmpty);
      expect(menuLabels(tester), <String>[StockExchangeField.manageLabel]);
      expect(
        tester
            .widget<StockExchangeField>(find.byType(StockExchangeField))
            .selected,
        isNull,
      );
      await openPreferences(tester);
      await togglePreference(tester, StockExchange.bse);
      await savePreferences(tester);
      expect(menuLabels(tester), <String>[
        StockExchange.bse.displayName,
        StockExchangeField.manageLabel,
      ]);
      expect(
        tester
            .widget<StockExchangeField>(find.byType(StockExchangeField))
            .selected,
        StockExchange.bse,
      );
    },
  );

  testWidgets('removing a saved holding exchange does not change its quote', (
    WidgetTester tester,
  ) async {
    dao.assets.add(_holding(1, '0700.HK').copyWith(currency: 'HKD'));
    await settings.setPreferredExchanges(<StockExchange>[
      StockExchange.us,
      StockExchange.hongKong,
    ]);
    await openEditor(tester, assetId: 1);
    await openPreferences(tester);
    await togglePreference(tester, StockExchange.hongKong);
    await savePreferences(tester);

    expect(menuLabels(tester), <String>[
      StockExchange.us.displayName,
      StockExchangeField.manageLabel,
    ]);
    final DropdownMenu<Object> menu = tester.widget<DropdownMenu<Object>>(
      find.byType(DropdownMenu<Object>),
    );
    expect(menu.controller?.text, StockExchange.hongKong.displayName);
    expect(
      find.text('Last price: ${CurrencyUtil.format(10, 'HKD')}'),
      findsOneWidget,
    );
    final Finder ticker = find.widgetWithText(TextField, 'Ticker symbol');
    expect(tester.widget<TextField>(ticker).controller?.text, '0700.HK');
  });

  testWidgets(
    'funds use the same shortlist and blank forms use its first exchange',
    (WidgetTester tester) async {
      await settings.setPreferredExchanges(<StockExchange>[StockExchange.bse]);
      await openEditor(tester);
      expect(
        tester
            .widget<StockExchangeField>(find.byType(StockExchangeField))
            .selected,
        StockExchange.bse,
      );
      final Finder typeMenu = find.byType(DropdownMenu<AssetType>);
      await tester.tap(typeMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AssetType.mutualFund.displayName).last);
      await tester.pumpAndSettle();

      expect(menuLabels(tester), <String>[
        StockExchange.bse.displayName,
        StockExchangeField.manageLabel,
      ]);
    },
  );

  testWidgets('failed preference save is visible and keeps the dialog open', (
    WidgetTester tester,
  ) async {
    settings = _FailingSettingsRepository(
      await SharedPreferences.getInstance(),
    );
    addTearDown(settings.dispose);
    await openEditor(tester);
    await openPreferences(tester);
    await togglePreference(tester, StockExchange.us);
    await savePreferences(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.textContaining("Couldn't save preferred exchanges:"),
      findsOneWidget,
    );
    expect(settings.current.preferredExchanges, <StockExchange>[
      StockExchange.us,
    ]);
    expect(find.widgetWithText(TextButton, 'Save'), findsWidgets);
  });
}
