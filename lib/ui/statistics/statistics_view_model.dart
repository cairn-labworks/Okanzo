import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/local/entity/portfolio_entity.dart';
import '../../data/repository/asset_repository.dart';
import '../../data/repository/currency_converter.dart';
import '../../data/repository/fx_repository.dart';
import '../../data/repository/liability_repository.dart';
import '../../data/repository/portfolio_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/liability_type.dart';
import '../../util/category_order.dart';
import '../../util/collections.dart';

/// A single named amount used to build a chart wedge.
class TypeAmount {
  const TypeAmount({
    required this.typeName,
    required this.label,
    required this.amount,
  });

  final String typeName;
  final String label;
  final double amount;
}

class StatisticsState {
  const StatisticsState({
    this.loading = true,
    this.portfolios = const <PortfolioEntity>[],
    this.activePortfolio,
    this.baseCurrency = 'USD',
    this.hideBalances = false,
    this.totalAssets = 0.0,
    this.totalLiabilities = 0.0,
    this.assetsByType = const <TypeAmount>[],
    this.liabilitiesByType = const <TypeAmount>[],
  });

  final bool loading;
  final List<PortfolioEntity> portfolios;
  final PortfolioEntity? activePortfolio;
  final String baseCurrency;
  final bool hideBalances;
  final double totalAssets;
  final double totalLiabilities;
  final List<TypeAmount> assetsByType;
  final List<TypeAmount> liabilitiesByType;

  double get netWorth => totalAssets - totalLiabilities;

  bool get hasAssets => assetsByType.isNotEmpty;

  bool get hasLiabilities => liabilitiesByType.isNotEmpty;

  bool get hasAnything => hasAssets || hasLiabilities;
}

class StatisticsViewModel extends ChangeNotifier {
  StatisticsViewModel({
    required SettingsRepository settingsRepository,
    required PortfolioRepository portfolioRepository,
    required AssetRepository assetRepository,
    required LiabilityRepository liabilityRepository,
    required FxRepository fxRepository,
  }) : _settingsRepository = settingsRepository,
       _portfolioRepository = portfolioRepository,
       _assetRepository = assetRepository,
       _liabilityRepository = liabilityRepository,
       _fxRepository = fxRepository {
    _start();
  }

  final SettingsRepository _settingsRepository;
  final PortfolioRepository _portfolioRepository;
  final AssetRepository _assetRepository;
  final LiabilityRepository _liabilityRepository;
  final FxRepository _fxRepository;

  StreamSubscription<AppSettings>? _settingsSub;
  StreamSubscription<List<PortfolioEntity>>? _portfolioSub;
  StreamSubscription<CurrencyConverter>? _converterSub;
  StreamSubscription<List<AssetEntity>>? _assetSub;
  StreamSubscription<List<LiabilityEntity>>? _liabilitySub;

  AppSettings? _settings;
  List<PortfolioEntity> _portfolios = const <PortfolioEntity>[];
  CurrencyConverter _converter = const CurrencyConverter.empty();
  List<AssetEntity> _assets = const <AssetEntity>[];
  List<LiabilityEntity> _liabilities = const <LiabilityEntity>[];
  int? _watchedPortfolioId;
  bool _loadedPortfolios = false;

  StatisticsState _state = const StatisticsState();

  StatisticsState get state => _state;

  void _start() {
    _settingsSub = _settingsRepository.settings.listen((AppSettings settings) {
      final AppSettings? previous = _settings;
      _settings = settings;
      if (previous != null &&
          previous.selectedPortfolioId == settings.selectedPortfolioId &&
          previous.baseCurrency == settings.baseCurrency &&
          previous.hideBalances == settings.hideBalances) {
        return;
      }
      _rebuild();
    });
    _portfolioSub = _portfolioRepository.observeAll().listen((
      List<PortfolioEntity> portfolios,
    ) {
      _portfolios = portfolios;
      _loadedPortfolios = true;
      _rebuild();
    });
    _converterSub = _fxRepository.converter.listen((CurrencyConverter value) {
      _converter = value;
      _rebuild();
    });
    unawaited(_fxRepository.ensureFreshRates());
  }

