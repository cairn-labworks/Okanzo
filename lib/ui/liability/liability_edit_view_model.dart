import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/local/entity/liability_entity.dart';
import '../../data/repository/liability_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../domain/model/liability_type.dart';
import '../asset/asset_edit_view_model.dart' show AssetEditEventType;
import '../asset/asset_form_state.dart' show filterDecimal;
import 'liability_form_state.dart';

/// One-shot outcome of the liability editor. Reuses [AssetEditEventType] so
/// both editors share the same saved/deleted/error vocabulary.
class LiabilityEditEvent {
  const LiabilityEditEvent(this.type, [this.message]);

  final AssetEditEventType type;
  final String? message;
}

class LiabilityEditViewModel extends ChangeNotifier {
  LiabilityEditViewModel({
    required LiabilityRepository liabilityRepository,
    required SettingsRepository settingsRepository,
    required int portfolioId,
    required int liabilityId,
  }) : _liabilityRepository = liabilityRepository,
       _settingsRepository = settingsRepository,
       _liabilityId = liabilityId,
       _form = LiabilityFormState(portfolioId: portfolioId) {
    unawaited(_load());
  }

  final LiabilityRepository _liabilityRepository;
  final SettingsRepository _settingsRepository;
  final int _liabilityId;

  LiabilityFormState _form;
  LiabilityEditEvent? _event;
  bool _disposed = false;

  LiabilityFormState get form => _form;

  LiabilityEditEvent? get event => _event;

  Future<void> _load() async {
    if (_liabilityId != 0) {
      final LiabilityEntity? liability = await _liabilityRepository.getById(
        _liabilityId,
      );
      if (liability != null) {
        _form = LiabilityFormState.fromEntity(liability);
        notifyListeners();
        return;
      }
    }
    _update(
      _form.copyWith(
        currency: _settingsRepository.current.baseCurrency,
        loading: false,
      ),
    );
  }

  void _update(LiabilityFormState next) {
    _form = next;
    notifyListeners();
  }

  void onTypeChange(LiabilityType type) => _update(_form.copyWith(type: type));

  void onNameChange(String value) => _update(_form.copyWith(name: value));

  void onCurrencyChange(String value) =>
      _update(_form.copyWith(currency: value));

  void onAmountChange(String value) =>
      _update(_form.copyWith(amount: filterDecimal(value)));

  void onNotesChange(String value) => _update(_form.copyWith(notes: value));

  Future<void> save() async {
    if (_form.isSaving) return;
    final String? error = _form.validate();
    if (error != null) {
      _emit(LiabilityEditEvent(AssetEditEventType.error, error));
      return;
    }
    _update(_form.copyWith(isSaving: true));
    await _liabilityRepository.save(_form.toEntity());
    if (_disposed) return;
    _emit(const LiabilityEditEvent(AssetEditEventType.saved));
  }

  Future<void> delete() async {
    if (_liabilityId == 0) return;
    await _liabilityRepository.delete(_liabilityId);
    if (_disposed) return;
    _emit(const LiabilityEditEvent(AssetEditEventType.deleted));
  }

  void consumeEvent() {
    _event = null;
  }

  void _emit(LiabilityEditEvent event) {
    _event = event;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
