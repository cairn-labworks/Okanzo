/// The category of a liability (something owed).
enum LiabilityType {
  loan('LOAN', 'Loan'),
  mortgage('MORTGAGE', 'Mortgage'),
  creditCard('CREDIT_CARD', 'Credit card'),
  pendingPayment('PENDING_PAYMENT', 'Pending payment'),
  tax('TAX', 'Tax due'),
  other('OTHER', 'Other');

  const LiabilityType(this.storageName, this.displayName);

  final String storageName;
  final String displayName;

  /// Short category hint shown beneath the label in selection pickers.
  String get pickerHint => switch (this) {
    LiabilityType.loan => 'Personal or other borrowing',
    LiabilityType.mortgage => 'Property borrowing',
    LiabilityType.creditCard => 'Outstanding card balance',
    LiabilityType.pendingPayment => 'A payment still owed',
    LiabilityType.tax => 'Outstanding taxes',
    LiabilityType.other => 'Another financial obligation',
  };

  static LiabilityType fromName(String? name) {
    for (final type in values) {
      if (type.storageName == name) return type;
    }
    return LiabilityType.other;
  }
}
