import '../../../util/result.dart';
import 'chart_response.dart';

/// A resolved quote for a market-linked symbol.
class StockQuote {
  const StockQuote({required this.symbol, required this.price, this.currency});

  final String symbol;
  final double price;
  final String? currency;
}

/// Fetches the latest/last-closing price for a ticker symbol and returns a
/// [Result] so callers can surface friendly errors.
class StockPriceService {
  StockPriceService(this._api);

  final StockApi _api;

  Future<Result<StockQuote>> fetchQuote(
    String symbol, {
    bool isCrypto = false,
  }) async {
    final String cleaned = symbol.trim().toUpperCase();
    if (cleaned.isEmpty) return Result<StockQuote>.failure('Symbol is empty');
    final String ticker = isCrypto && !cleaned.contains('-')
        ? '$cleaned-USD'
        : cleaned;
    try {
      final ChartResponse response = await _api.getChart(ticker);
      final ChartError? error = response.chart?.error;
      if (error != null) {
        return Result<StockQuote>.failure(
          error.description ?? 'Symbol not found',
        );
      }
      final List<ChartResult>? results = response.chart?.result;
      final ChartMeta? meta = (results == null || results.isEmpty)
          ? null
          : results.first.meta;
      if (meta == null) {
        return Result<StockQuote>.failure('No data returned for $ticker');
      }
      final double? price =
          meta.regularMarketPrice ??
          meta.previousClose ??
          meta.chartPreviousClose;
      if (price == null) {
        return Result<StockQuote>.failure('No price available for $ticker');
      }
      return Result<StockQuote>.success(
        StockQuote(symbol: ticker, price: price, currency: meta.currency),
      );
    } on Object catch (error) {
      return Result<StockQuote>.failure(_describe(error));
    }
  }

  static String _describe(Object error) {
    final String message = error.toString();
    return message.isEmpty ? 'Price lookup failed' : message;
  }
}