  void selectPortfolio(int id) =>
      unawaited(_settingsRepository.setSelectedPortfolioId(id));

  void _rebuild() {
    final AppSettings? settings = _settings;
    if (settings == null || !_loadedPortfolios) return;

    final PortfolioEntity? active = resolveActivePortfolio(
      _portfolios,
      settings.selectedPortfolioId,
    );
    _watchPortfolio(active?.id);

    if (active == null) {
      _state = StatisticsState(
        loading: false,
        portfolios: _portfolios,
        baseCurrency: settings.baseCurrency,
        hideBalances: settings.hideBalances,
      );
      notifyListeners();
      return;
    }

    final String base = settings.baseCurrency;
    final List<TypeAmount> assetsByType = _amounts<AssetType, AssetEntity>(
      _assets,
      (AssetEntity a) => a.type,
      (AssetType t) => t.displayName,
      (AssetType t) => t.storageName,
      (AssetEntity a) => _converter.convert(a.value, a.currency, base),
    );
    final List<TypeAmount> liabilitiesByType =
        _amounts<LiabilityType, LiabilityEntity>(
          _liabilities,
          (LiabilityEntity l) => l.type,
          (LiabilityType t) => t.displayName,
          (LiabilityType t) => t.storageName,
          (LiabilityEntity l) => _converter.convert(l.value, l.currency, base),
        );

    _state = StatisticsState(
      loading: false,
      portfolios: _portfolios,
      activePortfolio: active,
      baseCurrency: base,
      hideBalances: settings.hideBalances,
      totalAssets: _sum(assetsByType),
      totalLiabilities: _sum(liabilitiesByType),
      assetsByType: assetsByType,
      liabilitiesByType: liabilitiesByType,
    );
    notifyListeners();
  }

  List<TypeAmount> _amounts<T, E>(
    List<E> items,
    T Function(E) typeOf,
    String Function(T) labelOf,
    String Function(T) nameOf,
    double Function(E) valueOf,
  ) {
    final Map<T, List<E>> grouped = groupBy<T, E>(items, typeOf);
    final List<TypeAmount> amounts = <TypeAmount>[];
    grouped.forEach((T type, List<E> entries) {
      double total = 0;
      for (final E entry in entries) {
        total += valueOf(entry);
      }
      if (total > 0.0) {
        amounts.add(
          TypeAmount(
            typeName: nameOf(type),
            label: labelOf(type),
            amount: total,
          ),
        );
      }
    });
    return sortedByDescending<TypeAmount>(
      amounts,
      (TypeAmount amount) => amount.amount,
    );
  }

  static double _sum(List<TypeAmount> amounts) {
    double total = 0;
    for (final TypeAmount amount in amounts) {
      total += amount.amount;
    }
    return total;
  }

  void _watchPortfolio(int? portfolioId) {
    if (portfolioId == _watchedPortfolioId) return;
    _watchedPortfolioId = portfolioId;
    _assetSub?.cancel();
    _liabilitySub?.cancel();
    _assets = const <AssetEntity>[];
    _liabilities = const <LiabilityEntity>[];
    if (portfolioId == null) return;
    _assetSub = _assetRepository.observeForPortfolio(portfolioId).listen((
      List<AssetEntity> assets,
    ) {
      _assets = assets;
      _rebuild();
    });
    _liabilitySub = _liabilityRepository
        .observeForPortfolio(portfolioId)
        .listen((List<LiabilityEntity> liabilities) {
          _liabilities = liabilities;
          _rebuild();
        });
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _portfolioSub?.cancel();
    _converterSub?.cancel();
    _assetSub?.cancel();
    _liabilitySub?.cancel();
    super.dispose();
  }
}
