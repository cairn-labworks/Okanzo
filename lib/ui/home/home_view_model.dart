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
import '../../util/result.dart';
import 'category_groups.dart';

/// Everything the home screen renders.
class HomeState {
  const HomeState({
    this.loading = true,
    this.portfolios = const <PortfolioEntity>[],
    this.activePortfolio,
    this.baseCurrency = 'USD',
    this.displayInUsd = false,
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
  final bool displayInUsd;
  final NetWorthSummary? _summary;
  final List<AssetCategoryGroup> assetGroups;
  final List<LiabilityCategoryGroup> liabilityGroups;
  final bool isRefreshing;
  final bool hideBalances;
  final bool simpleNetWorth;

  String get displayCurrency =>
      displayInUsd && baseCurrency != 'USD' ? 'USD' : baseCurrency;

  NetWorthSummary get summary =>
      _summary ?? NetWorthSummary.empty(displayCurrency);

  bool get hasAnyAssets => assetGroups.isNotEmpty;

  bool get hasAnyLiabilities => liabilityGroups.isNotEmpty;

  bool get hasApproximateAssetConversions => assetGroups.any(
    (AssetCategoryGroup group) =>
        group.items.any((AssetLine line) => line.isConversionApproximate),
  );

  bool get hasApproximateLiabilityConversions => liabilityGroups.any(
    (LiabilityCategoryGroup group) =>
        group.items.any((LiabilityLine line) => line.isConversionApproximate),
  );
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
  int? _defaultPortfolioId;
  int? _watchedPortfolioId;
  bool _refreshing = false;
  bool _displayInUsd = false;
  bool _loadedPortfolios = false;
  bool _loadedAssets = false;
  bool _loadedLiabilities = false;
  bool _ensuringDefaultPortfolio = false;
  bool _startedBackgroundFxCheck = false;
  bool _disposed = false;

  HomeState _state = const HomeState();
  String? _message;

  HomeState get state => _state;

  /// A one-shot user-facing message (snackbar), cleared by [consumeMessage].
  String? get message => _message;

  Future<void> _start() async {
    _settingsSub = _settingsRepository.settings.listen((AppSettings settings) {
      final AppSettings? previous = _settings;
      _settings = settings;
      if (previous != null && previous.baseCurrency != settings.baseCurrency) {
        _displayInUsd = false;
      }
      if (previous != null &&
          previous.selectedPortfolioId == settings.selectedPortfolioId &&
          previous.baseCurrency == settings.baseCurrency &&
          previous.hideBalances == settings.hideBalances &&
          previous.simpleNetWorth == settings.simpleNetWorth &&
          !_categoryOrderChanged(settings.selectedPortfolioId)) {
        return;
      }
      _rebuild();
    });
    _portfolioSub = _portfolioRepository.observeAll().listen((
      List<PortfolioEntity> portfolios,
    ) {
      final int? nextDefaultId = defaultPortfolioId(portfolios);
      if (nextDefaultId != null) {
        final int? previousDefaultId = _defaultPortfolioId;
        _defaultPortfolioId = nextDefaultId;
        if (previousDefaultId != null &&
            previousDefaultId != nextDefaultId &&
            _settingsRepository.current.selectedPortfolioId != null) {
          unawaited(_settingsRepository.setSelectedPortfolioId(null));
          _settings = _settingsRepository.current;
        }
      } else {
        if (!_ensuringDefaultPortfolio) {
          _ensuringDefaultPortfolio = true;
          unawaited(
            _portfolioRepository.ensureDefaultPortfolio().whenComplete(() {
              _ensuringDefaultPortfolio = false;
            }),
          );
        }
        if (portfolios.isEmpty) return;
      }
      _portfolios = portfolios;
      _loadedPortfolios = true;
      _rebuild();
    });
    _converterSub = _fxRepository.converter.listen((CurrencyConverter value) {
      _converter = value;
      _rebuild();
    });
  }

  List<String> _lastAssetCategoryOrder = const <String>[];
  List<String> _lastLiabilityCategoryOrder = const <String>[];

  bool _categoryOrderChanged(int? selectedPortfolioId) {
    final int? portfolioId = selectedPortfolioId ?? _state.activePortfolio?.id;
    if (portfolioId == null) return false;
    return !listEquals(
          _lastAssetCategoryOrder,
          _settingsRepository.categoryOrder(portfolioId, CategorySection.asset),
        ) ||
        !listEquals(
          _lastLiabilityCategoryOrder,
          _settingsRepository.categoryOrder(
            portfolioId,
            CategorySection.liability,
          ),
        );
  }

  void selectPortfolio(int id) =>
      unawaited(_settingsRepository.setSelectedPortfolioId(id));

  void toggleHideBalances() =>
      unawaited(_settingsRepository.setHideBalances(!_state.hideBalances));

  void toggleDisplayCurrency() {
    if (_state.baseCurrency == 'USD') return;
    _displayInUsd = !_displayInUsd;
    _rebuild();
  }

  Future<void> refresh() async {
    final PortfolioEntity? active = _state.activePortfolio;
    if (active == null || _refreshing) return;
    _refreshing = true;
    _rebuild();
    final Result<void> fxResult = await _fxRepository.refreshRates();
    final PriceRefreshResult result = await _assetRepository.refreshAllPrices(
      active.id,
    );
    _refreshing = false;
    _message = result.total == 0
        ? (fxResult.isOffline ? Result.offlineMessage : 'Prices up to date')
        : result.failed == 0
        ? 'Updated ${result.updated} price(s)'
        : result.offline
        ? Result.offlineMessage
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
  Future<void> onAssetItemsReordered(List<int> orderedIds) =>
      _assetRepository.updateOrder(orderedIds);

  Future<void> onLiabilityItemsReordered(List<int> orderedIds) =>
      _liabilityRepository.updateOrder(orderedIds);

  void consumeMessage() {
    _message = null;
  }

  void _rebuild() {
    if (_disposed) return;
    final AppSettings? settings = _settings;
    if (settings == null) return;

    final bool effectiveDisplayUsd =
        _displayInUsd && settings.baseCurrency != 'USD';
    final String effectiveCurrency = effectiveDisplayUsd
        ? 'USD'
        : settings.baseCurrency;

    if (!_loadedPortfolios) {
      _state = HomeState(
        loading: true,
        baseCurrency: settings.baseCurrency,
        displayInUsd: effectiveDisplayUsd,
        isRefreshing: _refreshing,
        hideBalances: settings.hideBalances,
        simpleNetWorth: settings.simpleNetWorth,
      );
      notifyListeners();
      return;
    }

    final PortfolioEntity? active = resolveActivePortfolio(
      _portfolios,
      settings.selectedPortfolioId,
    );
    _watchPortfolio(active?.id);

    if (active == null) {
      _scheduleBackgroundFxCheck();
      _state = HomeState(
        loading: false,
        portfolios: _portfolios,
        baseCurrency: settings.baseCurrency,
        displayInUsd: effectiveDisplayUsd,
        isRefreshing: _refreshing,
        hideBalances: settings.hideBalances,
        simpleNetWorth: settings.simpleNetWorth,
      );
      notifyListeners();
      return;
    }

    if (!_loadedAssets || !_loadedLiabilities) {
      _state = HomeState(
        loading: true,
        portfolios: _portfolios,
        activePortfolio: active,
        baseCurrency: settings.baseCurrency,
        displayInUsd: effectiveDisplayUsd,
        isRefreshing: _refreshing,
        hideBalances: settings.hideBalances,
        simpleNetWorth: settings.simpleNetWorth,
      );
      notifyListeners();
      return;
    }

    _scheduleBackgroundFxCheck();

    final NetWorthSummary summary = _calculator.calculate(
      assets: _assets,
      liabilities: _liabilities,
      baseCurrency: effectiveCurrency,
      converter: _converter,
    );

    _state = HomeState(
      loading: false,
      portfolios: _portfolios,
      activePortfolio: active,
      baseCurrency: settings.baseCurrency,
      displayInUsd: effectiveDisplayUsd,
      summary: summary,
      assetGroups: _buildAssetGroups(active.id, effectiveCurrency),
      liabilityGroups: _buildLiabilityGroups(active.id, effectiveCurrency),
      isRefreshing: _refreshing,
      hideBalances: settings.hideBalances,
      simpleNetWorth: settings.simpleNetWorth,
    );
    notifyListeners();
  }

  void _scheduleBackgroundFxCheck() {
    if (_startedBackgroundFxCheck) return;
    _startedBackgroundFxCheck = true;
    unawaited(_fxRepository.ensureFreshRates());
  }

  void _watchPortfolio(int? portfolioId) {
    if (portfolioId == _watchedPortfolioId) return;
    _watchedPortfolioId = portfolioId;
    _assetSub?.cancel();
    _liabilitySub?.cancel();
    _assets = const <AssetEntity>[];
    _liabilities = const <LiabilityEntity>[];
    _loadedAssets = false;
    _loadedLiabilities = false;
    if (portfolioId == null) return;
    _assetSub = _assetRepository.observeForPortfolio(portfolioId).listen((
      List<AssetEntity> assets,
    ) {
      _assets = assets;
      _loadedAssets = true;
      _rebuild();
    });
    _liabilitySub = _liabilityRepository
        .observeForPortfolio(portfolioId)
        .listen((List<LiabilityEntity> liabilities) {
          _liabilities = liabilities;
          _loadedLiabilities = true;
          _rebuild();
        });
  }

  List<AssetCategoryGroup> _buildAssetGroups(
    int portfolioId,
    String baseCurrency,
  ) {
    final List<String> savedOrder = _settingsRepository.categoryOrder(
      portfolioId,
      CategorySection.asset,
    );
    _lastAssetCategoryOrder = savedOrder;
    final Map<AssetType, List<AssetEntity>> byType =
        groupBy<AssetType, AssetEntity>(
          _assets,
          (AssetEntity a) => a.type.displayCategory,
        );
    final List<AssetType> ordered = orderTypes<AssetType>(
      byType.keys,
      savedOrder,
      (key) => AssetType.fromName(key).displayCategory,
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
    final List<String> savedOrder = _settingsRepository.categoryOrder(
      portfolioId,
      CategorySection.liability,
    );
    _lastLiabilityCategoryOrder = savedOrder;
    final Map<LiabilityType, List<LiabilityEntity>> byType =
        groupBy<LiabilityType, LiabilityEntity>(
          _liabilities,
          (LiabilityEntity l) => l.type,
        );
    final List<LiabilityType> ordered = orderTypes<LiabilityType>(
      byType.keys,
      savedOrder,
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
    _disposed = true;
    _settingsSub?.cancel();
    _portfolioSub?.cancel();
    _converterSub?.cancel();
    _assetSub?.cancel();
    _liabilitySub?.cancel();
    super.dispose();
  }
}
