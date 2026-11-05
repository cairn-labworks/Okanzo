/// Exchanges offered by the stock/fund editor, using Yahoo Finance suffixes.
enum StockExchange {
  us('US (NYSE / Nasdaq)', '', 'USD', 'AAPL'),
  shanghai('Shanghai Stock Exchange', '.SS', 'CNY', '600519'),
  euronextParis('Euronext Paris', '.PA', 'EUR', 'AIR'),
  euronextAmsterdam('Euronext Amsterdam', '.AS', 'EUR', 'ASML'),
  euronextBrussels('Euronext Brussels', '.BR', 'EUR', 'ABI'),
  euronextLisbon('Euronext Lisbon', '.LS', 'EUR', 'EDP'),
  euronextDublin('Euronext Dublin', '.IR', 'EUR', 'KRX'),
  euronextOslo('Euronext Oslo', '.OL', 'NOK', 'EQNR'),
  euronextMilan('Euronext Milan', '.MI', 'EUR', 'ENI'),
  tokyo('Japan Exchange Group (Tokyo)', '.T', 'JPY', '7203'),
  hongKong('Hong Kong Stock Exchange', '.HK', 'HKD', '0700'),
  bse('BSE (India)', '.BO', 'INR', 'RELIANCE'),
  other('Other / full Yahoo ticker', '', null, 'VOD.L');

  const StockExchange(
    this.displayName,
    this.suffix,
    this.currency,
    this.example,
  );

  final String displayName;
  final String suffix;
  final String? currency;
  final String example;

  String qualify(String symbol) {
    final String cleaned = symbol.trim().toUpperCase();
    if (cleaned.isEmpty || suffix.isEmpty || cleaned.endsWith(suffix)) {
      return cleaned;
    }
    return '$cleaned$suffix';
  }

  static StockExchange fromSymbol(String symbol) {
    final String cleaned = symbol.trim().toUpperCase();
    for (final StockExchange exchange in values) {
      if (exchange.suffix.isNotEmpty && cleaned.endsWith(exchange.suffix)) {
        return exchange;
      }
    }
    return cleaned.contains('.') ? other : us;
  }
}
