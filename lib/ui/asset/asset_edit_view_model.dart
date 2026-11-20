import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/remote/stock/stock_price_service.dart';
import '../../data/remote/stock/stock_search_service.dart';
import '../../data/repository/asset_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/stock_exchange.dart';
import '../../util/result.dart';
import 'asset_form_state.dart';

/// One-shot outcomes of the asset editor.
enum AssetEditEventType { saved, deleted, error }

class AssetEditEvent {
  const AssetEditEvent(
    this.type, [
    this.message,
    this.savedAsset,
    this.previousAsset,
  ]);

  final AssetEditEventType type;
  final String? message;
  final AssetEntity? savedAsset;
  final AssetEntity? previousAsset;
}

class AssetEditViewModel extends ChangeNotifier {
  AssetEditViewModel({
    required AssetRepository assetRepository,
    required SettingsRepository settingsRepository,
    required int portfolioId,
    required int assetId,
  }) : _assetRepository = assetRepository,
       _settingsRepository = settingsRepository,
       _portfolioId = portfolioId,
       _assetId = assetId,
       _form = AssetFormState(portfolioId: portfolioId) {
    unawaited(_load());
  }

  final AssetRepository _assetRepository;
  final SettingsRepository _settingsRepository;
  final int _portfolioId;
  final int _assetId;

  AssetFormState _form;
  AssetEntity? _loadedEntity;
  AssetEditEvent? _event;
  int _priceRequest = 0;
  bool _convertingCurrency = false;
  bool _cancelled = false;
  bool _disposed = false;
  Result<StockQuote>? _quoteAttempt;

  AssetFormState get form => _form;

  AssetEditEvent? get event => _event;

  List<StockExchange> get preferredExchanges =>
      _settingsRepository.current.preferredExchanges;

  Future<void> savePreferredExchanges(List<StockExchange> exchanges) async {
    await _settingsRepository.setPreferredExchanges(exchanges);
    if (!_form.isEditing &&
        _form.symbol.trim().isEmpty &&
        !preferredExchanges.contains(_form.exchange)) {
      _form = _form.withExchange(
        preferredExchanges.firstOrNull ?? StockExchange.other,
      );
    }
    notifyListeners();
  }

  Future<void> _load() async {
    if (_assetId != 0) {
      final AssetEntity? asset = await _assetRepository.getById(_assetId);
      if (asset != null) {
        _loadedEntity = asset;
        _form = AssetFormState.fromEntity(asset);
        notifyListeners();
        return;
      }
    }
    final String base = _settingsRepository.current.baseCurrency;
    final StockExchange exchange =
        preferredExchanges.firstOrNull ?? StockExchange.other;
    _update(_form.copyWith(currency: base, exchange: exchange, loading: false));
  }

  void _update(AssetFormState next) {
    _form = next;
    notifyListeners();
  }

  void _updateQuoteInput(AssetFormState next) {
    _quoteAttempt = null;
    _priceRequest++;
    _convertingCurrency = false;
    _update(next.copyWith(isFetchingPrice: false, isSaving: false));
  }

  void onTypeChange(AssetType type) {
    if (type == _form.type) return;
    final bool wasMarket = _form.type.isMarketLinked;
    final bool isMarket = type.isMarketLinked;
    final String nextName = switch ((wasMarket, isMarket)) {
      (true, true) => '',
      (true, false) => _form.customName,
      (false, true) => '',
      (false, false) => _form.name,
    };
    final String nextCustomName = switch ((wasMarket, isMarket)) {
      (false, true) =>
        _form.customName.trim().isNotEmpty ? _form.customName : _form.name,
      _ => _form.customName,
    };
    _updateQuoteInput(
      _form.copyWith(
        type: type,
        name: nextName,
        customName: nextCustomName,
        exchange: _form.usesStockExchange
            ? _form.exchange
            : StockExchange.fromSymbol(_form.symbol),
        clearLastPrice: true,
      ),
    );
  }

  void onNameChange(String value) => _update(_form.copyWith(name: value));

  void onCustomNameChange(String value) =>
      _update(_form.copyWith(customName: value));

