import 'package:flutter/material.dart';

import '../../domain/model/asset_type.dart';
import '../../domain/model/liability_type.dart';
import '../../domain/model/release_notes.dart';

IconData assetTypeIcon(AssetType type) {
  switch (type) {
    case AssetType.stock:
      return Icons.show_chart;
    case AssetType.mutualFund:
      return Icons.pie_chart;
    case AssetType.crypto:
      return Icons.currency_bitcoin;
    case AssetType.gold:
      return Icons.diamond;
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
