import 'package:flutter/material.dart';

import '../../domain/model/net_worth_summary.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../theme/theme.dart';

/// Unboxed net-worth overview with the asset and liability totals.
class NetWorthCard extends StatelessWidget {
  const NetWorthCard({
    required this.summary,
    required this.hideBalances,
    this.simpleNetWorth = false,
    super.key,
  });

  final NetWorthSummary summary;
  final bool hideBalances;
  final bool simpleNetWorth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FinanceColors finance = FinanceColors.of(context);
    final Color onHero = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                'Net worth'.tr(context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (summary.hasApproximateConversions) ...<Widget>[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Some values are approximate'.tr(context),
                child: Icon(Icons.info_outlined, size: 16, color: onHero),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          hideBalances
              ? CurrencyUtil.masked(summary.baseCurrency)
              : simpleNetWorth
              ? CurrencyUtil.formatCompact(
                  summary.netWorth,
                  summary.baseCurrency,
                )
              : CurrencyUtil.format(summary.netWorth, summary.baseCurrency),
          key: const ValueKey<String>('net-worth-headline'),
          style: theme.textTheme.displaySmall?.copyWith(
            fontSize: 42,
            height: 1.15,
            letterSpacing: -1.8,
            fontWeight: FontWeight.w500,
            color: onHero,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${'Base currency'.tr(context)} · ${summary.baseCurrency}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricTile(
                icon: Icons.trending_up,
                accent: finance.positive,
                label: 'Assets'.tr(context),
                amount: hideBalances
                    ? CurrencyUtil.maskShort
                    : CurrencyUtil.format(
                        summary.totalAssets,
                        summary.baseCurrency,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                icon: Icons.trending_down,
                accent: finance.negative,
                label: 'Liabilities'.tr(context),
                amount: hideBalances
                    ? CurrencyUtil.maskShort
                    : CurrencyUtil.format(
                        summary.totalLiabilities,
                        summary.baseCurrency,
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.amount,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color labelColor = theme.colorScheme.onSurfaceVariant;
    final Color amountColor = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: labelColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              amount,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: amountColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
