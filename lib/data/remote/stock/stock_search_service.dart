import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../util/result.dart';
import 'chart_response.dart';

enum StockSearchType { stock, fund, crypto }

class StockSearchResult {
  const StockSearchResult({
    required this.symbol,
    required this.name,
    required this.exchange,
  });

  final String symbol;
  final String name;
  final String exchange;
}

/// Keyless Yahoo Finance search, using the same provider as market prices.
/// Only the user's search query is sent, never their asset name or holdings.
class StockSearchService {
  StockSearchService({required http.Client client}) : _client = client;

  final http.Client _client;

  Future<Result<List<StockSearchResult>>> search(
    String query, {
    required StockSearchType type,
  }) async {
    final String cleaned = query.trim();
    if (cleaned.length < 2) {
      return Result<List<StockSearchResult>>.failure(
        'Enter at least two characters',
      );
    }
    final Uri uri = Uri.parse('${StockApi.baseUrl}v1/finance/search').replace(
      queryParameters: <String, String>{
        'q': cleaned,
        'quotesCount': '20',
        'newsCount': '0',
        'enableFuzzyQuery': 'false',
      },
    );
    try {
      final http.Response response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return Result<List<StockSearchResult>>.failure(
          'HTTP ${response.statusCode}',
        );
      }
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?> || decoded['quotes'] is! List) {
        return Result<List<StockSearchResult>>.failure(
          'Invalid search response',
        );
      }
      final List<StockSearchResult> matches = <StockSearchResult>[];
      final Set<String> seen = <String>{};
      for (final Object? item in decoded['quotes']! as List<Object?>) {
        if (item is! Map<String, Object?> || item['isYahooFinance'] != true) {
          continue;
        }
        final bool matchesType = switch (type) {
          StockSearchType.stock => item['quoteType'] == 'EQUITY',
          StockSearchType.fund =>
            item['quoteType'] == 'ETF' || item['quoteType'] == 'MUTUALFUND',
          StockSearchType.crypto => item['quoteType'] == 'CRYPTOCURRENCY',
        };
        if (!matchesType) continue;
        final Object? symbol = item['symbol'];
        if (symbol is! String || symbol.trim().isEmpty) continue;
        final String ticker = symbol.trim().toUpperCase();
        if (!seen.add(ticker)) continue;
        final String name =
            _text(item['longname']) ?? _text(item['shortname']) ?? ticker;
        matches.add(
          StockSearchResult(
            symbol: ticker,
            name: name,
            exchange: _text(item['exchDisp']) ?? _text(item['exchange']) ?? '',
          ),
        );
        if (matches.length == 8) break;
      }
      return Result<List<StockSearchResult>>.success(matches);
    } on TimeoutException {
      return Result<List<StockSearchResult>>.failure('Search timed out');
    } on http.ClientException catch (error) {
      return Result<List<StockSearchResult>>.failure(error.toString());
    } on FormatException {
      return Result<List<StockSearchResult>>.failure('Invalid search response');
    }
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
