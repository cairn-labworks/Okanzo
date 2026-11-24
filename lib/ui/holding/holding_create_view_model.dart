import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/remote/stock/stock_price_service.dart';
import '../../data/remote/stock/stock_search_service.dart';
import '../../data/repository/asset_repository.dart';
import '../../data/repository/liability_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/holding_type.dart';
import '../../domain/model/precious_metal.dart';
import '../../domain/model/stock_exchange.dart';
import '../../util/result.dart';
import '../asset/asset_edit_view_model.dart' show AssetEditEventType;
import '../asset/asset_form_state.dart' show filterDecimal, formatInput;
import 'holding_create_form_state.dart';

class HoldingCreateEvent {
  const HoldingCreateEvent(
    this.type, {
    this.savedKind,
    this.savedAsset,
    this.savedLiability,
    this.message,
  });

  final AssetEditEventType type;
  final HoldingKind? savedKind;
  final AssetEntity? savedAsset;
  final LiabilityEntity? savedLiability;
  final String? message;
}

class HoldingCreateViewModel extends ChangeNotifier {
  HoldingCreateViewModel({
    required AssetRepository assetRepository,
    required LiabilityRepository liabilityRepository,
    required SettingsRepository settingsRepository,
    required int portfolioId,
    HoldingType initialType = const HoldingType.asset(AssetType.stock),
  }) : _assetRepository = assetRepository,
       _liabilityRepository = liabilityRepository,
       _settingsRepository = settingsRepository,
       _portfolioId = portfolioId,
       _form = HoldingCreateFormState(
         portfolioId: portfolioId,
         holdingType: initialType,
       ) {
    _load();
  }

  final AssetRepository _assetRepository;
  final LiabilityRepository _liabilityRepository;
  final SettingsRepository _settingsRepository;
  final int _portfolioId;

  HoldingCreateFormState _form;
  HoldingCreateEvent? _event;
  int _priceRequest = 0;
  int _nextSaveId = 0;
  int? _preparingSaveId;
  bool _isPersisting = false;
  bool _convertingCurrency = false;
  bool _cancelled = false;
  bool _disposed = false;
  Result<StockQuote>? _quoteAttempt;
  bool _metalOffline = false;

  HoldingCreateFormState get form => _form;

  HoldingCreateEvent? get event => _event;

  int get portfolioId => _portfolioId;

  List<StockExchange> get preferredExchanges =>
      _settingsRepository.current.preferredExchanges;

  Future<void> savePreferredExchanges(List<StockExchange> exchanges) async {
    if (_isPersisting) return;
    await _settingsRepository.setPreferredExchanges(exchanges);
    if (_disposed || _isPersisting) return;
    if (_form.symbol.trim().isEmpty &&
        !preferredExchanges.contains(_form.exchange)) {
      _form = _form.withExchange(
        preferredExchanges.firstOrNull ?? StockExchange.other,
      );
    }
    notifyListeners();
  }

  void _load() {
    final String base = _settingsRepository.current.baseCurrency;
    final StockExchange exchange =
        preferredExchanges.firstOrNull ?? StockExchange.other;
    _form = _form.copyWith(currency: base, exchange: exchange, loading: false);
  }

  void _update(HoldingCreateFormState next) {
    _form = next;
    notifyListeners();
  }

  void _updateQuoteInput(HoldingCreateFormState next) {
    if (_isPersisting) return;
    _quoteAttempt = null;
    _metalOffline = false;
    _priceRequest++;
    _preparingSaveId = null;
    _convertingCurrency = false;
    _update(
      next.copyWith(
        isFetchingPrice: false,
        isPreparingSave: false,
        isPersisting: _isPersisting,
      ),
    );
  }

