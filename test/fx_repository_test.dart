import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:okanzo/data/remote/fx/fx_api.dart';
import 'package:okanzo/data/repository/fx_repository.dart';
import 'package:okanzo/util/result.dart';

import 'helpers/fx_test_helpers.dart';

void main() {
  test('converts from cached rates without a network request', () async {
    final FxRepository repository = fxRepositoryForTest(
      client: MockClient((_) async => throw StateError('Unexpected request')),
    );

    expect((await repository.convertAmount(100, 'USD', 'EUR')).value, 50);
    expect((await repository.convertAmount(50, 'EUR', 'GBP')).value, 75);
    expect((await repository.convertAmount(75, 'GBP', 'USD')).value, 100);
  });

  test('same currency needs neither cached rates nor network', () async {
    final FxRepository repository = fxRepositoryForTest(
      rates: const <String, double>{},
      client: MockClient((_) async => throw StateError('Unexpected request')),
    );

    expect((await repository.convertAmount(100, 'EUR', 'EUR')).value, 100);
  });

  test(
    'fetches missing rates and caches them for subsequent conversions',
    () async {
      int requests = 0;
      final FxRepository repository = fxRepositoryForTest(
        rates: const <String, double>{},
        client: MockClient((http.Request request) async {
          requests++;
          expect(request.url.path, '/v6/latest/USD');
          return http.Response(
            jsonEncode(<String, Object>{
              'result': 'success',
              'rates': <String, double>{'EUR': 0.5, 'GBP': 0.75},
            }),
            200,
          );
        }),
      );

      expect((await repository.convertAmount(100, 'USD', 'EUR')).value, 50);
      expect((await repository.convertAmount(50, 'EUR', 'GBP')).value, 75);
      expect(requests, 1);
      expect((await repository.currentConverter()).canConvert('GBP'), isTrue);
    },
  );

  test('missing rates plus a failed fetch never return a 1:1 price', () async {
    final result = await fxRepositoryForTest(rates: const <String, double>{})
        .convertAmount(100, 'USD', 'EUR');

    expect(result.isFailure, isTrue);
    expect(result.errorMessage, contains('503'));
  });

  for (final double rate in <double>[0, -1, double.nan, double.infinity]) {
    test('rejects unusable cached FX rate $rate', () async {
      final result = await fxRepositoryForTest(
        rates: <String, double>{'EUR': rate},
      ).convertAmount(100, 'USD', 'EUR');

      expect(result.isFailure, isTrue);
    });
  }

  test(
    'a successful response must contain both conversion currencies',
    () async {
      final result = await fxRepositoryForTest(
        rates: const <String, double>{},
        client: MockClient(
          (_) async =>
              http.Response('{"result":"success","rates":{"GBP":0.75}}', 200),
        ),
      ).convertAmount(100, 'USD', 'EUR');

      expect(result.isFailure, isTrue);
      expect(result.errorMessage, 'Exchange rates unavailable for USD/EUR');
    },
  );

  test(
    'caches CurrencyConverter in memory across repeated conversions',
    () async {
      final FakeFxRateDao dao = FakeFxRateDao(const <String, double>{
        'EUR': 0.5,
        'GBP': 0.75,
      });
      final FxRepository repository = FxRepository(
        dao,
        FxApi(client: MockClient((_) async => throw StateError('No network'))),
      );

      expect((await repository.convertAmount(100, 'USD', 'EUR')).value, 50);
      expect((await repository.convertAmount(50, 'EUR', 'GBP')).value, 75);
      expect((await repository.convertAmount(75, 'GBP', 'USD')).value, 100);
      expect(dao.getAllCalls, 1);
    },
  );

  test(
    'deduplicates concurrent refreshRates and ensureFreshRates calls',
    () async {
      int requests = 0;
      final Completer<http.Response> gate = Completer<http.Response>();
      final FakeFxRateDao dao = FakeFxRateDao(const <String, double>{});
      final FxRepository repository = FxRepository(
        dao,
        FxApi(
          client: MockClient((_) {
            requests++;
            return gate.future;
          }),
        ),
      );

      final Future<Result<void>> first = repository.ensureFreshRates();
      final Future<Result<void>> second = repository.ensureFreshRates();
      final Future<Result<void>> third = repository.refreshRates();

      gate.complete(
        http.Response(
          '{"result":"success","rates":{"EUR":0.5,"GBP":0.75}}',
          200,
        ),
      );
      final List<Result<void>> results = await Future.wait(
        <Future<Result<void>>>[first, second, third],
      );

      expect(results.every((Result<void> r) => r.isSuccess), isTrue);
      expect(requests, 1);
      expect(dao.upsertCalls, 1);
    },
  );
}
