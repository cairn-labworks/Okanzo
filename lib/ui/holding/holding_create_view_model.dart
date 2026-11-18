import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/remote/stock/stock_price_service.dart';
import '../../data/remote/stock/stock_search_service.dart';
import '../../data/repository/asset_repository.dart';
import '../../data/repository/liability_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/holding_type.dart';
import '../../domain/model/stock_exchange.dart';
import '../../util/result.dart';
import '../asset/asset_edit_view_model.dart' show AssetEditEventType;
import '../asset/asset_form_state.dart' show filterDecimal;
import 'holding_create_form_state.dart';

class HoldingCreateEvent {
  const HoldingCreateEvent(this.type, {this.savedKind, this.message});

  final AssetEditEventType type;
  final HoldingKind? savedKind;
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
  bool _convertingCurrency = false;
  bool _cancelled = false;
  bool _disposed = false;

  HoldingCreateFormState get form => _form;

  HoldingCreateEvent? get event => _event;

  int get portfolioId => _portfolioId;

  List<StockExchange> get preferredExchanges =>
      _settingsRepository.current.preferredExchanges;

  Future<void> savePreferredExchanges(List<StockExchange> exchanges) async {
    await _settingsRepository.setPreferredExchanges(exchanges);
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
    _priceRequest++;
    _convertingCurrency = false;
    _update(next.copyWith(isFetchingPrice: false, isSaving: false));
  }

  void onTypeChange(HoldingType type) {
    if (type == _form.holdingType) return;
    final bool nextUsesExchange =
        type.assetType == AssetType.stock ||
        type.assetType == AssetType.mutualFund;
    final StockExchange nextExchange =
        !_form.usesStockExchange &&
            nextUsesExchange &&
            _form.symbol.contains('.')
        ? StockExchange.fromSymbol(_form.symbol)
        : _form.exchange;
    _updateQuoteInput(
      _form.copyWith(
        holdingType: type,
        exchange: nextExchange,
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
    if (!_form.isMarketLinked || price == null) {
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
        HoldingCreateEvent(
          AssetEditEventType.error,
          message: "Couldn't convert currency: ${converted.errorMessage}",
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
        name: _form.name.trim().isEmpty ? result.name : _form.name,
        clearLastPrice: true,
      ),
    );
  }

  void onFlatAmountChange(String value) =>
      _update(_form.copyWith(flatAmount: filterDecimal(value)));

  void onNotesChange(String value) => _update(_form.copyWith(notes: value));

  Future<void> fetchPrice() async {
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
    if (_disposed) return;
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
      _update(
        _form.copyWith(
          isFetchingPrice: false,
          lastPrice: result.value.price,
          lastPriceTimestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } else {
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
    if (_form.isSaving) return;
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
    _update(_form.copyWith(isSaving: true));
    if (_form.isLiability) {
      await _liabilityRepository.save(_form.toLiabilityEntity());
      if (_cancelled || _disposed) return;
      _emit(
        const HoldingCreateEvent(
          AssetEditEventType.saved,
          savedKind: HoldingKind.liability,
        ),
      );
      return;
    }
    String? notice;
    if (_form.isMarketLinked && _form.lastPrice == null) {
      final int request = ++_priceRequest;
      _convertingCurrency = false;
      final Result<StockQuote> quote = await _assetRepository.fetchQuote(
        _form.quoteSymbol,
        currency: _form.currency,
        isCrypto: _form.holdingType.assetType == AssetType.crypto,
      );
      if (_cancelled || _disposed || request != _priceRequest) {
        if (!_cancelled && !_disposed && _form.isSaving) {
          _update(_form.copyWith(isSaving: false));
        }
        return;
      }
      if (quote.isSuccess) {
        _form = _form.copyWith(
          lastPrice: quote.value.price,
          lastPriceTimestamp: DateTime.now().millisecondsSinceEpoch,
        );
      } else {
        notice = quote.isOffline
            ? 'No internet connection. Saved without latest price — refresh when online.'
            : 'Saved without latest price: ${quote.errorMessage}';
      }
    }
    if (_cancelled || _disposed) return;
    await _assetRepository.save(_form.toAssetEntity());
    if (_cancelled || _disposed) return;
    _emit(
      HoldingCreateEvent(
        AssetEditEventType.saved,
        savedKind: HoldingKind.asset,
        message: notice,
      ),
    );
  }

  void cancel() {
    _cancelled = true;
    _priceRequest++;
    _convertingCurrency = false;
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
