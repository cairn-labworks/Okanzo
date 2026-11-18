import 'dart:convert';

import 'package:http/http.dart' as http;

/// Subset of the Yahoo Finance chart response used to read the latest price.
class ChartResponse {
  const ChartResponse(this.chart);

  factory ChartResponse.fromJson(Map<String, Object?> json) => ChartResponse(
    json['chart'] is Map<String, Object?>
        ? Chart.fromJson(json['chart']! as Map<String, Object?>)
        : null,
  );

  final Chart? chart;
}

class Chart {
  const Chart({this.result, this.error});

  factory Chart.fromJson(Map<String, Object?> json) => Chart(
    result: (json['result'] as List<Object?>?)
        ?.whereType<Map<String, Object?>>()
        .map(ChartResult.fromJson)
        .toList(growable: false),
    error: json['error'] is Map<String, Object?>
        ? ChartError.fromJson(json['error']! as Map<String, Object?>)
        : null,
  );

  final List<ChartResult>? result;
  final ChartError? error;
}

class ChartError {
  const ChartError({this.code, this.description});

  factory ChartError.fromJson(Map<String, Object?> json) => ChartError(
    code: json['code'] as String?,
    description: json['description'] as String?,
  );

  final String? code;
  final String? description;
}

class ChartResult {
  const ChartResult({this.meta});

  factory ChartResult.fromJson(Map<String, Object?> json) => ChartResult(
    meta: json['meta'] is Map<String, Object?>
        ? ChartMeta.fromJson(json['meta']! as Map<String, Object?>)
        : null,
  );

  final ChartMeta? meta;
}

class ChartMeta {
  const ChartMeta({
    this.currency,
    this.symbol,
    this.longName,
    this.shortName,
    this.regularMarketPrice,
    this.previousClose,
    this.chartPreviousClose,
  });

  factory ChartMeta.fromJson(Map<String, Object?> json) => ChartMeta(
    currency: json['currency'] as String?,
    symbol: json['symbol'] as String?,
    longName: _nonEmptyText(json['longName']),
    shortName: _nonEmptyText(json['shortName']),
    regularMarketPrice: (json['regularMarketPrice'] as num?)?.toDouble(),
    previousClose: (json['previousClose'] as num?)?.toDouble(),
    chartPreviousClose: (json['chartPreviousClose'] as num?)?.toDouble(),
  );

  final String? currency;
  final String? symbol;
  final String? longName;
  final String? shortName;
  final double? regularMarketPrice;
  final double? previousClose;
  final double? chartPreviousClose;

  String? get displayName => longName ?? shortName;

  static String? _nonEmptyText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

/// Public Yahoo Finance chart endpoint. Only the ticker symbol is ever sent;
/// no personal or portfolio data leaves the device.
class StockApi {
  StockApi({http.Client? client}) : _client = client ?? http.Client();

  static const String baseUrl = 'https://query1.finance.yahoo.com/';

  final http.Client _client;

  Future<ChartResponse> getChart(
    String symbol, {
    String range = '1d',
    String interval = '1d',
  }) async {
    final Uri uri = Uri.parse(
      '${baseUrl}v8/finance/chart/${Uri.encodeComponent(symbol)}'
      '?range=$range&interval=$interval',
    );
    final http.Response response = await _client.get(uri);
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    // Yahoo answers unknown symbols with a non-2xx status and an error body;
    // that body carries the friendlier message, so prefer it when present.
    if (decoded is Map<String, Object?>) return ChartResponse.fromJson(decoded);
    throw http.ClientException('HTTP ${response.statusCode}', uri);
  }
}
