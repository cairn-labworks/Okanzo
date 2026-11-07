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
import 'package:okanzo/data/repository/fx_repository.dart';
import 'package:okanzo/data/repository/net_worth_calculator.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/ui/asset/asset_edit_view_model.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'helpers/fx_test_helpers.dart';

class _AssetDao implements AssetDao {
  _AssetDao([List<AssetEntity> assets = const <AssetEntity>[]])
    : assets = List<AssetEntity>.of(assets);

  final List<AssetEntity> assets;
  final Map<int, double> updatedPrices = <int, double>{};
  final Map<int, String?> updatedCurrencies = <int, String?>{};

  @override
  Future<AssetEntity?> getById(int id) async =>
      assets.where((AssetEntity asset) => asset.id == id).firstOrNull;

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
    final int index = assets.indexWhere((AssetEntity asset) => asset.id == id);
    if (index >= 0) {
      assets[index] = assets[index].copyWith(
        lastPrice: price,
        lastPriceTimestamp: timestamp,
        updatedAt: timestamp,
        currency: currency,
      );
    }
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

Future<AssetEditViewModel> _editor(
  AssetRepository repository, {
  int assetId = 0,
}) async {
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
    assetId: assetId,
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
  late FxRepository fxRepository;
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
    fxRepository = fxRepositoryForTest();
    repository = AssetRepository(dao, priceService, fxRepository);
  });

  for (final AssetType type in <AssetType>[
    AssetType.crypto,
    AssetType.stock,
    AssetType.mutualFund,
  ]) {
    test('$type fetch keeps EUR and converts the quote value', () async {
      final AssetEditViewModel viewModel = await _editor(repository);
      viewModel.onTypeChange(type);
      viewModel.onSymbolChange('BTC');
      viewModel.onQuantityChange('2');

      await viewModel.fetchPrice();

      expect(viewModel.form.currency, 'EUR');
      expect(viewModel.form.lastPrice, type == AssetType.crypto ? 45000 : 18);
      expect(
        viewModel.form.estimatedValue,
        type == AssetType.crypto ? 90000 : 36,
      );
    });
  }

  test(
    'changing currency converts rather than relabels a fetched price',
    () async {
      final AssetEditViewModel viewModel = await _editor(repository);
      viewModel.onTypeChange(AssetType.crypto);
      viewModel.onSymbolChange('BTC');
      await viewModel.fetchPrice();

      await viewModel.onCurrencyChange('GBP');

      expect(viewModel.form.currency, 'GBP');
      expect(viewModel.form.lastPrice, 67500);
    },
  );

  test('refresh keeps EUR and converts a USD crypto quote', () async {
    final AssetEntity asset = _asset(
      1,
      AssetType.crypto,
      'BTC',
    ).copyWith(currency: 'EUR');

    final Result<double> result = await repository.refreshPrice(asset);

    expect(result.value, 45000);
    expect(dao.updatedCurrencies[1], 'EUR');
    expect(dao.updatedPrices[1], 45000);
  });

  test(
    'currency selection survives save, reopen and repeated refreshes',
    () async {
      final AssetEditViewModel viewModel = await _editor(repository);
      viewModel.onNameChange('Bitcoin');
      viewModel.onTypeChange(AssetType.crypto);
      viewModel.onSymbolChange('BTC-USD');
      viewModel.onQuantityChange('2');
      await viewModel.fetchPrice();
      final int? timestamp = viewModel.form.lastPriceTimestamp;

      await viewModel.onCurrencyChange('GBP');
      expect(viewModel.form.lastPriceTimestamp, timestamp);
      await viewModel.save();
      final AssetEntity saved = dao.assets.last;
      expect(saved.currency, 'GBP');
      expect(saved.lastPrice, 67500);
      expect(saved.symbol, 'BTC-USD');

      final AssetEditViewModel reopened = await _editor(
        repository,
        assetId: saved.id,
      );
      await Future<void>.delayed(Duration.zero);
      expect(reopened.form.currency, 'GBP');
      expect(reopened.form.estimatedValue, 135000);
      await reopened.fetchPrice();
      expect(reopened.form.lastPrice, 67500);
      expect(reopened.form.currency, 'GBP');

      await repository.refreshPrice(saved);
      await repository.refreshPrice(dao.assets.last);
      expect(dao.assets.last.currency, 'GBP');
      expect(dao.assets.last.lastPrice, 67500);
      expect(
        const NetWorthCalculator()
            .calculate(
              assets: <AssetEntity>[dao.assets.last],
              liabilities: const <LiabilityEntity>[],
              baseCurrency: 'EUR',
              converter: const CurrencyConverter(<String, double>{
                'EUR': 0.5,
                'GBP': 0.75,
              }),
            )
            .totalAssets,
        90000,
      );
    },
  );

  test(
    'currency changes round trip without compounding quote conversions',
    () async {
      final AssetEditViewModel viewModel = await _editor(repository);
      viewModel.onTypeChange(AssetType.crypto);
      viewModel.onSymbolChange('BTC');
      await viewModel.fetchPrice();

      await viewModel.onCurrencyChange('GBP');
      expect(viewModel.form.lastPrice, 67500);
      await viewModel.onCurrencyChange('USD');
      expect(viewModel.form.lastPrice, 90000);
      await viewModel.onCurrencyChange('EUR');
      expect(viewModel.form.lastPrice, 45000);
      await viewModel.fetchPrice();
      expect(viewModel.form.lastPrice, 45000);
      expect(viewModel.form.currency, 'EUR');
    },
  );

  test(
    'failed currency conversion keeps both cached price and currency',
    () async {
      final AssetEditViewModel viewModel = await _editor(repository);
      viewModel.onSymbolChange('BTC');
      await viewModel.fetchPrice();
      final int? timestamp = viewModel.form.lastPriceTimestamp;

      await viewModel.onCurrencyChange('XYZ');

      expect(viewModel.form.currency, 'EUR');
      expect(viewModel.form.lastPrice, 18);
      expect(viewModel.form.lastPriceTimestamp, timestamp);
      expect(viewModel.form.isFetchingPrice, isFalse);
      expect(viewModel.event?.type, AssetEditEventType.error);
      expect(viewModel.event?.message, contains("Couldn't convert currency"));
    },
  );

  test('failed refresh conversion leaves the stored price untouched', () async {
    final AssetEntity asset = _asset(
      1,
      AssetType.crypto,
      'BTC',
    ).copyWith(currency: 'XYZ');

    final Result<double> result = await repository.refreshPrice(asset);

    expect(result.isFailure, isTrue);
    expect(dao.updatedPrices, isEmpty);
    expect(dao.updatedCurrencies, isEmpty);
  });

  test(
    'bulk refresh counts conversion failures without changing cached prices',
    () async {
      dao.assets.add(
        _asset(7, AssetType.stock, 'BTC').copyWith(currency: 'XYZ'),
      );

      final PriceRefreshResult result = await repository.refreshAllPrices(1);

      expect(result.total, 6);
      expect(result.updated, 4);
      expect(result.failed, 2);
      expect(dao.assets.last.currency, 'XYZ');
      expect(dao.assets.last.lastPrice, 36);
      expect(dao.updatedPrices.containsKey(7), isFalse);
    },
  );

  test(
    'currency changes without a quote do not require exchange rates',
    () async {
      final AssetEditViewModel viewModel = await _editor(repository);

      await viewModel.onCurrencyChange('XYZ');

      expect(viewModel.form.currency, 'XYZ');
      expect(viewModel.form.lastPrice, isNull);
      expect(viewModel.event, isNull);
      expect(requestedSymbols, isEmpty);
    },
  );

  test('manual asset currency changes preserve user-entered values', () async {
    final AssetEditViewModel viewModel = await _editor(repository);
    viewModel.onTypeChange(AssetType.cash);
    viewModel.onManualValueChange('123');

    await viewModel.onCurrencyChange('GBP');

    expect(viewModel.form.currency, 'GBP');
    expect(viewModel.form.estimatedValue, 123);
    expect(viewModel.form.manualValue, '123');
  });

  test(
    'currency changes discard a quote fetched for the previous selection',
    () async {
      final Completer<http.Response> response = Completer<http.Response>();
      final AssetEditViewModel viewModel = await _editor(
        AssetRepository(
          dao,
          StockPriceService(
            StockApi(client: MockClient((_) => response.future)),
          ),
          fxRepository,
        ),
      );
      viewModel.onSymbolChange('BTC');
      final Future<void> fetching = viewModel.fetchPrice();

      await viewModel.onCurrencyChange('GBP');
      response.complete(
        http.Response(
          '{"chart":{"result":[{"meta":{"regularMarketPrice":36,"currency":"USD"}}]}}',
          200,
        ),
      );
      await fetching;

      expect(viewModel.form.currency, 'GBP');
      expect(viewModel.form.lastPrice, isNull);
      expect(viewModel.form.isFetchingPrice, isFalse);
    },
  );

  test('type changes discard an in-flight currency conversion', () async {
    final Completer<http.Response> response = Completer<http.Response>();
    final AssetEditViewModel viewModel = await _editor(
      AssetRepository(
        dao,
        priceService,
        fxRepositoryForTest(
          rates: const <String, double>{'EUR': 0.5},
          client: MockClient((_) => response.future),
        ),
      ),
    );
    viewModel.onSymbolChange('BTC');
    await viewModel.fetchPrice();
    final Future<void> converting = viewModel.onCurrencyChange('GBP');
    viewModel.onTypeChange(AssetType.crypto);
    response.complete(
      http.Response('{"result":"success","rates":{"EUR":0.5,"GBP":0.75}}', 200),
    );
    await converting;

    expect(viewModel.form.currency, 'EUR');
    expect(viewModel.form.lastPrice, isNull);
    expect(viewModel.form.isFetchingPrice, isFalse);
    expect(viewModel.event, isNull);
  });

  test('save is rejected while a currency conversion is pending', () async {
    final Completer<http.Response> response = Completer<http.Response>();
    final AssetEditViewModel viewModel = await _editor(
      AssetRepository(
        dao,
        priceService,
        fxRepositoryForTest(
          rates: const <String, double>{'EUR': 0.5},
          client: MockClient((_) => response.future),
        ),
      ),
    );
    viewModel.onNameChange('Holding');
    viewModel.onSymbolChange('BTC');
    viewModel.onQuantityChange('2');
    await viewModel.fetchPrice();
    final int count = dao.assets.length;
    final Future<void> converting = viewModel.onCurrencyChange('GBP');
    await viewModel.save();

    expect(viewModel.event?.message, 'Wait for the price update to finish');
    expect(dao.assets.length, count);
    response.complete(http.Response('Offline', 503));
    await converting;
  });

  test(
    'reselecting the original currency cancels a pending conversion',
    () async {
      final Completer<http.Response> response = Completer<http.Response>();
      final AssetEditViewModel viewModel = await _editor(
        AssetRepository(
          dao,
          priceService,
          fxRepositoryForTest(
            rates: const <String, double>{'EUR': 0.5},
            client: MockClient((_) => response.future),
          ),
        ),
      );
      viewModel.onSymbolChange('BTC');
      await viewModel.fetchPrice();
      final Future<void> converting = viewModel.onCurrencyChange('GBP');
      await viewModel.onCurrencyChange('EUR');
      response.complete(
        http.Response(
          '{"result":"success","rates":{"EUR":0.5,"GBP":0.75}}',
          200,
        ),
      );
      await converting;

      expect(viewModel.form.currency, 'EUR');
      expect(viewModel.form.lastPrice, 18);
      expect(viewModel.form.isFetchingPrice, isFalse);
    },
  );

  test(
    'a superseded fetch cannot overwrite the newer price or loading state',
    () async {
      final List<Completer<http.Response>> responses =
          <Completer<http.Response>>[];
      final AssetEditViewModel viewModel = await _editor(
        AssetRepository(
          dao,
          StockPriceService(
            StockApi(
              client: MockClient((_) {
                final Completer<http.Response> response =
                    Completer<http.Response>();
                responses.add(response);
                return response.future;
              }),
            ),
          ),
          fxRepository,
        ),
      );
      viewModel.onSymbolChange('BTC');
      final Future<void> first = viewModel.fetchPrice();
      final Future<void> second = viewModel.fetchPrice();
      await Future<void>.delayed(Duration.zero);
      responses.first.complete(
        http.Response(
          '{"chart":{"result":[{"meta":{"regularMarketPrice":36,"currency":"USD"}}]}}',
          200,
        ),
      );
      await first;
      expect(viewModel.form.isFetchingPrice, isTrue);
      expect(viewModel.form.lastPrice, isNull);
      responses.last.complete(
        http.Response(
          '{"chart":{"result":[{"meta":{"regularMarketPrice":40,"currency":"USD"}}]}}',
          200,
        ),
      );
      await second;

      expect(viewModel.form.lastPrice, 20);
      expect(viewModel.form.currency, 'EUR');
      expect(viewModel.form.isFetchingPrice, isFalse);
    },
  );

  test('failed initial FX lookup does not show an unconverted quote', () async {
    final AssetEditViewModel viewModel = await _editor(
      AssetRepository(
        dao,
        priceService,
        fxRepositoryForTest(rates: const <String, double>{}),
      ),
    );
    viewModel.onSymbolChange('BTC');

    await viewModel.fetchPrice();

    expect(viewModel.form.currency, 'EUR');
    expect(viewModel.form.lastPrice, isNull);
    expect(viewModel.form.isFetchingPrice, isFalse);
    expect(viewModel.event?.type, AssetEditEventType.error);
    expect(viewModel.event?.message, contains('503'));
  });

  test(
    'blank quote currency is rejected instead of assuming a currency',
    () async {
      final AssetRepository noCurrency = AssetRepository(
        dao,
        StockPriceService(
          StockApi(
            client: MockClient(
              (_) async => http.Response(
                '{"chart":{"result":[{"meta":{"regularMarketPrice":36,"currency":""}}]}}',
                200,
              ),
            ),
          ),
        ),
        fxRepository,
      );

      final Result<double> result = await noCurrency.refreshPrice(
        dao.assets.first,
      );

      expect(result.isFailure, isTrue);
      expect(result.errorMessage, contains('Quote currency unavailable'));
      expect(dao.updatedPrices, isEmpty);
    },
  );

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
        'refresh converts USD to $currency (cached price: $lastPrice)',
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
            fxRepository,
          );

          await repository.refreshPrice(AssetEntity.fromMap(storage.row));
          await notified;

          final AssetEntity refreshed = AssetEntity.fromMap(storage.row);
          expect(storage.updates, 1);
          expect(refreshed.currency, currency);
          expect(
            refreshed.lastPrice,
            90000 *
                switch (currency) {
                  'EUR' => 0.5,
                  'GBP' => 0.75,
                  'INR' => 80,
                  _ => throw StateError('Unexpected test currency'),
                },
          );
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
                    'GBP': 0.75,
                    'INR': 80,
                  }),
                )
                .totalAssets,
            45000,
          );
        },
      );
    }
  }

  test(
    'refresh converts an explicit non-USD pair to the holding currency',
    () async {
      final _Database storage = _Database(
        _asset(1, AssetType.crypto, 'BTC-EUR').toMap(),
      );
      final AppDatabase database = AppDatabase(storage);
      addTearDown(database.close);
      final AssetRepository repository = AssetRepository(
        AssetDao(database),
        priceService,
        fxRepository,
      );

      await repository.refreshPrice(AssetEntity.fromMap(storage.row));

      expect(storage.row['currency'], 'USD');
      expect(storage.row['lastPrice'], 160000);
    },
  );

  test(
    'refresh rejects a quote without currency and preserves the cache',
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
        fxRepository,
      );

      final Result<double> result = await repository.refreshPrice(
        AssetEntity.fromMap(storage.row),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorMessage, contains('Quote currency unavailable'));
      expect(storage.row['currency'], 'GBP');
      expect(storage.row['lastPrice'], 36);
      expect(storage.updates, 0);
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

      expect(viewModel.form.lastPrice, 18);
      expect(viewModel.form.lastPriceTimestamp, isNotNull);
      viewModel.onTypeChange(AssetType.crypto);
      expect(viewModel.form.lastPrice, isNull);
      expect(viewModel.form.lastPriceTimestamp, isNull);
      expect(viewModel.form.estimatedValue, 0);
      expect(viewModel.form.validate(), isNull);
      expect(viewModel.form.toEntity().lastPrice, isNull);

      await viewModel.fetchPrice();

      expect(requestedSymbols, <String>['BTC', 'BTC-USD']);
      expect(viewModel.form.lastPrice, 45000);
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

      expect(viewModel.form.lastPrice, 18);
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
        fxRepository,
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

  test('editor fetches a crypto pair in the selected currency', () async {
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
    expect(viewModel.form.lastPrice, 45000);
    expect(viewModel.form.estimatedValue, 45000);
    expect(viewModel.form.currency, 'EUR');
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