  void onTypeChange(HoldingType type) {
    if (_isPersisting || type == _form.holdingType) return;
    final bool wasMarket = _form.isMarketLinked;
    final bool nextIsMarket = type.assetType?.isMarketLinked ?? false;
    final String nextName = switch ((wasMarket, nextIsMarket)) {
      (true, true) => '',
      (true, false) => _form.customName,
      (false, true) => '',
      (false, false) => _form.name,
    };
    final String nextCustomName = switch ((wasMarket, nextIsMarket)) {
      (false, true) =>
        _form.customName.trim().isNotEmpty ? _form.customName : _form.name,
      _ => _form.customName,
    };
    final bool nextUsesExchange =
        type.assetType == AssetType.stock ||
        type.assetType == AssetType.mutualFund;
    final StockExchange nextExchange =
        !_form.usesStockExchange &&
            nextUsesExchange &&
            _form.symbol.contains('.')
        ? StockExchange.fromSymbol(_form.symbol)
        : _form.exchange;
    final bool enteringOrLeavingMetals =
        type.assetType == AssetType.metals ||
        _form.holdingType.assetType == AssetType.metals;
    _updateQuoteInput(
      _form.copyWith(
        holdingType: type,
        name: nextName,
        customName: nextCustomName,
        clearMetal: true,
        customPrice: false,
        useTotalValue: false,
        pricePerUnit: enteringOrLeavingMetals ? '' : null,
        quantity:
            (type.assetType == AssetType.metals &&
                    _form.holdingType.assetType != AssetType.gold) ||
                _form.holdingType.assetType == AssetType.metals
            ? ''
            : null,
        exchange: nextExchange,
        clearLastPrice: true,
      ),
    );
  }

  void onNameChange(String value) {
    if (_isPersisting) return;
    _update(_form.copyWith(name: value));
  }

  void onCustomNameChange(String value) {
    if (_isPersisting) return;
    _update(_form.copyWith(customName: value));
  }

  Future<void> onCurrencyChange(String value) async {
    if (_isPersisting) return;
    if (_form.holdingType.assetType == AssetType.metals &&
        value != _form.currency) {
      _updateQuoteInput(
        _form.copyWith(
          currency: value,
          clearLastPrice: true,
          pricePerUnit: _form.customPrice ? null : '',
        ),
      );
      if (!_form.customPrice && !_form.useTotalValue) await fetchMetalPrice();
      return;
    }
    if (value == _form.currency) {
      if (_convertingCurrency) {
        _priceRequest++;
        _convertingCurrency = false;
        _update(_form.copyWith(isFetchingPrice: false));
      }
      return;
    }
    final int request = ++_priceRequest;
    _quoteAttempt = null;
    _preparingSaveId = null;
    final double? price = _form.lastPrice;
    if (!_form.isMarketLinked || price == null) {
      _convertingCurrency = false;
      _update(
        _form.copyWith(
          currency: value,
          isFetchingPrice: false,
          isPreparingSave: false,
          isPersisting: _isPersisting,
        ),
      );
      return;
    }
    final String from = _form.currency;
    _convertingCurrency = true;
    _update(
      _form.copyWith(
        isFetchingPrice: true,
        isPreparingSave: false,
        isPersisting: _isPersisting,
      ),
    );
    final Result<double> converted = await _assetRepository.convertPrice(
      price,
      from,
      value,
    );
    if (_disposed || _isPersisting || request != _priceRequest) return;
    _convertingCurrency = false;
    if (converted.isSuccess) {
      _update(
        _form.copyWith(
          currency: value,
          lastPrice: converted.value,
          isFetchingPrice: false,
        ),
      );
    } else {
      _update(_form.copyWith(isFetchingPrice: false));
      _emit(
        HoldingCreateEvent(
          AssetEditEventType.error,
          message: "Couldn't convert currency: ${converted.errorMessage}",
        ),
      );
    }
  }

  void onQuantityChange(String value) {
    if (_isPersisting) return;
    _update(_form.copyWith(quantity: filterDecimal(value)));
  }

  void onMetalChange(PreciousMetal metal) {
    if (_isPersisting || metal == _form.metal) return;
    _updateQuoteInput(
      _form.copyWith(
        metal: metal,
        clearPurity: true,
        clearLastPrice: true,
        pricePerUnit: '',
        customPrice: false,
        useTotalValue: !metal.hasPurity,
        quantity: '',
      ),
    );
  }

  Future<void> onPurityChange(String purity) async {
    if (_isPersisting ||
        _form.metal?.grades[purity] == null ||
        purity == _form.purity) {
      return;
    }
    _updateQuoteInput(
      _form.copyWith(
        purity: purity,
        clearLastPrice: !_form.customPrice,
        pricePerUnit: _form.customPrice ? null : '',
      ),
    );
    if (!_form.customPrice && !_form.useTotalValue) await fetchMetalPrice();
  }

  void onTotalValueChange(bool value) {
    if (_isPersisting || _form.useTotalValue == value) return;
    _updateQuoteInput(_form.copyWith(useTotalValue: value));
    if (!value && !_form.customPrice && _form.lastPrice == null) {
      unawaited(fetchMetalPrice());
    }
  }

