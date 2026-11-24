import '../../data/local/entity/liability_entity.dart';
import '../../domain/model/liability_type.dart';
import '../asset/asset_form_state.dart'
    show formatInput, losesInputPrecision, numberPrecisionError;

/// Editable state of the liability form (pure data + validation).
class LiabilityFormState {
  const LiabilityFormState({
    this.id = 0,
    this.position = 0,
    this.portfolioId = 0,
    this.type = LiabilityType.loan,
    this.name = '',
    this.currency = 'USD',
    this.amount = '',
    this.notes = '',
    this.loading = true,
    this.isSaving = false,
  });

  final int id;
  final int position;
  final int portfolioId;
  final LiabilityType type;
  final String name;
  final String currency;
  final String amount;
  final String notes;
  final bool loading;
  final bool isSaving;

  bool get isEditing => id != 0;

  bool get hasPrecisionLoss => losesInputPrecision(amount);

  /// Returns the first validation error, or null when the form can be saved.
  String? validate() {
    if (name.trim().isEmpty) return 'Give this liability a name';
    if (currency.trim().isEmpty) return 'Choose a currency';
    if (hasPrecisionLoss) return numberPrecisionError;
    if (double.tryParse(amount)?.isFinite != true) return 'Enter an amount';
    return null;
  }

  /// Mirrors the Android editor: both timestamps are stamped with the current
  /// time, and the repository re-stamps [updatedAt] when saving.
  LiabilityEntity toEntity({int? now}) {
    final int timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    return LiabilityEntity(
      id: id,
      position: position,
      portfolioId: portfolioId,
      type: type,
      name: name.trim(),
      currency: currency.trim().toUpperCase(),
      amount: double.tryParse(amount) ?? 0.0,
      notes: notes.trim().isEmpty ? null : notes.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static LiabilityFormState fromEntity(LiabilityEntity liability) =>
      LiabilityFormState(
        id: liability.id,
        position: liability.position,
        portfolioId: liability.portfolioId,
        type: liability.type,
        name: liability.name,
        currency: liability.currency,
        amount: formatInput(liability.amount),
        notes: liability.notes ?? '',
        loading: false,
      );

  LiabilityFormState copyWith({
    int? id,
    int? portfolioId,
    LiabilityType? type,
    String? name,
    String? currency,
    String? amount,
    String? notes,
    bool? loading,
    bool? isSaving,
  }) {
    return LiabilityFormState(
      id: id ?? this.id,
      position: position,
      portfolioId: portfolioId ?? this.portfolioId,
      type: type ?? this.type,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      amount: amount ?? this.amount,
      notes: notes ?? this.notes,
      loading: loading ?? this.loading,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}
