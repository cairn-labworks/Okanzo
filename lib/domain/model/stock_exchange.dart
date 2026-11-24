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
  nse('NSE (India)', '.NS', 'INR', 'RELIANCE'),
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

  /// Representative company or fund example for helper text and search hints.
  (String name, String ticker) exampleHolding({
    bool fund = false,
  }) => switch (this) {
    StockExchange.us => fund ? ('Vanguard S&P 500', 'VOO') : ('Apple', 'AAPL'),
    StockExchange.shanghai =>
      fund ? ('CSI 300 ETF', '510300') : ('Kweichow Moutai', '600519'),
    StockExchange.euronextParis =>
      fund ? ('Amundi MSCI World', 'CW8') : ('Airbus', 'AIR'),
    StockExchange.euronextAmsterdam =>
      fund ? ('Vanguard All-World', 'VWRL') : ('ASML', 'ASML'),
    StockExchange.euronextBrussels =>
      fund ? ('iShares Core MSCI', 'IWDA') : ('AB InBev', 'ABI'),
    StockExchange.euronextLisbon =>
      fund ? ('PSI 20 ETF', 'PPP') : ('EDP', 'EDP'),
    StockExchange.euronextDublin =>
      fund ? ('iShares S&P 500', 'CSPX') : ('Kerry Group', 'KRX'),
    StockExchange.euronextOslo =>
      fund ? ('OBX ETF', 'OBX') : ('Equinor', 'EQNR'),
    StockExchange.euronextMilan =>
      fund ? ('FTSE MIB ETF', 'IMIB') : ('Eni', 'ENI'),
    StockExchange.tokyo => fund ? ('TOPIX ETF', '1306') : ('Toyota', '7203'),
    StockExchange.hongKong =>
      fund ? ('Tracker Fund', '2800') : ('Tencent', '0700'),
    StockExchange.bse || StockExchange.nse =>
      fund ? ('Nifty 50 ETF', 'NIFTYBEES') : ('Reliance', 'RELIANCE'),
    StockExchange.other =>
      fund ? ('Vanguard FTSE', 'VWRL.L') : ('Vodafone', 'VOD.L'),
  };

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
