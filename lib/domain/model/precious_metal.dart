enum PreciousMetal {
  gold('Gold', 'GC=F', 'e.g. Family gold', {
    '24K': 1,
    '22K': 22 / 24,
    '18K': 18 / 24,
    '14K': 14 / 24,
  }),
  silver('Silver', 'SI=F', 'e.g. Silver coins', {
    '999': .999,
    '925': .925,
    '900': .900,
  }),
  platinum('Platinum', 'PL=F', 'e.g. Platinum ring', {
    '999': .999,
    '950': .950,
    '900': .900,
  }),
  palladium('Palladium', 'PA=F', 'e.g. Palladium bar', {
    '999': .999,
    '950': .950,
  }),
  diamond('Diamond', null, 'e.g. Loose diamond', {}),
  gemstone('Other gemstone', null, 'e.g. Sapphire', {}),
  jewellery('Jewellery', null, 'e.g. Diamond engagement ring', {}),
  otherPrecious('Other precious item', null, 'e.g. Precious item', {});

  const PreciousMetal(this.label, this.ticker, this.nameExample, this.grades);

  final String label;
  final String? ticker;
  final String nameExample;
  final Map<String, double> grades;

  bool get hasPurity => grades.isNotEmpty;

  static PreciousMetal? fromName(Object? value) =>
      values.where((metal) => metal.name == value).firstOrNull;
}
