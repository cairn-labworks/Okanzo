import '../../domain/model/asset_type.dart';
import '../../util/result.dart';
import '../local/dao/asset_dao.dart';
import '../local/entity/asset_entity.dart';
import '../remote/stock/stock_price_service.dart';
import 'fx_repository.dart';

/// Outcome of refreshing every market-linked price in a portfolio.
class PriceRefreshResult {
  const PriceRefreshResult({
    required this.updated,
    required this.failed,
    required this.total,
  });

  final int updated;
  final int failed;
  final int total;
}

class AssetRepository {
  const AssetRepository(this._dao, this._stockPriceService, this._fxRepository);

  final AssetDao _dao;
  final StockPriceService _stockPriceService;
  final FxRepository _fxRepository;

  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) =>
      _dao.observeForPortfolio(portfolioId);

  Future<List<AssetEntity>> getForPortfolio(int portfolioId) =>
      _dao.getForPortfolio(portfolioId);

  Stream<AssetEntity?> observeById(int id) => _dao.observeById(id);

  Future<AssetEntity?> getById(int id) => _dao.getById(id);

  Future<int> save(AssetEntity asset) async {
    final AssetEntity stamped = asset.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (asset.id == 0) {
      final int position =
          await _dao.maxPosition(asset.portfolioId, asset.type) + 1;
      return _dao.insert(stamped.copyWith(position: position));
    }
    await _dao.update(stamped);
    return asset.id;
  }

  Future<void> delete(int id) => _dao.deleteById(id);

  /// Persists a new custom order for a set of assets (typically one type).
  Future<void> updateOrder(List<int> orderedIds) =>
      _dao.updatePositions(orderedIds);

  /// Looks up a live quote in the selected holding currency without persisting.
  Future<Result<StockQuote>> fetchQuote(
    String symbol, {
    required String currency,
    bool isCrypto = false,
  }) async {
    final Result<StockQuote> result = await _stockPriceService.fetchQuote(
      symbol,
      isCrypto: isCrypto,
    );
    if (result.isFailure) return result;
    final StockQuote quote = result.value;
    final String? source = quote.currency;
    if (source == null || source.trim().isEmpty) {
      return Result<StockQuote>.failure(
        'Quote currency unavailable for ${quote.symbol}',
      );
    }
    final Result<double> converted = await convertPrice(
      quote.price,
      source,
      currency,
    );
    if (converted.isFailure) {
      return Result<StockQuote>.failure(converted.errorMessage!);
    }
    return Result<StockQuote>.success(
      StockQuote(
        symbol: quote.symbol,
        price: converted.value,
        currency: currency,
      ),
    );
  }

  Future<Result<double>> convertPrice(double price, String from, String to) =>
      _fxRepository.convertAmount(
        price,
        from.trim().toUpperCase(),
        to.trim().toUpperCase(),
      );

  /// Refreshes the market price for a single asset (by symbol) and persists it.
  /// Returns the updated price on success.
  Future<Result<double>> refreshPrice(AssetEntity asset) async {
    final String symbol = asset.symbol?.trim() ?? '';
    if (!asset.type.isMarketLinked || symbol.isEmpty) {
      return Result<double>.failure('Asset has no market symbol');
    }
    final Result<StockQuote> quote = await fetchQuote(
      symbol,
      currency: asset.currency,
      isCrypto: asset.type == AssetType.crypto,
    );
    if (quote.isFailure) return Result<double>.failure(quote.errorMessage!);
    final int now = DateTime.now().millisecondsSinceEpoch;
    await _dao.updatePrice(
      asset.id,
      quote.value.price,
      now,
      currency: quote.value.currency,
    );
    return Result<double>.success(quote.value.price);
  }

  static const int _maxConcurrentQuoteRequests = 4;

  /// Refreshes prices for all market-linked assets in a portfolio.
  ///
  /// Deduplicates identical ticker lookups, fetches quotes with bounded
  /// concurrency, and persists all updated prices in a single database
  /// transaction so watchers only rebuild once.
  Future<PriceRefreshResult> refreshAllPrices(int portfolioId) async {
    final List<AssetEntity> assets = (await _dao.getForPortfolio(portfolioId))
        .where((AssetEntity asset) {
          final String? symbol = asset.symbol;
          return asset.type.isMarketLinked &&
              symbol != null &&
              symbol.trim().isNotEmpty;
        })
        .toList(growable: false);
    if (assets.isEmpty) {
      return const PriceRefreshResult(updated: 0, failed: 0, total: 0);
    }

    final List<(String, bool)> uniqueKeys = <(String, bool)>[];
    final Set<(String, bool)> seenKeys = <(String, bool)>{};
    for (final AssetEntity asset in assets) {
      final (String, bool) key = (
        asset.symbol!.trim().toUpperCase(),
        asset.type == AssetType.crypto,
      );
      if (seenKeys.add(key)) uniqueKeys.add(key);
    }

    final Map<(String, bool), Result<StockQuote>> rawQuotes =
        <(String, bool), Result<StockQuote>>{};
    int nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < uniqueKeys.length) {
        final (String symbol, bool isCrypto) key = uniqueKeys[nextIndex++];
        rawQuotes[key] = await _stockPriceService.fetchQuote(
          key.$1,
          isCrypto: key.$2,
        );
      }
    }

    final int workerCount = uniqueKeys.length < _maxConcurrentQuoteRequests
        ? uniqueKeys.length
        : _maxConcurrentQuoteRequests;
    await Future.wait(<Future<void>>[
      for (int i = 0; i < workerCount; i++) worker(),
    ]);

    int updated = 0;
    int failed = 0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<({int id, double price, int timestamp, String? currency})>
    updates = <({int id, double price, int timestamp, String? currency})>[];

    for (final AssetEntity asset in assets) {
      final (String, bool) key = (
        asset.symbol!.trim().toUpperCase(),
        asset.type == AssetType.crypto,
      );
      final Result<StockQuote>? raw = rawQuotes[key];
      if (raw == null || raw.isFailure) {
        failed++;
        continue;
      }
      final StockQuote quote = raw.value;
      final String? source = quote.currency;
      if (source == null || source.trim().isEmpty) {
        failed++;
        continue;
      }
      final Result<double> converted = await convertPrice(
        quote.price,
        source,
        asset.currency,
      );
      if (converted.isFailure) {
        failed++;
        continue;
      }
      updates.add((
        id: asset.id,
        price: converted.value,
        timestamp: now,
        currency: asset.currency,
      ));
      updated++;
    }

    await _dao.updatePrices(updates);
    return PriceRefreshResult(
      updated: updated,
      failed: failed,
      total: assets.length,
    );
  }
}
