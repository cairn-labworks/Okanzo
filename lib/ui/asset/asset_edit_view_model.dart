import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/remote/stock/stock_price_service.dart';
import '../../data/repository/asset_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/stock_exchange.dart';
import '../../util/result.dart';
import 'asset_form_state.dart';

/// One-shot outcomes of the asset editor.
enum AssetEditEventType { saved, deleted, error }

class AssetEditEvent {
  const AssetEditEvent(this.type, [this.message]);

  final AssetEditEventType type;
  final String? message;
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
  AssetEditEvent? _event;
  int _priceRequest = 0;
  bool _convertingCurrency = false;
  bool _disposed = false;

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
    _priceRequest++;
    _convertingCurrency = false;
    _update(next.copyWith(isFetchingPrice: false));
  }

  void onTypeChange(AssetType type) {
    if (type == _form.type) return;
    _updateQuoteInput(
      _form.copyWith(
        type: type,
        exchange: _form.usesStockExchange
            ? _form.exchange
            : StockExchange.fromSymbol(_form.symbol),
        clearLastPrice: true,
      ),
    );
  }

  void onNameChange(String value) => _update(_form.copyWith(name: value));

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
    final double? price = _form.lastPrice;
    if (!_form.type.isMarketLinked || price == null) {
      _convertingCurrency = false;
      _update(_form.copyWith(currency: value, isFetchingPrice: false));
      return;
    }
    final String from = _form.currency;
    _convertingCurrency = true;
    _update(_form.copyWith(isFetchingPrice: true));
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
      final StockQuote quote = result.value;
      _update(
        _form.copyWith(
          isFetchingPrice: false,
          lastPrice: quote.price,
          lastPriceTimestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } else {
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
    await _assetRepository.save(_form.toEntity());
    _emit(const AssetEditEvent(AssetEditEventType.saved));
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
