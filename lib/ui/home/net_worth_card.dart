import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/model/net_worth_summary.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/form_components.dart' show canvasBoxBorderColor;
import '../statistics/chart_format.dart';
import '../theme/app_material.dart';
import '../theme/app_style.dart';
import '../theme/motion.dart';
import '../theme/theme.dart';

/// Rounded tonal net-worth block with color-coded asset/liability tiles and split bar.
class NetWorthCard extends StatelessWidget {
  const NetWorthCard({
    required this.summary,
    required this.hideBalances,
    this.simpleNetWorth = false,
    this.configuredBaseCurrency,
    this.showingUsd = false,
    this.onToggleCurrency,
    super.key,
  });

  final NetWorthSummary summary;
  final bool hideBalances;
  final bool simpleNetWorth;
  final String? configuredBaseCurrency;
  final bool showingUsd;
  final VoidCallback? onToggleCurrency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool enhanced = AppStyle.of(context).isEnhanced;
    final FinanceColors finance = FinanceColors.of(context);
    final String baseCode = configuredBaseCurrency ?? summary.baseCurrency;
    final bool isNegative = !hideBalances && summary.netWorth < -0.005;
    final Color headlineColor = isNegative ? finance.negative : colors.primary;
    final bool showCoverage =
        !hideBalances &&
        (summary.totalAssets > 0 || summary.totalLiabilities > 0);

