import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/local/entity/portfolio_entity.dart';
import '../../data/repository/asset_repository.dart';
import '../../data/repository/currency_converter.dart';
import '../../data/repository/fx_repository.dart';
import '../../data/repository/liability_repository.dart';
import '../../data/repository/net_worth_calculator.dart';
import '../../data/repository/portfolio_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../domain/model/net_worth_summary.dart';

/// One portfolio as shown in the portfolio manager.
class PortfolioRow {
  const PortfolioRow({
    required this.portfolio,
    required this.netWorth,
    required this.baseCurrency,
    required this.assetCount,
    required this.liabilityCount,
  });

  final PortfolioEntity portfolio;
  final double netWorth;
  final String baseCurrency;
  final int assetCount;
  final int liabilityCount;
}

class PortfolioListViewModel extends ChangeNotifier {
  PortfolioListViewModel({
    required PortfolioRepository portfolioRepository,
    required AssetRepository assetRepository,
    required LiabilityRepository liabilityRepository,
    required FxRepository fxRepository,
    required SettingsRepository settingsRepository,
  }) : _portfolioRepository = portfolioRepository,
       _assetRepository = assetRepository,
       _liabilityRepository = liabilityRepository,
       _fxRepository = fxRepository,
       _settingsRepository = settingsRepository {
    _start();
  }

  final PortfolioRepository _portfolioRepository;
  final AssetRepository _assetRepository;
  final LiabilityRepository _liabilityRepository;
  final FxRepository _fxRepository;
  final SettingsRepository _settingsRepository;

  static const NetWorthCalculator _calculator = NetWorthCalculator();

  StreamSubscription<List<PortfolioEntity>>? _portfolioSub;
  StreamSubscription<AppSettings>? _settingsSub;
  StreamSubscription<CurrencyConverter>? _converterSub;

  List<PortfolioEntity> _portfolios = const <PortfolioEntity>[];
  final Map<int, List<AssetEntity>> _assetsByPortfolio =
      <int, List<AssetEntity>>{};
  final Map<int, List<LiabilityEntity>> _liabilitiesByPortfolio =
      <int, List<LiabilityEntity>>{};
  String? _baseCurrency;
  CurrencyConverter _converter = const CurrencyConverter.empty();
  List<PortfolioRow> _rows = const <PortfolioRow>[];
  String? _message;
  bool _disposed = false;

  List<PortfolioRow> get rows => _rows;

  String? get message => _message;

  void _start() {
    _baseCurrency = _settingsRepository.current.baseCurrency;
    _portfolioSub = _portfolioRepository.observeAll().listen((
      List<PortfolioEntity> portfolios,
    ) {
      _portfolios = portfolios;
      unawaited(_reloadHoldingsAndRecompute());
    });
    _settingsSub = _settingsRepository.settings.listen((AppSettings settings) {
      if (settings.baseCurrency == _baseCurrency) return;
      _baseCurrency = settings.baseCurrency;
      _recomputeFromCache();
    });
    _converterSub = _fxRepository.converter.listen((CurrencyConverter value) {
      _converter = value;
      _recomputeFromCache();
    });
  }

  Future<void> _reloadHoldingsAndRecompute() async {
    final List<PortfolioEntity> snapshot = _portfolios;
    final Map<int, List<AssetEntity>> assetsMap = <int, List<AssetEntity>>{};
    final Map<int, List<LiabilityEntity>> liabilitiesMap =
        <int, List<LiabilityEntity>>{};
    for (final PortfolioEntity portfolio in snapshot) {
      assetsMap[portfolio.id] = await _assetRepository.getForPortfolio(
        portfolio.id,
      );
      liabilitiesMap[portfolio.id] = await _liabilityRepository.getForPortfolio(
        portfolio.id,
      );
      if (_disposed) return;
    }
    _assetsByPortfolio
      ..clear()
      ..addAll(assetsMap);
    _liabilitiesByPortfolio
      ..clear()
      ..addAll(liabilitiesMap);
    _recomputeFromCache();
  }

  void _recomputeFromCache() {
    if (_disposed) return;
    final String baseCurrency =
        _baseCurrency ?? _settingsRepository.current.baseCurrency;
    final List<PortfolioRow> rows = <PortfolioRow>[];
    for (final PortfolioEntity portfolio in _portfolios) {
      final List<AssetEntity> assets =
          _assetsByPortfolio[portfolio.id] ?? const <AssetEntity>[];
      final List<LiabilityEntity> liabilities =
          _liabilitiesByPortfolio[portfolio.id] ?? const <LiabilityEntity>[];
      final NetWorthSummary summary = _calculator.calculate(
        assets: assets,
        liabilities: liabilities,
        baseCurrency: baseCurrency,
        converter: _converter,
      );
      rows.add(
        PortfolioRow(
          portfolio: portfolio,
          netWorth: summary.netWorth,
          baseCurrency: baseCurrency,
          assetCount: assets.length,
          liabilityCount: liabilities.length,
        ),
      );
    }
    _rows = rows;
    notifyListeners();
  }

  void create(String name) {
    if (name.trim().isEmpty) return;
    unawaited(_portfolioRepository.create(name));
  }

  void rename(int id, String name) {
    if (name.trim().isEmpty) return;
    unawaited(_portfolioRepository.rename(id, name));
  }

  void setDefault(int id) => unawaited(_portfolioRepository.setDefault(id));

  Future<void> delete(int id) async {
    final bool removed = await _portfolioRepository.delete(id);
    if (!removed) {
      _message = 'You must keep at least one portfolio';
      notifyListeners();
    }
  }

  void consumeMessage() {
    _message = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _portfolioSub?.cancel();
    _settingsSub?.cancel();
    _converterSub?.cancel();
    super.dispose();
  }
}