  Future<void> onCurrencyChange(String value) async {
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
    final double? price = _form.lastPrice;
    if (!_form.type.isMarketLinked || price == null) {
      _convertingCurrency = false;
      _update(
        _form.copyWith(
          currency: value,
          isFetchingPrice: false,
          isSaving: false,
        ),
      );
      return;
    }
    final String from = _form.currency;
    _convertingCurrency = true;
    _update(_form.copyWith(isFetchingPrice: true, isSaving: false));
    final Result<double> converted = await _assetRepository.convertPrice(
      price,
      from,
      value,
    );
    if (_disposed || request != _priceRequest) return;
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
        AssetEditEvent(
          AssetEditEventType.error,
          "Couldn't convert currency: ${converted.errorMessage}",
        ),
      );
    }
  }

  void onQuantityChange(String value) =>
      _update(_form.copyWith(quantity: filterDecimal(value)));

  void onPricePerUnitChange(String value) =>
      _update(_form.copyWith(pricePerUnit: filterDecimal(value)));

  void onSymbolChange(String value) =>
      _updateQuoteInput(_form.withSymbol(value));

  void onExchangeChange(StockExchange value) {
    if (value != _form.exchange) {
      _updateQuoteInput(_form.withExchange(value));
    }
  }

  void onStockSelected(StockSearchResult result) {
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

  void onManualValueChange(String value) =>
      _update(_form.copyWith(manualValue: filterDecimal(value)));

  void onNotesChange(String value) => _update(_form.copyWith(notes: value));

  Future<void> fetchPrice() async {
    final String symbol = _form.quoteSymbol;
    final AssetType type = _form.type;
    final StockExchange exchange = _form.exchange;
    final String currency = _form.currency;
    if (symbol.isEmpty) {
      _emit(
        const AssetEditEvent(
          AssetEditEventType.error,
          'Enter a ticker symbol first',
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
      isCrypto: type == AssetType.crypto,
    );
    if (_disposed) return;
    if (request != _priceRequest) {
      if (!_form.isFetchingPrice &&
          _form.type == type &&
          _form.exchange != exchange) {
        _emit(
          const AssetEditEvent(
            AssetEditEventType.error,
            'Ticker or exchange changed; fetch the price again',
          ),
        );
      }
      return;
    }
    if (result.isSuccess) {
      _quoteAttempt = result;
      final StockQuote quote = result.value;
      final String? fetchedName = quote.name?.trim();
      _update(
        _form.copyWith(
          isFetchingPrice: false,
          lastPrice: quote.price,
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
        AssetEditEvent(
          AssetEditEventType.error,
          "Couldn't fetch price: ${result.errorMessage}",
        ),
      );
    }
  }

  Future<void> save() async {
    if (_form.isSaving) return;
    if (_form.isFetchingPrice) {
      _emit(
        const AssetEditEvent(
          AssetEditEventType.error,
          'Wait for the price update to finish',
        ),
      );
      return;
    }
    final String? error = _form.validate();
    if (error != null) {
      _emit(AssetEditEvent(AssetEditEventType.error, error));
      return;
    }
    _update(_form.copyWith(isSaving: true));
    String? notice;
    if (_form.valuationMode == ValuationMode.market &&
        _form.lastPrice == null) {
      final int request = ++_priceRequest;
      _convertingCurrency = false;
      final Result<StockQuote> quote =
          _quoteAttempt ??
          await _assetRepository.fetchQuote(
            _form.quoteSymbol,
            currency: _form.currency,
            isCrypto: _form.type == AssetType.crypto,
          );
      if (_cancelled || _disposed || request != _priceRequest) {
        if (!_cancelled && !_disposed && _form.isSaving) {
          _update(_form.copyWith(isSaving: false));
        }
        return;
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
    if (_cancelled || _disposed) return;
    final AssetEntity toSave = _form.toEntity();
    final int savedId = await _assetRepository.save(toSave);
    if (_cancelled || _disposed) return;
    _emit(
      AssetEditEvent(
        AssetEditEventType.saved,
        notice,
        toSave.copyWith(id: savedId),
        _loadedEntity,
      ),
    );
  }

  void cancel() {
    _cancelled = true;
    _priceRequest++;
    _convertingCurrency = false;
  }

  Future<void> delete() async {
    if (_assetId == 0) return;
    await _assetRepository.delete(_assetId);
    _emit(const AssetEditEvent(AssetEditEventType.deleted));
  }

  void consumeEvent() {
    _event = null;
  }

  void _emit(AssetEditEvent event) {
    _event = event;
    notifyListeners();
  }

  int get portfolioId => _portfolioId;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
