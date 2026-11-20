import 'package:flutter/material.dart';

import '../../domain/model/asset_type.dart';
import '../../domain/model/liability_type.dart';
import '../../domain/model/precious_metal.dart';
import '../../domain/model/release_notes.dart';
import '../../domain/model/stock_exchange.dart';
import '../../util/currency_data.dart';

IconData assetTypeIcon(AssetType type) {
  switch (type) {
    case AssetType.stock:
      return Icons.show_chart;
    case AssetType.mutualFund:
      return Icons.pie_chart;
    case AssetType.crypto:
      return Icons.currency_bitcoin;
    case AssetType.gold:
      return metalIcon(PreciousMetal.gold);
    case AssetType.metals:
      return Icons.layers_outlined;
    case AssetType.cash:
      return Icons.payments;
    case AssetType.bankDeposit:
      return Icons.account_balance;
    case AssetType.realEstate:
      return Icons.home;
    case AssetType.vehicle:
      return Icons.directions_car;
    case AssetType.bond:
      return Icons.description;
    case AssetType.other:
      return Icons.category;
  }
}

IconData metalIcon(PreciousMetal metal) => switch (metal) {
  PreciousMetal.gold => Icons.view_agenda_outlined,
  PreciousMetal.silver => Icons.toll_outlined,
  PreciousMetal.platinum => Icons.view_in_ar_outlined,
  PreciousMetal.palladium => Icons.hexagon_outlined,
};

IconData liabilityTypeIcon(LiabilityType type) {
  switch (type) {
    case LiabilityType.loan:
      return Icons.account_balance_wallet;
    case LiabilityType.mortgage:
      return Icons.home_work;
    case LiabilityType.creditCard:
      return Icons.credit_card;
    case LiabilityType.pendingPayment:
      return Icons.schedule;
    case LiabilityType.tax:
      return Icons.receipt_long;
    case LiabilityType.other:
      return Icons.request_quote;
  }
}

IconData releaseHighlightIcon(ReleaseHighlightIcon icon) {
  switch (icon) {
    case ReleaseHighlightIcon.language:
      return Icons.translate_rounded;
    case ReleaseHighlightIcon.exchanges:
      return Icons.candlestick_chart_rounded;
    case ReleaseHighlightIcon.crypto:
      return Icons.currency_bitcoin_rounded;
    case ReleaseHighlightIcon.releaseNotes:
      return Icons.new_releases_outlined;
    case ReleaseHighlightIcon.portfolio:
      return Icons.pie_chart_outline_rounded;
    case ReleaseHighlightIcon.statistics:
      return Icons.insights_rounded;
    case ReleaseHighlightIcon.security:
      return Icons.lock_outline_rounded;
    case ReleaseHighlightIcon.backup:
      return Icons.import_export_rounded;
    case ReleaseHighlightIcon.currency:
      return Icons.currency_exchange_rounded;
    case ReleaseHighlightIcon.theme:
      return Icons.palette_outlined;
    case ReleaseHighlightIcon.assets:
      return Icons.trending_up_rounded;
    case ReleaseHighlightIcon.liabilities:
      return Icons.account_balance_wallet_outlined;
  }
}

IconData stockExchangeIcon(StockExchange exchange) {
  switch (exchange) {
    case StockExchange.us:
      return Icons.candlestick_chart;
    case StockExchange.euronextParis:
    case StockExchange.euronextAmsterdam:
    case StockExchange.euronextBrussels:
    case StockExchange.euronextLisbon:
    case StockExchange.euronextDublin:
    case StockExchange.euronextOslo:
    case StockExchange.euronextMilan:
      return Icons.hub_outlined;
    case StockExchange.shanghai:
    case StockExchange.tokyo:
    case StockExchange.hongKong:
    case StockExchange.bse:
      return Icons.account_balance;
    case StockExchange.other:
      return Icons.public;
  }
}

IconData currencyIcon(String currencyCode) {
  final String code = currencyCode.trim().toUpperCase();
  switch (code) {
    case 'EUR':
    case 'CHE':
      return Icons.euro;
    case 'GBP':
    case 'CYP':
    case 'EGP':
    case 'FKP':
    case 'GIP':
    case 'IEP':
    case 'LBP':
    case 'SDG':
    case 'SHP':
    case 'SSP':
    case 'SYP':
      return Icons.currency_pound;
    case 'INR':
    case 'LKR':
    case 'MUR':
    case 'NPR':
    case 'PKR':
    case 'SCR':
      return Icons.currency_rupee;
    case 'JPY':
      return Icons.currency_yen;
    case 'CNY':
      return Icons.currency_yuan;
    case 'CHF':
    case 'CHW':
    case 'BEF':
    case 'BIF':
    case 'CDF':
    case 'DJF':
    case 'FRF':
    case 'GNF':
    case 'KMF':
    case 'LUF':
    case 'MGF':
    case 'RWF':
    case 'XAF':
    case 'XFO':
    case 'XFU':
    case 'XOF':
    case 'XPF':
      return Icons.currency_franc;
    case 'TRY':
    case 'TRL':
    case 'ITL':
    case 'MTL':
      return Icons.currency_lira;
    case 'RUB':
    case 'RUR':
    case 'BYN':
    case 'BYR':
    case 'BYB':
      return Icons.currency_ruble;
    case 'XAU':
    case 'XAG':
    case 'XPD':
    case 'XPT':
    case 'ZWG':
      return Icons.diamond_outlined;
    case 'XBA':
    case 'XBB':
    case 'XBC':
    case 'XBD':
    case 'XDR':
    case 'XSU':
    case 'XUA':
      return Icons.currency_exchange;
  }
  final CurrencyInfo? info = kCurrencies[code];
  if (info != null &&
      (info.symbol.contains(r'$') ||
          info.displayName.contains('Dollar') ||
          info.displayName.contains('Peso'))) {
    return Icons.attach_money;
  }
  return Icons.payments_outlined;
}
