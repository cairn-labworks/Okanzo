import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:okanzo/data/local/dao/fx_rate_dao.dart';
import 'package:okanzo/data/local/entity/fx_rate_entity.dart';
import 'package:okanzo/data/remote/fx/fx_api.dart';
import 'package:okanzo/data/repository/fx_repository.dart';

class FakeFxRateDao extends Fake implements FxRateDao {
  FakeFxRateDao(Map<String, double> rates)
    : _rates = <String, FxRateEntity>{
        for (final MapEntry<String, double> rate in rates.entries)
          rate.key: FxRateEntity(
            currency: rate.key,
            unitsPerUsd: rate.value,
            timestamp: 1,
          ),
      };

  final Map<String, FxRateEntity> _rates;
  int getAllCalls = 0;
  int upsertCalls = 0;

  @override
  Future<List<FxRateEntity>> getAll() async {
    getAllCalls++;
    return _rates.values.toList();
  }

  @override
  Future<void> upsertAll(List<FxRateEntity> rates) async {
    upsertCalls++;
    for (final FxRateEntity rate in rates) {
      _rates[rate.currency] = rate;
    }
  }

  @override
  Future<int?> latestTimestamp() async => _rates.isEmpty
      ? null
      : _rates.values
            .map((FxRateEntity r) => r.timestamp)
            .reduce((int a, int b) => a > b ? a : b);
}

FxRepository fxRepositoryForTest({
  Map<String, double> rates = const <String, double>{
    'EUR': 0.5,
    'GBP': 0.75,
    'INR': 80,
    'HKD': 8,
  },
  http.Client? client,
}) => FxRepository(
  FakeFxRateDao(rates),
  FxApi(
    client: client ?? MockClient((_) async => http.Response('Offline', 503)),
  ),
);
