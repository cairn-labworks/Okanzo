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
import '../../domain/model/asset_type.dart';
import '../../domain/model/liability_type.dart';
import '../../domain/model/net_worth_summary.dart';
import '../../util/category_order.dart';
import '../../util/collections.dart';
import 'category_groups.dart';

/// Everything the home screen renders.
class HomeState {
  const HomeState({
    this.loading = true,
    this.portfolios = const <PortfolioEntity>[],
    this.activePortfolio,
    this.baseCurrency = 'USD',
    NetWorthSummary? summary,
    this.assetGroups = const <AssetCategoryGroup>[],
    this.liabilityGroups = const <LiabilityCategoryGroup>[],
    this.isRefreshing = false,
    this.hideBalances = false,
    this.simpleNetWorth = false,
  }) : _summary = summary;

  final bool loading;
  final List<PortfolioEntity> portfolios;
  final PortfolioEntity? activePortfolio;
  final String baseCurrency;
  final NetWorthSummary? _summary;
  final List<AssetCategoryGroup> assetGroups;
  final List<LiabilityCategoryGroup> liabilityGroups;
  final bool isRefreshing;
  final bool hideBalances;
  final bool simpleNetWorth;

  NetWorthSummary get summary =>
      _summary ?? NetWorthSummary.empty(baseCurrency);

  bool get hasAnyAssets => assetGroups.isNotEmpty;

  bool get hasAnyLiabilities => liabilityGroups.isNotEmpty;
}

/// Drives the home screen: keeps the active portfolio, its holdings and the
/// converted net-worth summary in sync with the database and settings.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
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

  static const NetWorthCalculator _calculator = NetWorthCalculator();

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
  bool _refreshing = false;
  bool _loadedPortfolios = false;

  HomeState _state = const HomeState();
  String? _message;

  HomeState get state => _state;

  /// A one-shot user-facing message (snackbar), cleared by [consumeMessage].
  String? get message => _message;

  Future<void> _start() async {
    _settingsSub = _settingsRepository.settings.listen((AppSettings settings) {
      _settings = settings;
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
    unawaited(_portfolioRepository.ensureDefaultPortfolio());
    unawaited(_fxRepository.ensureFreshRates());
  }

  void selectPortfolio(int id) =>
      unawaited(_settingsRepository.setSelectedPortfolioId(id));

  void toggleHideBalances() =>
      unawaited(_settingsRepository.setHideBalances(!_state.hideBalances));

  Future<void> refresh() async {
    final PortfolioEntity? active = _state.activePortfolio;
    if (active == null || _refreshing) return;
    _refreshing = true;
    _rebuild();
    await _fxRepository.refreshRates();
    final PriceRefreshResult result = await _assetRepository.refreshAllPrices(
      active.id,
    );
    _refreshing = false;
    _message = result.total == 0
        ? 'Prices up to date'
        : result.failed == 0
        ? 'Updated ${result.updated} price(s)'
        : 'Updated ${result.updated}, ${result.failed} failed';
    _rebuild();
  }

  /// Persists a new order of asset category cards.
  void onAssetCategoriesReordered(List<AssetType> orderedTypes) {
    final PortfolioEntity? active = _state.activePortfolio;
    if (active == null) return;
    unawaited(
      _settingsRepository.setCategoryOrder(
        active.id,
        CategorySection.asset,
        <String>[for (final AssetType type in orderedTypes) type.storageName],
      ),
    );
  }

  void onLiabilityCategoriesReordered(List<LiabilityType> orderedTypes) {
    final PortfolioEntity? active = _state.activePortfolio;
    if (active == null) return;
    unawaited(
      _settingsRepository.setCategoryOrder(
        active.id,
        CategorySection.liability,
        <String>[
          for (final LiabilityType type in orderedTypes) type.storageName,
        ],
      ),
    );
  }

  /// Persists a new order of asset items within a single type.
  void onAssetItemsReordered(List<int> orderedIds) =>
      unawaited(_assetRepository.updateOrder(orderedIds));

  void onLiabilityItemsReordered(List<int> orderedIds) =>
      unawaited(_liabilityRepository.updateOrder(orderedIds));

  void consumeMessage() {
    _message = null;
  }

  void _rebuild() {
    final AppSettings? settings = _settings;
    if (settings == null || !_loadedPortfolios) return;

    final PortfolioEntity? active = resolveActivePortfolio(
      _portfolios,
      settings.selectedPortfolioId,
    );
    _watchPortfolio(active?.id);

    if (active == null) {
      _state = HomeState(
        loading: false,
        portfolios: _portfolios,
        baseCurrency: settings.baseCurrency,
        isRefreshing: _refreshing,
        hideBalances: settings.hideBalances,
        simpleNetWorth: settings.simpleNetWorth,
      );
      notifyListeners();
      return;
    }

    final NetWorthSummary summary = _calculator.calculate(
      assets: _assets,
      liabilities: _liabilities,
      baseCurrency: settings.baseCurrency,
      converter: _converter,
    );

    _state = HomeState(
      loading: false,
      portfolios: _portfolios,
      activePortfolio: active,
      baseCurrency: settings.baseCurrency,
      summary: summary,
      assetGroups: _buildAssetGroups(active.id, settings.baseCurrency),
      liabilityGroups: _buildLiabilityGroups(active.id, settings.baseCurrency),
      isRefreshing: _refreshing,
      hideBalances: settings.hideBalances,
      simpleNetWorth: settings.simpleNetWorth,
    );
    notifyListeners();
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

  List<AssetCategoryGroup> _buildAssetGroups(
    int portfolioId,
    String baseCurrency,
  ) {
    final Map<AssetType, List<AssetEntity>> byType =
        groupBy<AssetType, AssetEntity>(_assets, (AssetEntity a) => a.type);
    final List<AssetType> ordered = orderTypes<AssetType>(
      byType.keys,
      _settingsRepository.categoryOrder(portfolioId, CategorySection.asset),
      AssetType.fromName,
    );
    return <AssetCategoryGroup>[
      for (final AssetType type in ordered)
        () {
          final List<AssetLine> lines = buildAssetLines(
            byType[type]!,
            _converter,
            baseCurrency,
          );
          return AssetCategoryGroup(
            type: type,
            total: sumAssetLines(lines),
            baseCurrency: baseCurrency,
            items: lines,
          );
        }(),
    ];
  }

  List<LiabilityCategoryGroup> _buildLiabilityGroups(
    int portfolioId,
    String baseCurrency,
  ) {
    final Map<LiabilityType, List<LiabilityEntity>> byType =
        groupBy<LiabilityType, LiabilityEntity>(
          _liabilities,
          (LiabilityEntity l) => l.type,
        );
    final List<LiabilityType> ordered = orderTypes<LiabilityType>(
      byType.keys,
      _settingsRepository.categoryOrder(portfolioId, CategorySection.liability),
      LiabilityType.fromName,
    );
    return <LiabilityCategoryGroup>[
      for (final LiabilityType type in ordered)
        () {
          final List<LiabilityLine> lines = buildLiabilityLines(
            byType[type]!,
            _converter,
            baseCurrency,
          );
          return LiabilityCategoryGroup(
            type: type,
            total: sumLiabilityLines(lines),
            baseCurrency: baseCurrency,
            items: lines,
          );
        }(),
    ];
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
