import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/local/entity/portfolio_entity.dart';
import '../../di/app_container.dart';
import '../../domain/model/asset_type.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../../util/relative_time.dart';
import '../home/category_groups.dart' show formatQuantity;
import '../statistics/chart_format.dart';
import '../theme/theme.dart';
import 'form_components.dart';

Color holdingGlanceBarrierColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xAA10231B)
    : const Color(0x7310231B);

class HoldingGlanceDialog extends StatelessWidget {
  const HoldingGlanceDialog({
    this.asset,
    this.liability,
    this.portfolioName,
    required this.hideBalances,
    this.baseCurrency,
    this.convertedValue,
    this.isConversionApproximate = false,
    this.portfolioSectionTotal,
    this.isSectionTotalApproximate = false,
    this.status,
    this.notice,
    this.canClose = true,
    this.closeKey,
    required this.primaryLabel,
    this.primaryKey,
    required this.onPrimary,
    this.actions = const <Widget>[],
    super.key,
  }) : assert((asset == null) != (liability == null));

  final AssetEntity? asset;
  final LiabilityEntity? liability;
  final String? portfolioName;
  final bool hideBalances;
  final String? baseCurrency;
  final double? convertedValue;
  final bool isConversionApproximate;
  final double? portfolioSectionTotal;
  final bool isSectionTotalApproximate;
  final String? status;
  final Widget? notice;
  final bool canClose;
  final Key? closeKey;
  final String primaryLabel;
  final Key? primaryKey;
  final VoidCallback? onPrimary;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AssetEntity? asset = this.asset;
    final LiabilityEntity? liability = this.liability;
    final bool isAsset = asset != null;
    final int portfolioId = asset?.portfolioId ?? liability!.portfolioId;
    final String name = asset?.displayName ?? liability!.name;
    final String currency = asset?.currency ?? liability!.currency;
    final String typeLabel =
        (asset?.type.displayCategory.displayName ?? liability!.type.displayName)
            .tr(context);
    final String kindLabel = (isAsset ? 'Asset' : 'Liability').tr(context);
    final bool isPriced = asset?.isPriced ?? true;
    String money(double value) => hideBalances
        ? CurrencyUtil.maskShort
        : CurrencyUtil.format(value, currency);
    String quantity(double value) =>
        hideBalances ? CurrencyUtil.maskShort : formatQuantity(value);
    final String headlineValue = !isPriced
        ? 'Price pending'.tr(context)
        : hideBalances
        ? CurrencyUtil.masked(currency)
        : CurrencyUtil.format(asset?.value ?? liability!.value, currency);