    return AppSurface(
      radius: 24,
      hero: true,
      child: DecoratedBox(
        key: const ValueKey<String>('net-worth-block'),
        decoration: BoxDecoration(
          color: enhanced ? Colors.transparent : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: enhanced ? null : Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) =>
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  'Net worth'.tr(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textHeightBehavior: const TextHeightBehavior(
                                    applyHeightToFirstAscent: false,
                                    applyHeightToLastDescent: false,
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    height: 1.15,
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (summary
                                  .hasApproximateConversions) ...<Widget>[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: 'Some values are approximate'.tr(
                                    context,
                                  ),
                                  child: Icon(
                                    Icons.info_outlined,
                                    size: 16,
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (baseCode == 'USD')
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.65,
                            ),
                            child: DecoratedBox(
                              key: const ValueKey<String>(
                                'net-worth-base-currency-pill',
                              ),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 5,
                                ),
                                child: Text(
                                  'USD',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  textHeightBehavior: const TextHeightBehavior(
                                    applyHeightToFirstAscent: false,
                                    applyHeightToLastDescent: false,
                                  ),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 11,
                                    height: 1.1,
                                    letterSpacing: 0.3,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          _CurrencyPillToggle(
                            baseCode: baseCode,
                            showingUsd: showingUsd,
                            maxWidth: constraints.maxWidth * 0.65,
                            onToggle: onToggleCurrency,
                          ),
                      ],
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                hideBalances
                    ? CurrencyUtil.masked(summary.baseCurrency)
                    : simpleNetWorth
                    ? CurrencyUtil.formatCompact(
                        summary.netWorth,
                        summary.baseCurrency,
                      )
                    : CurrencyUtil.format(
                        summary.netWorth,
                        summary.baseCurrency,
                      ),
                key: const ValueKey<String>('net-worth-headline'),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 42,
                  height: 1.15,
                  letterSpacing: -1.8,
                  fontWeight: FontWeight.w500,
                  color: headlineColor,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _MetricTile(
                      key: const ValueKey<String>('net-worth-assets-tile'),
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      key: const ValueKey<String>('net-worth-liabilities-tile'),
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
              if (showCoverage) ...<Widget>[
                const SizedBox(height: 14),
                _CoverageBar(summary: summary, isNegative: isNegative),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverageBar extends StatelessWidget {
  const _CoverageBar({required this.summary, required this.isNegative});

  final NetWorthSummary summary;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final FinanceColors finance = FinanceColors.of(context);
    final double total = summary.totalAssets + summary.totalLiabilities;
    final bool hasAssets = summary.totalAssets > 0;
    final bool hasLiabilities = summary.totalLiabilities > 0;
    final double targetAssetsFraction = total > 0
        ? (summary.totalAssets / total).clamp(0.0, 1.0)
        : 0.0;
    final String assetsPct = oneDecimalPercentageLabel(
      summary.totalAssets,
      total,
    );
    final String liabilitiesPct = oneDecimalPercentageLabel(
      summary.totalLiabilities,
      total,
    );

    return Column(
      key: const ValueKey<String>('net-worth-coverage-bar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 8,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: targetAssetsFraction),
                  duration: interactionDuration(context),
                  curve: interactionCurve,
                  builder:
                      (BuildContext context, double fraction, Widget? child) {
                        if (hasAssets && !hasLiabilities) {
                          return SizedBox(
                            width: constraints.maxWidth,
                            height: 8,
                            child: DecoratedBox(
                              key: const ValueKey<String>(
                                'net-worth-assets-bar-segment',
                              ),
                              decoration: BoxDecoration(
                                color: finance.positive,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          );
                        }
                        if (!hasAssets && hasLiabilities) {
                          return SizedBox(
                            width: constraints.maxWidth,
                            height: 8,
                            child: DecoratedBox(
                              key: const ValueKey<String>(
                                'net-worth-liabilities-bar-segment',
                              ),
                              decoration: BoxDecoration(
                                color: finance.negative,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          );
                        }
                        final double gap = constraints.maxWidth > 12 ? 3.0 : 0;
                        final double usable = math.max(
                          0.0,
                          constraints.maxWidth - gap,
                        );
                        final double clamped = fraction.clamp(0.0, 1.0);
                        final double assetsWidth = usable * clamped;
                        final double liabilitiesWidth = usable * (1 - clamped);
                        return Row(
                          children: <Widget>[
                            SizedBox(
                              width: assetsWidth,
                              height: 8,
                              child: DecoratedBox(
                                key: const ValueKey<String>(
                                  'net-worth-assets-bar-segment',
                                ),
                                decoration: BoxDecoration(
                                  color: finance.positive,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            SizedBox(width: gap),
                            SizedBox(
                              width: liabilitiesWidth,
                              height: 8,
                              child: DecoratedBox(
                                key: const ValueKey<String>(
                                  'net-worth-liabilities-bar-segment',
                                ),
                                decoration: BoxDecoration(
                                  color: finance.negative,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: <Widget>[
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: finance.positive,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 6, height: 6),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${'Assets'.tr(context)} ${assetsPct.isEmpty ? '0.0%' : assetsPct}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: finance.negative,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox(width: 6, height: 6),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${'Liabilities'.tr(context)} ${liabilitiesPct.isEmpty ? '0.0%' : liabilitiesPct}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (isNegative) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            'Liabilities exceed assets'.tr(context),
            style: theme.textTheme.labelSmall?.copyWith(
              color: finance.negative,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
    super.key,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color tileBackground = Color.lerp(
      colors.surface,
      accent,
      isDark ? 0.11 : 0.08,
    )!;
    final Color tileBorder = Color.lerp(colors.outlineVariant, accent, 0.42)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tileBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tileBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3.5),
                    child: Icon(icon, size: 13, color: accent),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
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
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyPillToggle extends StatelessWidget {
  const _CurrencyPillToggle({
    required this.baseCode,
    required this.showingUsd,
    required this.maxWidth,
    this.onToggle,
  });

  final String baseCode;
  final bool showingUsd;
  final double maxWidth;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final double targetWidth = math.min(
      maxWidth,
      MediaQuery.textScalerOf(context).scale(98).clamp(98.0, 152.0),
    );
    final List<(String code, bool active)> segments = <(String, bool)>[
      (baseCode, !showingUsd),
      ('USD', showingUsd),
    ];

    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        toggled: showingUsd,
        label: '$baseCode / USD',
        child: InkWell(
          key: const ValueKey<String>('net-worth-base-currency-pill'),
          borderRadius: BorderRadius.circular(999),
          onTap: onToggle,
          child: SizedBox(
            width: targetWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: canvasBoxBorderColor(colors)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.5),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: AnimatedAlign(
                        alignment: showingUsd
                            ? AlignmentDirectional.centerEnd
                            : AlignmentDirectional.centerStart,
                        duration: interactionDuration(context),
                        curve: interactionCurve,
                        child: FractionallySizedBox(
                          widthFactor: 0.5,
                          heightFactor: 1.0,
                          child: DecoratedBox(
                            key: const ValueKey<String>(
                              'net-worth-currency-thumb',
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        for (final (String code, bool active) in segments)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4.5,
                              ),
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: interactionDuration(context),
                                  curve: interactionCurve,
                                  style:
                                      (theme.textTheme.labelSmall ??
                                              const TextStyle())
                                          .copyWith(
                                            fontSize: 10.5,
                                            height: 1.1,
                                            letterSpacing: 0.25,
                                            fontWeight: FontWeight.w600,
                                            color: active
                                                ? colors.onPrimary
                                                : colors.onSurfaceVariant,
                                          ),
                                  child: Text(
                                    code,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    textHeightBehavior:
                                        const TextHeightBehavior(
                                          applyHeightToFirstAscent: false,
                                          applyHeightToLastDescent: false,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
