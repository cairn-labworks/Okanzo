import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:okanzo/data/local/app_database.dart';
import 'package:okanzo/data/local/dao/asset_dao.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/data/remote/stock/chart_response.dart';
import 'package:okanzo/data/remote/stock/stock_price_service.dart';
import 'package:okanzo/data/repository/asset_repository.dart';
import 'package:okanzo/data/repository/currency_converter.dart';
import 'package:okanzo/data/repository/net_worth_calculator.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/ui/asset/asset_edit_view_model.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class _AssetDao implements AssetDao {
  _AssetDao([this.assets = const <AssetEntity>[]]);

  final List<AssetEntity> assets;
  final Map<int, double> updatedPrices = <int, double>{};
  final Map<int, String?> updatedCurrencies = <int, String?>{};

  @override
  Future<List<AssetEntity>> getForPortfolio(int portfolioId) async => assets
      .where((AssetEntity asset) => asset.portfolioId == portfolioId)
      .toList();

  @override
  Future<void> updatePrice(
    int id,
    double price,
    int timestamp, {
    String? currency,
  }) async {
    updatedPrices[id] = price;
    updatedCurrencies[id] = currency;
    expect(timestamp, greaterThan(0));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements Database {
  _Database(this.row);

  final Map<String, Object?> row;
  int updates = 0;

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
    expect(whereArgs, <Object?>[row['id']]);
    row.addAll(values);
    updates++;
    return 1;
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AssetEditViewModel> _editor(AssetRepository repository) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'base_currency': 'EUR',
  });
  final SettingsRepository settings = SettingsRepository(
    await SharedPreferences.getInstance(),
  );
  final AssetEditViewModel viewModel = AssetEditViewModel(
    assetRepository: repository,
    settingsRepository: settings,
    portfolioId: 1,
    assetId: 0,
  );
  addTearDown(viewModel.dispose);
  addTearDown(settings.dispose);
  return viewModel;
}

