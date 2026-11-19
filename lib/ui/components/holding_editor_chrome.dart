import 'package:flutter/material.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/local/entity/portfolio_entity.dart';
import '../../data/repository/currency_converter.dart';
import '../../data/repository/net_worth_calculator.dart';
import '../../domain/model/net_worth_summary.dart';
import '../../di/app_container.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import 'ui_components.dart';

class HoldingEditorHeading extends StatelessWidget {
  const HoldingEditorHeading({
    required this.portfolioId,
    required this.title,
    required this.asset,
    this.onKindSelected,
    this.enabled = true,
    super.key,
  });

  final int portfolioId;
  final String title;
  final bool asset;
  final bool enabled;
  final ValueChanged<bool>? onKindSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (onKindSelected != null) ...<Widget>[
          Row(
            children: <Widget>[
              for (final bool kind in <bool>[true, false])
                Flexible(
                  child: Semantics(
                    selected: kind == asset,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 2,
                            color: kind == asset
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: TextButton(
                        onPressed: enabled ? () => onKindSelected!(kind) : null,
                        style: TextButton.styleFrom(
                          foregroundColor: kind == asset
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          textStyle: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: kind == asset
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          minimumSize: const Size(48, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                        ),
                        child: Text(
                          (kind ? 'Asset / I own' : 'Liability / I owe').tr(
                            context,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 23),
        ],
        HoldingPortfolioLabel(
          portfolioId: portfolioId,
          template: 'To {portfolio}'.tr(context),
          uppercase: true,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1.35,
          ),
        ),
        const SizedBox(height: 9),
        PageHeading(title),
        const SizedBox(height: 10),
        Text(
          (asset
                  ? 'A little more of your picture, in one place.'
                  : 'Keep what you owe in perspective.')
              .tr(context),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.65,
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class HoldingPortfolioLabel extends StatefulWidget {
  const HoldingPortfolioLabel({
    required this.portfolioId,
    this.template = '{portfolio}',
    this.uppercase = false,
    this.style,
    super.key,
  });

  final int portfolioId;
  final String template;
  final bool uppercase;
  final TextStyle? style;

  @override
  State<HoldingPortfolioLabel> createState() => _HoldingPortfolioLabelState();
}

class _HoldingPortfolioLabelState extends State<HoldingPortfolioLabel> {
  Stream<List<PortfolioEntity>>? _portfolios;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _portfolios ??= AppScope.of(context).portfolioRepository.observeAll();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<PortfolioEntity>>(
    stream: _portfolios,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Text('Could not load portfolio.'.tr(context));
      }
      final PortfolioEntity? portfolio = snapshot.data
          ?.where((portfolio) => portfolio.id == widget.portfolioId)
          .firstOrNull;
      return portfolio == null
          ? const SizedBox.shrink()
          : Text(
              widget.uppercase
                  ? widget.template
                        .replaceAll('{portfolio}', portfolio.name)
                        .toUpperCase()
                  : widget.template.replaceAll('{portfolio}', portfolio.name),
              style: widget.style,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
    },
  );
}

class HoldingEditorFooter extends StatelessWidget {
  const HoldingEditorFooter({
    required this.portfolioId,
    required this.asset,
    required this.amount,
    required this.currency,
    required this.ready,
    required this.saving,
    required this.onSave,
    this.priced = true,
    super.key,
  });

  final bool asset;
  final int portfolioId;
  final double amount;
  final String currency;
  final bool ready;
  final bool saving;
  final bool priced;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(24, 12, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: HoldingPortfolioLabel(
                      portfolioId: portfolioId,
                      template:
                          '{portfolio} / ${(asset ? 'Assets' : 'Liabilities').tr(context)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Flexible(
                    fit: FlexFit.tight,
                    child: Text(
                      priced
                          ? CurrencyUtil.format(amount, currency)
                          : 'Price pending'.tr(context),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: !ready || saving ? null : onSave,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        (asset ? 'Save asset' : 'Save liability').tr(context),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                (!ready
                        ? 'Complete the required fields with valid values.'
                        : !priced
                        ? 'Ready to save without a price; refresh when available.'
                        : 'All required details are ready.')
                    .tr(context),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  height: 1.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HoldingNetWorthPreview extends StatefulWidget {
  const HoldingNetWorthPreview({
    required this.portfolioId,
    required this.holdingId,
    required this.asset,
    required this.value,
    required this.currency,
    this.priced = true,
    super.key,
  });

  final int portfolioId;
  final int holdingId;
  final bool asset;
  final double value;
  final String currency;
  final bool priced;

  @override
  State<HoldingNetWorthPreview> createState() => _HoldingNetWorthPreviewState();
}

class _HoldingNetWorthPreviewState extends State<HoldingNetWorthPreview> {
  Stream<List<AssetEntity>>? _assets;
  Stream<List<LiabilityEntity>>? _liabilities;
  Stream<CurrencyConverter>? _converter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppContainer container = AppScope.of(context);
    _assets ??= container.assetRepository.observeForPortfolio(
      widget.portfolioId,
    );
    _liabilities ??= container.liabilityRepository.observeForPortfolio(
      widget.portfolioId,
    );
    _converter ??= container.fxRepository.converter;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AssetEntity>>(
    stream: _assets,
    builder: (context, assets) => StreamBuilder<List<LiabilityEntity>>(
      stream: _liabilities,
      builder: (context, liabilities) => StreamBuilder<CurrencyConverter>(
        stream: _converter,
        builder: (context, converter) {
          if (assets.hasError || liabilities.hasError || converter.hasError) {
            return Text('Could not load portfolio totals.'.tr(context));
          }
          if (!assets.hasData || !liabilities.hasData || !converter.hasData) {
            return const SizedBox.shrink();
          }
          final String base = AppScope.of(context)
              .settingsRepository
              .current
              .baseCurrency;
          final CurrencyConverter rates = converter.data!;
          final NetWorthSummary summary = const NetWorthCalculator().calculate(
            assets: assets.data!,
            liabilities: liabilities.data!,
            baseCurrency: base,
            converter: rates,
          );
          final double current = summary.netWorth;
          final double previous = widget.asset
              ? assets.data!
                    .where((asset) => asset.id == widget.holdingId)
                    .fold(
                      0.0,
                      (sum, asset) =>
                          sum +
                          rates.convert(asset.value, asset.currency, base),
                    )
              : liabilities.data!
                    .where((liability) => liability.id == widget.holdingId)
                    .fold(
                      0.0,
                      (sum, liability) =>
                          sum +
                          rates.convert(
                            liability.value,
                            liability.currency,
                            base,
                          ),
                    );
          final double next =
              current +
              (widget.asset ? 1 : -1) *
                  (rates.convert(widget.value, widget.currency, base) -
                      previous);
          final ThemeData theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.only(top: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Column(
                  children: <Widget>[
                    _netRow(context, 'Current net worth', current, base, false),
                    const SizedBox(height: 12),
                    _netRow(
                      context,
                      widget.holdingId == 0
                          ? 'After this holding'
                          : 'After this update',
                      next,
                      base,
                      true,
                    ),
                    if (!widget.priced ||
                        (widget.currency != base &&
                            (!rates.canConvert(widget.currency) ||
                                !rates.canConvert(base))) ||
                        summary.hasApproximateConversions) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          (!widget.priced
                                  ? 'This asset is excluded until it has a price.'
                                  : 'Some values are approximate')
                              .tr(context),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _netRow(
    BuildContext context,
    String label,
    double amount,
    String currency,
    bool highlight,
  ) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          label.tr(context),
          style:
              (highlight
                      ? Theme.of(context).textTheme.bodyMedium
                      : Theme.of(context).textTheme.bodySmall)
                  ?.copyWith(
                    color: highlight
                        ? null
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
        ),
      ),
      Flexible(
        fit: FlexFit.tight,
        child: Text(
          CurrencyUtil.format(amount, currency),
          textAlign: TextAlign.end,
          style:
              (highlight
                      ? Theme.of(context).textTheme.bodyMedium
                      : Theme.of(context).textTheme.bodySmall)
                  ?.copyWith(
                    color: highlight
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    fontWeight: FontWeight.w600,
                  ),
        ),
      ),
    ],
  );
}
