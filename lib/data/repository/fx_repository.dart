import '../../util/result.dart';
import '../local/dao/fx_rate_dao.dart';
import '../local/entity/fx_rate_entity.dart';
import '../remote/fx/fx_api.dart';
import 'currency_converter.dart';

class FxRepository {
  const FxRepository(this._dao, this._api);

  static const int _defaultMaxAgeMillis = 12 * 60 * 60 * 1000; // 12 hours

  final FxRateDao _dao;
  final FxApi _api;

  Stream<CurrencyConverter> get converter =>
      _dao.observeAll().map(_toConverter);

  Future<CurrencyConverter> currentConverter() async =>
      _toConverter(await _dao.getAll());

  Future<int?> latestTimestamp() => _dao.latestTimestamp();

  /// Converts using cached rates, fetching them if either currency is missing.
  /// Unlike approximate portfolio totals, a stored price must never use 1:1.
  Future<Result<double>> convertAmount(
    double amount,
    String from,
    String to,
  ) async {
    if (!amount.isFinite || from.isEmpty || to.isEmpty) {
      return Result<double>.failure('Invalid currency conversion');
    }
    if (from == to) return Result<double>.success(amount);
    CurrencyConverter rates = await currentConverter();
    if (!rates.canConvert(from) || !rates.canConvert(to)) {
      final Result<void> refreshed = await refreshRates();
      if (refreshed.isFailure) {
        return Result<double>.failure(refreshed.errorMessage!);
      }
      rates = await currentConverter();
    }
    if (!rates.canConvert(from) || !rates.canConvert(to)) {
      return Result<double>.failure('Exchange rates unavailable for $from/$to');
    }
    final double converted = rates.convert(amount, from, to);
    return converted.isFinite
        ? Result<double>.success(converted)
        : Result<double>.failure('Invalid currency conversion');
  }

  /// Fetches and caches the latest USD-based exchange rates.
  Future<Result<void>> refreshRates() async {
    try {
      final FxResponse response = await _api.getLatest('USD');
      final Map<String, double>? rates = response.rates;
      if (response.result != 'success' || rates == null || rates.isEmpty) {
        return Result<void>.failure('Exchange rates unavailable');
      }
      final int now = DateTime.now().millisecondsSinceEpoch;
      await _dao.upsertAll(<FxRateEntity>[
        for (final MapEntry<String, double> rate in rates.entries)
          FxRateEntity(
            currency: rate.key,
            unitsPerUsd: rate.value,
            timestamp: now,
          ),
      ]);
      return Result<void>.success(null);
    } on Object catch (error) {
      return Result<void>.failure(error.toString());
    }
  }

  /// Refreshes only if the cache is empty or older than [maxAgeMillis].
  Future<Result<void>> ensureFreshRates([
    int maxAgeMillis = _defaultMaxAgeMillis,
  ]) async {
    final int? latest = await _dao.latestTimestamp();
    final bool fresh =
        latest != null &&
        DateTime.now().millisecondsSinceEpoch - latest < maxAgeMillis;
    return fresh ? Result<void>.success(null) : refreshRates();
  }

  CurrencyConverter _toConverter(List<FxRateEntity> rates) =>
      CurrencyConverter(<String, double>{
        for (final FxRateEntity rate in rates) rate.currency: rate.unitsPerUsd,
      });
}
