import 'package:flutter/material.dart';

import '../../data/local/entity/portfolio_entity.dart';
import '../../di/app_container.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import 'form_components.dart';
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
    this.alignmentEnd = false,
    this.style,
    super.key,
  });

  final int portfolioId;
  final String template;
  final bool uppercase;
  final bool alignmentEnd;
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
              textAlign: widget.alignmentEnd ? TextAlign.end : null,
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
    this.onCancel,
    this.cancelEnabled = true,
    this.priced = true,
    this.calculation,
    super.key,
  });

  final bool asset;
  final int portfolioId;
  final double amount;
  final String currency;
  final bool ready;
  final bool saving;
  final VoidCallback? onCancel;
  final bool cancelEnabled;
  final bool priced;
  final String? calculation;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String? effectiveCalculation = asset
        ? (calculation ??
              (priced
                  ? 'Current value in {currency}'
                        .tr(context)
                        .replaceAll('{currency}', currency)
                  : '0 × ${CurrencyUtil.format(0, currency)} · ${'price not fetched yet'.tr(context)}'))
        : null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.only(top: 2, bottom: 13),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) =>
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  (asset
                                          ? 'Estimated value'
                                          : 'Outstanding amount')
                                      .tr(context),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                    height: 1.25,
                                  ),
                                ),
                                if (effectiveCalculation != null &&
                                    effectiveCalculation
                                        .isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text(
                                    effectiveCalculation,
                                    key: ValueKey<String>(
                                      priced
                                          ? 'asset-valuation-caption'
                                          : 'asset-valuation-pending-caption',
                                    ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 11.5,
                                      height: 1.35,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.52,
                            ),
                            child: Text(
                              CurrencyUtil.format(amount, currency),
                              key: ValueKey<String>(
                                asset
                                    ? 'asset-estimated-value'
                                    : 'liability-outstanding-amount',
                              ),
                              textAlign: TextAlign.end,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontSize: 26,
                                height: 1.1,
                                letterSpacing: -0.65,
                                fontWeight: FontWeight.w600,
                                color: colors.primary,
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
              const SizedBox(height: 12),
              _FooterActions(
                asset: asset,
                ready: ready,
                saving: saving,
                onSave: onSave,
                onCancel: onCancel,
                cancelEnabled: cancelEnabled,
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
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterActions extends StatelessWidget {
  const _FooterActions({
    required this.asset,
    required this.ready,
    required this.saving,
    required this.onSave,
    required this.onCancel,
    required this.cancelEnabled,
  });

  final bool asset;
  final bool ready;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback? onCancel;
  final bool cancelEnabled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget saveButton = FilledButton(
      onPressed: !ready || saving ? null : onSave,
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              (asset ? 'Save asset' : 'Save liability').tr(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
    );
    if (onCancel == null) return saveButton;
    final Widget cancelButton = OutlinedButton(
      onPressed: cancelEnabled ? onCancel : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        side: BorderSide(color: canvasBoxBorderColor(colors)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: Text(
        'Cancel'.tr(context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= 260 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20) {
          return Row(
            children: <Widget>[
              Expanded(child: cancelButton),
              const SizedBox(width: 12),
              Expanded(child: saveButton),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            cancelButton,
            const SizedBox(height: 10),
            saveButton,
          ],
        );
      },
    );
  }
}