  Future<void> fetchMetalPrice() async {
    if (_isPersisting) return;
    final PreciousMetal? metal = _form.metal;
    final String? purity = _form.purity;
    if (_form.holdingType.assetType != AssetType.metals ||
        _form.useTotalValue ||
        metal?.ticker == null ||
        purity == null) {
      return;
    }
    final int request = ++_priceRequest;
    _update(_form.copyWith(isFetchingPrice: true));
    final Result<double> result = await _assetRepository.fetchMetalPrice(
      metal!,
      purity,
      currency: _form.currency,
    );
    if (_disposed || _cancelled || _isPersisting || request != _priceRequest) {
      return;
    }
    _metalOffline = result.isOffline;
    _update(
      _form.copyWith(
        lastPrice: result.isSuccess ? result.value : null,
        pricePerUnit: result.isSuccess ? formatInput(result.value) : null,
        customPrice: result.isSuccess ? false : null,
        lastPriceTimestamp: result.isSuccess
            ? DateTime.now().millisecondsSinceEpoch
            : null,
        isFetchingPrice: false,
      ),
    );
    if (result.isFailure) {
      _emit(
        HoldingCreateEvent(
          AssetEditEventType.error,
          message: "Couldn't fetch price: ${result.errorMessage}",
        ),
      );
    }
  }

  void onPricePerUnitChange(String value) {
    if (_isPersisting) return;
    if (_form.holdingType.assetType == AssetType.metals) {
      _updateQuoteInput(_form.copyWith(pricePerUnit: value, customPrice: true));
    } else {
      _update(_form.copyWith(pricePerUnit: filterDecimal(value)));
    }
  }

  void onSymbolChange(String value) {
    if (_isPersisting) return;
    _updateQuoteInput(_form.withSymbol(value));
  }

  void onExchangeChange(StockExchange value) {
    if (_isPersisting || value == _form.exchange) return;
    _updateQuoteInput(_form.withExchange(value));
  }

  void onStockSelected(StockSearchResult result) {
    if (_isPersisting) return;
    _updateQuoteInput(
      _form.copyWith(
        symbol: result.symbol,
        exchange: _form.usesStockExchange
            ? StockExchange.fromSymbol(result.symbol)
            : _form.exchange,
        name: result.name,
        clearLastPrice: true,
      ),
    );
  }

  void onFlatAmountChange(String value) {
    if (_isPersisting) return;
    _update(
      _form.copyWith(
        flatAmount: _form.holdingType.assetType == AssetType.metals
            ? value
            : filterDecimal(value),
      ),
    );
  }

  void onNotesChange(String value) {
    if (_isPersisting) return;
    _update(_form.copyWith(notes: value));
  }

  Future<void> fetchPrice() async {
    if (_isPersisting) return;
    final String symbol = _form.quoteSymbol;
    final HoldingType holdingType = _form.holdingType;
    final StockExchange exchange = _form.exchange;
    final String currency = _form.currency;
    if (symbol.isEmpty) {
      _emit(
        const HoldingCreateEvent(
          AssetEditEventType.error,
          message: 'Enter a ticker symbol first',
        ),
      );
      return;
    }
    final int request = ++_priceRequest;
    _convertingCurrency = false;
    _update(_form.copyWith(isFetchingPrice: true));
    final Result<StockQuote> result = await _assetRepository.fetchQuote(
      symbol,
      currency: currency,
      isCrypto: holdingType.assetType == AssetType.crypto,
    );
    if (_disposed || _isPersisting) return;
    if (request != _priceRequest) {
      if (!_form.isFetchingPrice &&
          _form.holdingType == holdingType &&
          _form.exchange != exchange) {
        _emit(
          const HoldingCreateEvent(
            AssetEditEventType.error,
            message: 'Ticker or exchange changed; fetch the price again',
          ),
        );
      }
      return;
    }
    if (result.isSuccess) {
      _quoteAttempt = result;
      final String? fetchedName = result.value.name?.trim();
      _update(
        _form.copyWith(
          isFetchingPrice: false,
          lastPrice: result.value.price,
          lastPriceTimestamp: DateTime.now().millisecondsSinceEpoch,
          name: fetchedName != null && fetchedName.isNotEmpty
              ? fetchedName
              : null,
        ),
      );
    } else {
      _quoteAttempt = result;
      _update(_form.copyWith(isFetchingPrice: false));
      _emit(
        HoldingCreateEvent(
          AssetEditEventType.error,
          message: "Couldn't fetch price: ${result.errorMessage}",
        ),
      );
    }
  }

