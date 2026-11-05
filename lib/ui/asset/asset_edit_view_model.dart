import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/remote/stock/stock_price_service.dart';
import '../../data/repository/asset_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../domain/model/asset_type.dart';
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

  AssetFormState get form => _form;

  AssetEditEvent? get event => _event;

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
    _update(_form.copyWith(currency: base, loading: false));
  }

  void _update(AssetFormState next) {
    _form = next;
    notifyListeners();
  }

  void onTypeChange(AssetType type) =>
      _update(_form.copyWith(type: type, clearLastPrice: _form.type != type));

  void onNameChange(String value) => _update(_form.copyWith(name: value));

  void onCurrencyChange(String value) =>
      _update(_form.copyWith(currency: value));

  void onQuantityChange(String value) =>
      _update(_form.copyWith(quantity: filterDecimal(value)));

  void onPricePerUnitChange(String value) =>
      _update(_form.copyWith(pricePerUnit: filterDecimal(value)));

  void onSymbolChange(String value) =>
      _update(_form.copyWith(symbol: value, clearLastPrice: true));

  void onManualValueChange(String value) =>
      _update(_form.copyWith(manualValue: filterDecimal(value)));

  void onNotesChange(String value) => _update(_form.copyWith(notes: value));

  Future<void> fetchPrice() async {
    final String symbol = _form.symbol.trim();
    final AssetType type = _form.type;
    if (symbol.isEmpty) {
      _emit(
        const AssetEditEvent(
          AssetEditEventType.error,
          'Enter a ticker symbol first',
        ),
      );
      return;
    }
    _update(_form.copyWith(isFetchingPrice: true));
    final Result<StockQuote> result = await _assetRepository.fetchQuote(
      symbol,
      isCrypto: type == AssetType.crypto,
    );
    if (_form.type != type || _form.symbol.trim() != symbol) {
      _update(_form.copyWith(isFetchingPrice: false));
      return;
    }
    if (result.isSuccess) {
      final StockQuote quote = result.value;
      _update(
        _form.copyWith(
          isFetchingPrice: false,
          lastPrice: quote.price,
          lastPriceTimestamp: DateTime.now().millisecondsSinceEpoch,
          currency: quote.currency ?? _form.currency,
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
}
