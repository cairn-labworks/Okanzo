import '../../domain/model/asset_type.dart';
import '../../util/result.dart';
import '../local/dao/asset_dao.dart';
import '../local/entity/asset_entity.dart';
import '../remote/stock/stock_price_service.dart';

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
  const AssetRepository(this._dao, this._stockPriceService);

  final AssetDao _dao;
  final StockPriceService _stockPriceService;

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

  /// Looks up a live quote for a symbol without persisting anything.
  Future<Result<StockQuote>> fetchQuote(
    String symbol, {
    bool isCrypto = false,
  }) => _stockPriceService.fetchQuote(symbol, isCrypto: isCrypto);

  /// Refreshes the market price for a single asset (by symbol) and persists it.
  /// Returns the updated price on success.
  Future<Result<double>> refreshPrice(AssetEntity asset) async {
    final String symbol = asset.symbol?.trim() ?? '';
    if (!asset.type.isMarketLinked || symbol.isEmpty) {
      return Result<double>.failure('Asset has no market symbol');
    }
    final Result<StockQuote> quote = await _stockPriceService.fetchQuote(
      symbol,
      isCrypto: asset.type == AssetType.crypto,
    );
    if (quote.isFailure) return Result<double>.failure(quote.errorMessage!);
    final int now = DateTime.now().millisecondsSinceEpoch;
    await _dao.updatePrice(asset.id, quote.value.price, now);
    return Result<double>.success(quote.value.price);
  }

  /// Refreshes prices for all market-linked assets in a portfolio.
  Future<PriceRefreshResult> refreshAllPrices(int portfolioId) async {
    final List<AssetEntity> assets = (await _dao.getForPortfolio(portfolioId))
        .where((AssetEntity asset) {
          final String? symbol = asset.symbol;
          return asset.type.isMarketLinked &&
              symbol != null &&
              symbol.trim().isNotEmpty;
        })
        .toList(growable: false);
    int updated = 0;
    int failed = 0;
    for (final AssetEntity asset in assets) {
      if ((await refreshPrice(asset)).isSuccess) {
        updated++;
      } else {
        failed++;
      }
    }
    return PriceRefreshResult(
      updated: updated,
      failed: failed,
      total: assets.length,
    );
  }
}