    final List<(String, String)> detailRows = <(String, String)>[
      ('Type'.tr(context), typeLabel),
      ('Currency'.tr(context), currency),
      if (asset?.displayedMetal != null)
        ('Precious item'.tr(context), asset!.displayedMetal!.label.tr(context)),
      if (asset?.type == AssetType.metals && asset?.purity != null)
        ('Purity'.tr(context), asset!.purity!),
      if (isAsset && asset.symbol != null && asset.symbol!.trim().isNotEmpty)
        ('Ticker'.tr(context), asset.symbol!.trim()),
      if (isAsset && asset.type.isMarketLinked && asset.quantity != null)
        ('Quantity'.tr(context), quantity(asset.quantity!)),
      if (isAsset && asset.type.isMarketLinked)
        (
          'Last price'.tr(context),
          asset.lastPrice != null
              ? money(asset.lastPrice!)
              : 'Pending'.tr(context),
        ),
      if (isAsset &&
          (asset.type.valuationMode == ValuationMode.quantity ||
              asset.type == AssetType.metals && !asset.useTotalValue) &&
          asset.quantity != null)
        (
          'Weight'.tr(context),
          hideBalances
              ? CurrencyUtil.maskShort
              : '${formatQuantity(asset.quantity!)}${asset.type.unitLabel == null ? '' : ' ${asset.type.unitLabel}'}',
        ),
      if (isAsset &&
          asset.type != AssetType.metals &&
          asset.pricePerUnit != null)
        (
          'Price per {unit}'
              .tr(context)
              .replaceAll('{unit}', asset.type.unitLabel ?? 'unit'),
          money(asset.pricePerUnit!),
        ),
      if (isAsset && asset.type == AssetType.metals && !asset.useTotalValue)
        (
          'Price per gram'.tr(context),
          !asset.isPriced
              ? 'Pending'.tr(context)
              : hideBalances
              ? CurrencyUtil.maskShort
              : CurrencyUtil.formatRate(asset.metalRate!, currency),
        ),
      if (isAsset && asset.type == AssetType.metals)
        (
          'Valuation method'.tr(context),
          (asset.useTotalValue ? 'Total value' : 'By weight').tr(context),
        ),
      if (isAsset &&
          asset.type == AssetType.metals &&
          asset.customPrice &&
          !asset.useTotalValue)
        ('Price'.tr(context), 'Custom rate'.tr(context)),
      if ((asset?.notes ?? liability?.notes)?.trim().isNotEmpty ?? false)
        ('Notes'.tr(context), (asset?.notes ?? liability!.notes)!.trim()),
    ];

    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final FinanceColors finance = FinanceColors.of(context);
    final Color boxBorder = canvasBoxBorderColor(colors);
    final bool isMarketDerived =
        isAsset &&
        (asset.type.isMarketLinked ||
            (asset.type == AssetType.metals &&
                asset.metal?.ticker != null &&
                !asset.useTotalValue &&
                !asset.customPrice));
    final String sourceCore =
        (isMarketDerived ? 'Market quote' : 'Manual valuation').tr(context);
    final int provenanceTime = isMarketDerived
        ? (asset.lastPriceTimestamp ?? 0)
        : (asset?.updatedAt ?? liability!.updatedAt);
    final String sourceLabel = isMarketDerived && !isPriced
        ? '$sourceCore · ${'Price pending'.tr(context)}'
        : provenanceTime > 0
        ? '$sourceCore · ${relativeTimeSpan(provenanceTime, localizations: AppLocalizations.of(context))}'
        : sourceCore;
    final bool showConverted =
        isPriced &&
        !isConversionApproximate &&
        baseCurrency != null &&
        convertedValue != null &&
        currency != baseCurrency;
    final String sharePct =
        (isPriced &&
            !isConversionApproximate &&
            !isSectionTotalApproximate &&
            convertedValue != null &&
            portfolioSectionTotal != null &&
            portfolioSectionTotal! > 0)
        ? oneDecimalPercentageLabel(convertedValue!, portfolioSectionTotal!)
        : '';
    final double shareFraction =
        (sharePct.isNotEmpty && portfolioSectionTotal! > 0)
        ? (convertedValue! / portfolioSectionTotal!).clamp(0.0, 1.0)
        : 0.0;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: Dialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: boxBorder),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 375,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    key: closeKey,
                    tooltip: 'Close'.tr(context),
                    visualDensity: VisualDensity.compact,
                    onPressed: canClose
                        ? () => Navigator.of(context).pop()
                        : null,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ),
                Text(
                  status ?? '$kindLabel / $typeLabel'.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.35,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.6,
                    height: 1.25,
                    color: colors.onSurface,
                  ),
                ),
                if (asset?.customName != null &&
                    asset!.customName!.trim().isNotEmpty &&
                    asset.customName!.trim() != asset.name) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    asset.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            isMarketDerived ? Icons.sync : Icons.edit_outlined,
                            size: 13,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              sourceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  headlineValue,
                  key: const ValueKey<String>('holding-glance-headline-value'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: 34,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.8,
                    height: 1.3,
                    color: isAsset ? colors.primary : finance.negative,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (showConverted || sharePct.isNotEmpty) ...<Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (showConverted)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    'Portfolio value ({currency})'
                                        .tr(context)
                                        .replaceAll(
                                          '{currency}',
                                          baseCurrency!,
                                        ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 6,
                                  child: Text(
                                    hideBalances
                                        ? CurrencyUtil.maskShort
                                        : CurrencyUtil.format(
                                            convertedValue!,
                                            baseCurrency!,
                                          ),
                                    textAlign: TextAlign.end,
                                    style: theme.textTheme.bodySmall?.copyWith(
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
                          if (showConverted && sharePct.isNotEmpty)
                            const SizedBox(height: 8),
                          if (sharePct.isNotEmpty) ...<Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  flex: 6,
                                  child: Text(
                                    (isAsset
                                            ? 'Share of portfolio assets'
                                            : 'Share of portfolio liabilities')
                                        .tr(context),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  flex: 4,
                                  child: Text(
                                    sharePct,
                                    textAlign: TextAlign.end,
                                    style: theme.textTheme.bodySmall?.copyWith(
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
                            const SizedBox(height: 6),
                            ClipRRect(
                              key: const ValueKey<String>(
                                'holding-portfolio-share-bar',
                              ),
                              borderRadius: BorderRadius.circular(999),
                              child: ColoredBox(
                                color: colors.surfaceContainerHigh,
                                child: SizedBox(
                                  height: 5,
                                  child: FractionallySizedBox(
                                    alignment: AlignmentDirectional.centerStart,
                                    widthFactor: shareFraction,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: isAsset
                                            ? finance.positive
                                            : finance.negative,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    child: _PortfolioResolvedRows(
                      portfolioId: portfolioId,
                      portfolioName: portfolioName,
                      rows: detailRows,
                    ),
                  ),
                ),
                if (notice case final Widget message) ...<Widget>[
                  const SizedBox(height: 14),
                  message,
                ],
                const SizedBox(height: 22),
                FilledButton(
                  key: primaryKey,
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(primaryLabel),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PortfolioResolvedRows extends StatefulWidget {
  const _PortfolioResolvedRows({
    required this.portfolioId,
    required this.rows,
    this.portfolioName,
  });

  final int portfolioId;
  final String? portfolioName;
  final List<(String, String)> rows;

  @override
  State<_PortfolioResolvedRows> createState() => _PortfolioResolvedRowsState();
}

class _PortfolioResolvedRowsState extends State<_PortfolioResolvedRows> {
  Stream<List<PortfolioEntity>>? _portfolios;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.portfolioName == null) {
      _portfolios ??= AppScope.of(context).portfolioRepository.observeAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.portfolioName != null && widget.portfolioName!.isNotEmpty) {
      return _buildList(context, <(String, String)>[
        ('Portfolio'.tr(context), widget.portfolioName!),
        ...widget.rows,
      ]);
    }
    return StreamBuilder<List<PortfolioEntity>>(
      stream: _portfolios,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<PortfolioEntity>> snapshot,
          ) {
            final PortfolioEntity? portfolio = snapshot.data
                ?.where((PortfolioEntity item) => item.id == widget.portfolioId)
                .firstOrNull;
            return _buildList(context, <(String, String)>[
              if (portfolio != null) ('Portfolio'.tr(context), portfolio.name),
              ...widget.rows,
            ]);
          },
    );
  }

  Widget _buildList(BuildContext context, List<(String, String)> items) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int index = 0; index < items.length; index++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: index < items.length - 1
                  ? Border(bottom: BorderSide(color: colors.outlineVariant))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 4,
                    child: Text(
                      items[index].$1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 6,
                    child: Text(
                      items[index].$2,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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
          ),
      ],
    );
  }
}
