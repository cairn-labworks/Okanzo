import 'package:flutter/material.dart';

import '../../domain/model/net_worth_summary.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../theme/app_style.dart';
import '../theme/theme.dart';

/// The headline card: net worth plus the asset and liability totals.
class NetWorthCard extends StatelessWidget {
  const NetWorthCard({
    required this.summary,
    required this.hideBalances,
    super.key,
  });

  final NetWorthSummary summary;
  final bool hideBalances;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FinanceColors finance = FinanceColors.of(context);
    final AppStyle style = AppStyle.of(context);
    final List<Color>? gradient = style.heroGradient;
    final bool onGradient = gradient != null;
    final Color onHero =
        style.heroForeground ?? theme.colorScheme.onPrimaryContainer;
    final Widget content = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Net worth'.tr(context),
                style: theme.textTheme.labelLarge?.copyWith(color: onHero),
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
          const SizedBox(height: 6),
          Text(
            hideBalances
                ? CurrencyUtil.masked(summary.baseCurrency)
                : CurrencyUtil.format(summary.netWorth, summary.baseCurrency),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: onHero,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricTile(
                  icon: Icons.trending_up,
                  accent: onGradient ? onHero : finance.positive,
                  onGradient: onGradient,
                  onHero: onHero,
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
                  accent: onGradient ? onHero : finance.negative,
                  onGradient: onGradient,
                  onHero: onHero,
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
      ),
    );
    return Card(
      color: onGradient
          ? Colors.transparent
          : theme.colorScheme.primaryContainer,
      elevation: onGradient ? 0 : null,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeExtraLarge),
      ),
      child: onGradient
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
              ),
              child: content,
            )
          : content,
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.amount,
    required this.onGradient,
    required this.onHero,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String amount;

  /// Whether the tile sits on the gradient hero (Midnight theme).
  final bool onGradient;
  final Color onHero;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color labelColor = onGradient
        ? onHero.withValues(alpha: 0.85)
        : theme.colorScheme.onSurfaceVariant;
    final Color amountColor = onGradient ? onHero : theme.colorScheme.onSurface;
    return Material(
      color: onGradient
          ? Colors.white.withValues(alpha: 0.16)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(shapeLarge),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: labelColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: amountColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
