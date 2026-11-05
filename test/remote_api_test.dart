import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:okanzo/data/remote/fx/fx_api.dart';
import 'package:okanzo/data/remote/stock/chart_response.dart';
import 'package:okanzo/data/remote/stock/stock_price_service.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/util/result.dart';
import 'package:test/test.dart';

StockPriceService serviceReturning(
  String body, {
  int status = 200,
  void Function(Uri uri)? onRequest,
}) => StockPriceService(
  StockApi(
    client: MockClient((http.Request request) async {
      onRequest?.call(request.url);
      return http.Response(body, status);
    }),
  ),
);

String metaBody(Map<String, Object?> meta) => jsonEncode(<String, Object?>{
  'chart': <String, Object?>{
    'result': <Object?>[
      <String, Object?>{'meta': meta},
    ],
    'error': null,
  },
});

void main() {
  group('StockPriceService', () {
    test('rejects an empty symbol without calling the network', () async {
      bool called = false;
      final StockPriceService service = serviceReturning(
        '{}',
        onRequest: (Uri _) => called = true,
      );
      final Result<StockQuote> result = await service.fetchQuote('   ');
      expect(result.isFailure, isTrue);
      expect(result.errorMessage, 'Symbol is empty');
      expect(called, isFalse);
    });

    test(
      'uppercases and trims the symbol in the request and the quote',
      () async {
        Uri? seen;
        final StockPriceService service = serviceReturning(
          metaBody(<String, Object?>{
            'regularMarketPrice': 190.25,
            'currency': 'USD',
          }),
          onRequest: (Uri uri) => seen = uri,
        );
        final Result<StockQuote> result = await service.fetchQuote(' aapl ');
        expect(seen.toString(), contains('/v8/finance/chart/AAPL'));
        expect(seen.toString(), contains('range=1d'));
        expect(result.value.symbol, 'AAPL');
        expect(result.value.price, 190.25);
        expect(result.value.currency, 'USD');
      },
    );

    test('uses the USD pair for bare crypto symbols', () async {
      Uri? seen;
      final StockPriceService service = serviceReturning(
        metaBody(<String, Object?>{
          'regularMarketPrice': 90000.0,
          'currency': 'USD',
        }),
        onRequest: (Uri uri) => seen = uri,
      );

      final Result<StockQuote> result = await service.fetchQuote(
        ' btc ',
        isCrypto: true,
      );

      expect(seen.toString(), contains('/v8/finance/chart/BTC-USD'));
      expect(result.value.symbol, 'BTC-USD');
      expect(result.value.price, 90000.0);
      expect(result.value.currency, 'USD');
    });

    test('does not append a second quote currency to crypto pairs', () async {
      Uri? seen;
      final StockPriceService service = serviceReturning(
        metaBody(<String, Object?>{'regularMarketPrice': 90000.0}),
        onRequest: (Uri uri) => seen = uri,
      );

      await service.fetchQuote('BTC-USD', isCrypto: true);

      expect(seen.toString(), contains('/v8/finance/chart/BTC-USD'));
    });

    test('preserves non-USD crypto pairs', () async {
      Uri? seen;
      final StockPriceService service = serviceReturning(
        metaBody(<String, Object?>{
          'regularMarketPrice': 80000.0,
          'currency': 'EUR',
        }),
        onRequest: (Uri uri) => seen = uri,
      );

      final Result<StockQuote> result = await service.fetchQuote(
        ' btc-eur ',
        isCrypto: true,
      );

      expect(seen!.path, '/v8/finance/chart/BTC-EUR');
      expect(result.value.symbol, 'BTC-EUR');
      expect(result.value.currency, 'EUR');
    });

    test('leaves a stock ticker named BTC unchanged', () async {
      Uri? seen;
      final StockPriceService service = serviceReturning(
        metaBody(<String, Object?>{'regularMarketPrice': 36.0}),
        onRequest: (Uri uri) => seen = uri,
      );

      final Result<StockQuote> result = await service.fetchQuote('BTC');

      expect(seen!.path, '/v8/finance/chart/BTC');
      expect(result.value.symbol, 'BTC');
    });

    test(
      'does not fall back to a bare ticker when a crypto pair fails',
      () async {
        final List<String> paths = <String>[];
        final StockPriceService service = serviceReturning(
          '{"chart":{"result":[]}}',
          onRequest: (Uri uri) => paths.add(uri.path),
        );

        final Result<StockQuote> result = await service.fetchQuote(
          'ETH',
          isCrypto: true,
        );

        expect(result.errorMessage, 'No data returned for ETH-USD');
        expect(paths, <String>['/v8/finance/chart/ETH-USD']);
      },
    );

    test(
      'fetches each selectable exchange ticker and retains its currency',
      () async {
        for (final StockExchange exchange in StockExchange.values) {
          if (exchange == StockExchange.other) continue;
          final String symbol = exchange.qualify(exchange.example);
          Uri? seen;
          final StockPriceService service = serviceReturning(
            metaBody(<String, Object?>{
              'regularMarketPrice': 123.45,
              'currency': exchange.currency,
            }),
            onRequest: (Uri uri) => seen = uri,
          );
          final Result<StockQuote> result = await service.fetchQuote(symbol);

          expect(seen!.pathSegments.last, symbol);
          expect(result.value.symbol, symbol);
          expect(result.value.price, 123.45);
          expect(result.value.currency, exchange.currency);
        }
      },
    );

    test(
      'supports Yahoo Finance symbols for major international exchanges',
      () async {
        const List<String> symbols = <String>[
          '7203.T',
          '600519.SS',
          '000001.SZ',
          '0700.HK',
          'AIR.PA',
          'VOD.L',
          'RELIANCE.NS',
          'SHOP.TO',
        ];

        for (final String symbol in symbols) {
          Uri? seen;
          final StockPriceService service = serviceReturning(
            metaBody(<String, Object?>{'regularMarketPrice': 1.0}),
            onRequest: (Uri uri) => seen = uri,
          );
          final Result<StockQuote> result = await service.fetchQuote(symbol);

          expect(seen!.pathSegments.last, symbol);
          expect(result.value.symbol, symbol);
        }
      },
    );

    test('falls back to previousClose then chartPreviousClose', () async {
      final Result<StockQuote> previous = await serviceReturning(
        metaBody(<String, Object?>{'previousClose': 10.0}),
      ).fetchQuote('X');
      expect(previous.value.price, 10.0);

      final Result<StockQuote> chart = await serviceReturning(
        metaBody(<String, Object?>{'chartPreviousClose': 7.5}),
      ).fetchQuote('X');
      expect(chart.value.price, 7.5);
    });

    test(
      'normalizes minor-unit prices without rescaling ISO currencies',
      () async {
        const Map<String, (String, double)> expected =
            <String, (String, double)>{
              'GBp': ('GBP', 1.25),
              'GBX': ('GBP', 1.25),
              'ZAc': ('ZAR', 1.25),
              'ILA': ('ILS', 1.25),
              'GBP': ('GBP', 125),
              'ZAR': ('ZAR', 125),
              'ILS': ('ILS', 125),
            };

        for (final MapEntry<String, (String, double)> entry
            in expected.entries) {
          final Result<StockQuote> result = await serviceReturning(
            metaBody(<String, Object?>{
              'regularMarketPrice': 125,
              'currency': entry.key,
            }),
          ).fetchQuote('VOD.L');

          expect(result.value.currency, entry.value.$1);
          expect(result.value.price, entry.value.$2);
        }
      },
    );

    test('surfaces the Yahoo error description from an error body', () async {
      final Result<StockQuote> result = await serviceReturning(
        jsonEncode(<String, Object?>{
          'chart': <String, Object?>{
            'result': null,
            'error': <String, Object?>{
              'code': 'Not Found',
              'description': 'No data found, symbol may be delisted',
            },
          },
        }),
        status: 404,
      ).fetchQuote('NOPE');
      expect(result.errorMessage, 'No data found, symbol may be delisted');
    });

    test('reports missing data and missing prices separately', () async {
      final Result<StockQuote> noResult = await serviceReturning(
        jsonEncode(<String, Object?>{
          'chart': <String, Object?>{'result': <Object?>[]},
        }),
      ).fetchQuote('abc');
      expect(noResult.errorMessage, 'No data returned for ABC');

      final Result<StockQuote> noPrice = await serviceReturning(
        metaBody(<String, Object?>{'currency': 'USD'}),
      ).fetchQuote('abc');
      expect(noPrice.errorMessage, 'No price available for ABC');
    });

    test(
      'a non-JSON body becomes a failure rather than an exception',
      () async {
        final Result<StockQuote> result = await serviceReturning(
          '<html>rate limited</html>',
          status: 429,
        ).fetchQuote('AAPL');
        expect(result.isFailure, isTrue);
        expect(result.errorMessage, contains('429'));
      },
    );
  });

  group('FxApi', () {
    test('parses rates and the update timestamp', () async {
      Uri? seen;
      final FxApi api = FxApi(
        client: MockClient((http.Request request) async {
          seen = request.url;
          return http.Response(
            jsonEncode(<String, Object?>{
              'result': 'success',
              'base_code': 'EUR',
              'time_last_update_unix': 1700000000,
              'rates': <String, Object?>{'EUR': 1, 'USD': 1.09},
            }),
            200,
          );
        }),
      );

      final FxResponse response = await api.getLatest('EUR');
      expect(seen.toString(), 'https://open.er-api.com/v6/latest/EUR');
      expect(response.result, 'success');
      expect(response.baseCode, 'EUR');
      expect(response.rates!['USD'], 1.09);
      expect(response.rates!['EUR'], 1.0);
      expect(response.timeLastUpdateUnix, 1700000000);
    });

    test('defaults to USD and throws on a failed status', () async {
      Uri? seen;
      final FxApi api = FxApi(
        client: MockClient((http.Request request) async {
          seen = request.url;
          return http.Response('nope', 503);
        }),
      );
      await expectLater(api.getLatest(), throwsA(isA<http.ClientException>()));
      expect(seen.toString(), endsWith('/v6/latest/USD'));
    });
  });
}
