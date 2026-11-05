import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:okanzo/data/local/dao/asset_dao.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/remote/stock/chart_response.dart';
import 'package:okanzo/data/remote/stock/stock_price_service.dart';
import 'package:okanzo/data/repository/asset_repository.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/ui/asset/asset_edit_view_model.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AssetDao implements AssetDao {
  _AssetDao([this.assets = const <AssetEntity>[]]);

  final List<AssetEntity> assets;
  final Map<int, double> updatedPrices = <int, double>{};

  @override
  Future<List<AssetEntity>> getForPortfolio(int portfolioId) async => assets
      .where((AssetEntity asset) => asset.portfolioId == portfolioId)
      .toList();

  @override
  Future<void> updatePrice(int id, double price, int timestamp) async {
    updatedPrices[id] = price;
    expect(timestamp, greaterThan(0));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    repository = AssetRepository(
      dao,
      StockPriceService(
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
            final double price = symbol == 'BTC-USD' ? 90000 : 36;
            return http.Response(
              jsonEncode(<String, Object?>{
                'chart': <String, Object?>{
                  'result': <Object?>[
                    <String, Object?>{
                      'meta': <String, Object?>{
                        'regularMarketPrice': price,
                        'currency': 'USD',
                      },
                    },
                  ],
                },
              }),
              200,
            );
          }),
        ),
      ),
    );
  });

  test('refreshes existing bare crypto holdings with the USD pair', () async {
    final Result<double> result = await repository.refreshPrice(
      dao.assets.first,
    );

    expect(result.value, 90000);
    expect(requestedSymbols, <String>['BTC-USD']);
    expect(dao.updatedPrices, <int, double>{1: 90000});
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
    },
  );

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