AssetEntity _asset(int id, AssetType type, String symbol) => AssetEntity(
  id: id,
  portfolioId: 1,
  type: type,
  name: symbol,
  currency: 'USD',
  symbol: symbol,
  quantity: 1,
  lastPrice: 36,
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AssetDao dao;
  late AssetRepository repository;
  late StockPriceService priceService;
  late List<String> requestedSymbols;

  setUp(() {
    requestedSymbols = <String>[];
    dao = _AssetDao(<AssetEntity>[
      _asset(1, AssetType.crypto, ' btc '),
      _asset(2, AssetType.stock, 'BTC'),
      _asset(3, AssetType.mutualFund, 'VTI'),
      _asset(4, AssetType.crypto, 'ETH-USD'),
      _asset(5, AssetType.crypto, 'UNKNOWN'),
      _asset(6, AssetType.cash, ''),
    ]);
    priceService = StockPriceService(
      StockApi(
        client: MockClient((http.Request request) async {
          final String symbol = request.url.pathSegments.last;
          requestedSymbols.add(symbol);
          if (symbol == 'UNKNOWN-USD') {
            return http.Response(
              '{"chart":{"error":{"description":"Symbol not found"}}}',
              404,
            );
          }
          final double price = switch (symbol) {
            'BTC-USD' => 90000,
            'BTC-EUR' => 80000,
            _ => 36,
          };
          return http.Response(
            jsonEncode(<String, Object?>{
              'chart': <String, Object?>{
                'result': <Object?>[
                  <String, Object?>{
                    'meta': <String, Object?>{
                      'regularMarketPrice': price,
                      if (symbol != 'NOCURRENCY')
                        'currency': symbol == 'BTC-EUR' ? 'EUR' : 'USD',
                    },
                  },
                ],
              },
            }),
            200,
          );
        }),
      ),
    );
    repository = AssetRepository(dao, priceService);
  });

  test('refreshes existing bare crypto holdings with the USD pair', () async {
    final Result<double> result = await repository.refreshPrice(
      dao.assets.first,
    );

    expect(result.value, 90000);
    expect(requestedSymbols, <String>['BTC-USD']);
    expect(dao.updatedPrices, <int, double>{1: 90000});
    expect(dao.updatedCurrencies, <int, String?>{1: 'USD'});
  });

  test(
    'bulk refresh uses asset types and preserves failed cached prices',
    () async {
      final PriceRefreshResult result = await repository.refreshAllPrices(1);

      expect(requestedSymbols, <String>[
        'BTC-USD',
        'BTC',
        'VTI',
        'ETH-USD',
        'UNKNOWN-USD',
      ]);
      expect(result.total, 5);
      expect(result.updated, 4);
      expect(result.failed, 1);
      expect(dao.updatedPrices, <int, double>{1: 90000, 2: 36, 3: 36, 4: 36});
      expect(dao.updatedCurrencies, <int, String?>{
        1: 'USD',
        2: 'USD',
        3: 'USD',
        4: 'USD',
      });
    },
  );

  for (final String currency in <String>['EUR', 'GBP', 'INR']) {
    for (final double? lastPrice in <double?>[null, 36]) {
      test(
        'refresh replaces $currency with USD (cached price: $lastPrice)',
        () async {
          final AssetEntity asset = _asset(
            1,
            AssetType.crypto,
            'BTC',
          ).copyWith(currency: currency);
          final _Database storage = _Database(
            asset.toMap()..['lastPrice'] = lastPrice,
          );
          final AppDatabase database = AppDatabase(storage);
          addTearDown(database.close);
          final Future<void> notified = expectLater(
            database.changes,
            emits(<String>{Tables.assets}),
          );
          final AssetRepository repository = AssetRepository(
            AssetDao(database),
            priceService,
          );

          await repository.refreshPrice(AssetEntity.fromMap(storage.row));
          await notified;

          final AssetEntity refreshed = AssetEntity.fromMap(storage.row);
          expect(storage.updates, 1);
          expect(refreshed.currency, 'USD');
          expect(refreshed.lastPrice, 90000);
          expect(refreshed.lastPriceTimestamp, greaterThan(0));
          expect(refreshed.updatedAt, refreshed.lastPriceTimestamp);
          expect(refreshed.name, asset.name);
          expect(refreshed.symbol, 'BTC');
          expect(
            const NetWorthCalculator()
                .calculate(
                  assets: <AssetEntity>[refreshed],
                  liabilities: const <LiabilityEntity>[],
                  baseCurrency: 'EUR',
                  converter: const CurrencyConverter(<String, double>{
                    'EUR': 0.5,
                  }),
                )
                .totalAssets,
            45000,
          );
        },
      );
    }
  }

  test('refresh persists the currency of an explicit non-USD pair', () async {
    final _Database storage = _Database(
      _asset(1, AssetType.crypto, 'BTC-EUR').toMap(),
    );
    final AppDatabase database = AppDatabase(storage);
    addTearDown(database.close);
    final AssetRepository repository = AssetRepository(
      AssetDao(database),
      priceService,
    );

    await repository.refreshPrice(AssetEntity.fromMap(storage.row));

    expect(storage.row['currency'], 'EUR');
    expect(storage.row['lastPrice'], 80000);
  });

  test(
    'refresh preserves the holding currency when the quote omits it',
    () async {
      final _Database storage = _Database(
        _asset(
          1,
          AssetType.stock,
          'NOCURRENCY',
        ).copyWith(currency: 'GBP').toMap(),
      );
      final AppDatabase database = AppDatabase(storage);
      addTearDown(database.close);
      final AssetRepository repository = AssetRepository(
        AssetDao(database),
        priceService,
      );

      await repository.refreshPrice(AssetEntity.fromMap(storage.row));

      expect(storage.row['currency'], 'GBP');
      expect(storage.row['lastPrice'], 36);
    },
  );

  test(
    'an empty quote currency does not overwrite the holding currency',
    () async {
      final _Database storage = _Database(
        _asset(1, AssetType.crypto, 'BTC').copyWith(currency: 'EUR').toMap(),
      );
      final AppDatabase database = AppDatabase(storage);
      addTearDown(database.close);

      await AssetDao(database).updatePrice(1, 90000, 123, currency: '');

      expect(storage.row['currency'], 'EUR');
      expect(storage.row['lastPrice'], 90000);
      expect(storage.row['lastPriceTimestamp'], 123);
      expect(storage.row['updatedAt'], 123);
    },
  );

  test(
    'type changes clear prices and timestamps from the previous lookup',
    () async {
      final AssetEditViewModel viewModel = await _editor(repository);
      viewModel.onNameChange('Bitcoin');
      viewModel.onSymbolChange('BTC');
      viewModel.onQuantityChange('1');

      await viewModel.fetchPrice();

      expect(viewModel.form.lastPrice, 36);
      expect(viewModel.form.lastPriceTimestamp, isNotNull);
      viewModel.onTypeChange(AssetType.crypto);
      expect(viewModel.form.lastPrice, isNull);
      expect(viewModel.form.lastPriceTimestamp, isNull);
      expect(viewModel.form.estimatedValue, 0);
      expect(viewModel.form.validate(), isNull);
      expect(viewModel.form.toEntity().lastPrice, isNull);

      await viewModel.fetchPrice();

      expect(requestedSymbols, <String>['BTC', 'BTC-USD']);
      expect(viewModel.form.lastPrice, 90000);
      viewModel.onTypeChange(AssetType.stock);
      expect(viewModel.form.lastPrice, isNull);
      expect(viewModel.form.lastPriceTimestamp, isNull);
    },
  );

  test(
    'selecting the current type preserves its valid fetched quote',
    () async {
      final AssetEditViewModel viewModel = await _editor(repository);
      viewModel.onSymbolChange('BTC');
      await viewModel.fetchPrice();
      final int? timestamp = viewModel.form.lastPriceTimestamp;

      viewModel.onTypeChange(AssetType.stock);

      expect(viewModel.form.lastPrice, 36);
      expect(viewModel.form.lastPriceTimestamp, timestamp);
    },
  );

  test('a type change also discards a quote that is still in flight', () async {
    final Completer<http.Response> response = Completer<http.Response>();
    final AssetEditViewModel viewModel = await _editor(
      AssetRepository(
        dao,
        StockPriceService(
          StockApi(client: MockClient((http.Request _) => response.future)),
        ),
      ),
    );
    viewModel.onSymbolChange('BTC');
    final Future<void> fetching = viewModel.fetchPrice();
    expect(viewModel.form.isFetchingPrice, isTrue);
    viewModel.onTypeChange(AssetType.crypto);
    response.complete(
      http.Response(
        '{"chart":{"result":[{"meta":{"regularMarketPrice":36,"currency":"USD"}}]}}',
        200,
      ),
    );

    await fetching;

    expect(viewModel.form.lastPrice, isNull);
    expect(viewModel.form.lastPriceTimestamp, isNull);
    expect(viewModel.form.currency, 'EUR');
    expect(viewModel.form.isFetchingPrice, isFalse);
    expect(viewModel.event, isNull);
  });

  test('editor fetches a crypto pair and adopts its quote currency', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'EUR',
    });
    final SettingsRepository settings = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    final AssetEditViewModel viewModel = AssetEditViewModel(
      assetRepository: repository,
      settingsRepository: settings,
      portfolioId: 1,
      assetId: 0,
    );
    addTearDown(viewModel.dispose);
    addTearDown(settings.dispose);
    viewModel.onTypeChange(AssetType.crypto);
    viewModel.onSymbolChange('BTC');
    viewModel.onQuantityChange('1');

    await viewModel.fetchPrice();

    expect(requestedSymbols, <String>['BTC-USD']);
    expect(viewModel.form.lastPrice, 90000);
    expect(viewModel.form.estimatedValue, 90000);
    expect(viewModel.form.currency, 'USD');
    expect(viewModel.form.isFetchingPrice, isFalse);
    expect(viewModel.form.toEntity().type, AssetType.crypto);
  });

  test(
    'editor surfaces a failed crypto lookup without replacing its price',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'base_currency': 'USD',
      });
      final SettingsRepository settings = SettingsRepository(
        await SharedPreferences.getInstance(),
      );
      final AssetEditViewModel viewModel = AssetEditViewModel(
        assetRepository: repository,
        settingsRepository: settings,
        portfolioId: 1,
        assetId: 0,
      );
      addTearDown(viewModel.dispose);
      addTearDown(settings.dispose);
      viewModel.onTypeChange(AssetType.crypto);
      viewModel.onSymbolChange('UNKNOWN');

      await viewModel.fetchPrice();

      expect(requestedSymbols, <String>['UNKNOWN-USD']);
      expect(viewModel.form.lastPrice, isNull);
      expect(viewModel.form.isFetchingPrice, isFalse);
      expect(viewModel.event?.type, AssetEditEventType.error);
      expect(viewModel.event?.message, contains('Symbol not found'));
      expect(dao.updatedPrices, isEmpty);
    },
  );
}
