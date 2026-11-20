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
  });

  const PreciousMetal(this.label, this.ticker, this.nameExample, this.grades);

  final String label;
  final String ticker;
  final String nameExample;
  final Map<String, double> grades;

  static PreciousMetal? fromName(Object? value) =>
      values.where((metal) => metal.name == value).firstOrNull;
}