  Future<void> save() async {
    if (_isPersisting || _preparingSaveId != null) return;
    if (_form.isFetchingPrice) {
      _emit(
        const HoldingCreateEvent(
          AssetEditEventType.error,
          message: 'Wait for the price update to finish',
        ),
      );
      return;
    }
    final String? error = _form.validate();
    if (error != null) {
      _emit(HoldingCreateEvent(AssetEditEventType.error, message: error));
      return;
    }
    _cancelled = false;
    if (_form.isLiability) {
      final LiabilityEntity toSave = _form.toLiabilityEntity();
      _isPersisting = true;
      _update(_form.copyWith(isPreparingSave: false, isPersisting: true));
      final int savedId;
      try {
        savedId = await _liabilityRepository.save(toSave);
      } finally {
        _isPersisting = false;
        if (!_disposed) {
          _update(_form.copyWith(isPersisting: false));
        }
      }
      if (_disposed) return;
      _emit(
        HoldingCreateEvent(
          AssetEditEventType.saved,
          savedKind: HoldingKind.liability,
          savedLiability: toSave.copyWith(id: savedId),
        ),
      );
      return;
    }

    String? notice;
    if (_form.holdingType.assetType == AssetType.metals &&
        !_form.toAssetEntity().isPriced) {
      notice = _metalOffline
          ? 'No internet connection. Saved without latest price — refresh when online.'
          : 'Saved without a metal price. Refresh when available.';
    }
    if (_form.isMarketLinked && _form.lastPrice == null) {
      final Result<StockQuote>? cachedAttempt = _quoteAttempt;
      final Result<StockQuote> quote;
      if (cachedAttempt != null) {
        quote = cachedAttempt;
      } else {
        final int saveId = ++_nextSaveId;
        _preparingSaveId = saveId;
        final int request = ++_priceRequest;
        _convertingCurrency = false;
        _update(_form.copyWith(isPreparingSave: true));
        quote = await _assetRepository.fetchQuote(
          _form.quoteSymbol,
          currency: _form.currency,
          isCrypto: _form.holdingType.assetType == AssetType.crypto,
        );
        if (_disposed ||
            _cancelled ||
            _isPersisting ||
            _preparingSaveId != saveId ||
            request != _priceRequest) {
          if (!_disposed && _preparingSaveId == saveId) {
            _preparingSaveId = null;
            _update(_form.copyWith(isPreparingSave: false));
          }
          return;
        }
        _preparingSaveId = null;
      }
      if (quote.isSuccess) {
        final String? fetchedName = quote.value.name?.trim();
        _form = _form.copyWith(
          lastPrice: quote.value.price,
          lastPriceTimestamp: DateTime.now().millisecondsSinceEpoch,
          name: fetchedName != null && fetchedName.isNotEmpty
              ? fetchedName
              : null,
        );
      } else {
        notice = quote.isOffline
            ? 'No internet connection. Saved without latest price — refresh when online.'
            : 'Saved without latest price: ${quote.errorMessage}';
      }
    }
    if (_cancelled || _disposed || _isPersisting) return;
    final AssetEntity toSave = _form.toAssetEntity();
    _isPersisting = true;
    _update(_form.copyWith(isPreparingSave: false, isPersisting: true));
    final int savedId;
    try {
      savedId = await _assetRepository.save(toSave);
    } finally {
      _isPersisting = false;
      if (!_disposed) {
        _update(_form.copyWith(isPersisting: false));
      }
    }
    if (_disposed) return;
    _emit(
      HoldingCreateEvent(
        AssetEditEventType.saved,
        savedKind: HoldingKind.asset,
        savedAsset: toSave.copyWith(id: savedId),
        message: notice,
      ),
    );
  }

  void cancel() {
    if (_isPersisting) return;
    _cancelled = true;
    _preparingSaveId = null;
    _priceRequest++;
    _convertingCurrency = false;
    if (_form.isPreparingSave || _form.isFetchingPrice) {
      _update(_form.copyWith(isPreparingSave: false, isFetchingPrice: false));
    }
  }

  void consumeEvent() {
    _event = null;
  }

  void _emit(HoldingCreateEvent event) {
    _event = event;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
