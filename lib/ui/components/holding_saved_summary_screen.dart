import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/repository/currency_converter.dart';
import '../../data/repository/net_worth_calculator.dart';
import '../../di/app_container.dart';
import '../../domain/model/net_worth_summary.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import 'form_components.dart';
import 'holding_create_screen.dart';
import 'holding_editor_chrome.dart';

/// Post-save confirmation summary matching the Canvas prototype's `success`
/// screen when an asset or liability is added or updated.
class HoldingSavedSummaryScreen extends StatefulWidget {
  const HoldingSavedSummaryScreen({
    required this.portfolioId,
    required this.updated,
    this.savedAsset,
    this.previousAsset,
    this.savedLiability,
    this.previousLiability,
    this.notice,
    super.key,
  }) : assert((savedAsset == null) != (savedLiability == null));

  final int portfolioId;
  final bool updated;
  final AssetEntity? savedAsset;
  final AssetEntity? previousAsset;
  final LiabilityEntity? savedLiability;
  final LiabilityEntity? previousLiability;
  final String? notice;

  bool get isAsset => savedAsset != null;

  @override
  State<HoldingSavedSummaryScreen> createState() =>
      _HoldingSavedSummaryScreenState();
}

class _HoldingSavedSummaryScreenState extends State<HoldingSavedSummaryScreen> {
  Stream<List<AssetEntity>>? _assets;
  Stream<List<LiabilityEntity>>? _liabilities;
  Stream<CurrencyConverter>? _converter;
  bool _busy = false;

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

  Future<void> _undo() async {
    if (_busy) return;
    setState(() => _busy = true);
    final AppContainer container = AppScope.of(context);
    try {
      if (widget.isAsset) {
        final AssetEntity saved = widget.savedAsset!;
        if (widget.previousAsset != null) {
          await container.assetRepository.save(widget.previousAsset!);
        } else {
          await container.assetRepository.delete(saved.id);
        }
      } else {
        final LiabilityEntity saved = widget.savedLiability!;
        if (widget.previousLiability != null) {
          await container.liabilityRepository.save(widget.previousLiability!);
        } else {
          await container.liabilityRepository.delete(saved.id);
        }
      }
      if (!mounted) return;
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              (widget.updated ? 'Update undone.' : 'Addition undone.').tr(
                context,
              ),
            ),
          ),
        );
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _addAnotherHolding() async {
    if (_busy) return;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final bool? asset = await showDialog<bool>(
      context: context,
      barrierColor: dark ? const Color(0xAA10231B) : const Color(0x7310231B),
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        final ColorScheme colors = theme.colorScheme;
        final Color boxBorder = canvasBoxBorderColor(colors);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: AlertDialog(
            backgroundColor: colors.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: boxBorder),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
            actionsAlignment: MainAxisAlignment.center,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Add holding'.tr(context).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.35,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'What would you like to add?'.tr(context),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.6,
                    height: 1.25,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 375,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _HoldingKindChoiceCard(
                    icon: Icons.trending_up,
                    title: 'An asset'.tr(context),
                    subtitle: 'Something you own'.tr(context),
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: 10),
                  _HoldingKindChoiceCard(
                    icon: Icons.trending_down,
                    title: 'A liability'.tr(context),
                    subtitle: 'Something you owe'.tr(context),
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onSurfaceVariant,
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  child: Text('Close'.tr(context)),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || asset == null) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HoldingCreateScreen(
            portfolioId: widget.portfolioId,
            asset: asset,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final AppContainer container = AppScope.of(context);
    final bool hideBalances = container.settingsRepository.current.hideBalances;
    final String baseCurrency =
        container.settingsRepository.current.baseCurrency;
    final AssetEntity? asset = widget.savedAsset;
    final LiabilityEntity? liability = widget.savedLiability;
    final String name = asset?.displayName ?? liability!.name;
    final String currency = asset?.currency ?? liability!.currency;
    final double rawValue = asset?.value ?? liability!.value;
    final bool priced =
        asset == null || !asset.type.isMarketLinked || asset.lastPrice != null;
    final String heading = switch ((widget.isAsset, widget.updated)) {
      (true, false) => 'Asset added.'.tr(context),
      (true, true) => 'Asset updated.'.tr(context),
      (false, false) => 'Liability added.'.tr(context),
      (false, true) => 'Liability updated.'.tr(context),
    };
    final String displayAmount = !priced
        ? 'Price pending'.tr(context)
        : hideBalances
        ? CurrencyUtil.masked(currency)
        : CurrencyUtil.format(rawValue, currency);
    final String? localizedNotice =
        widget.notice != null && widget.notice!.trim().isNotEmpty
        ? widget.notice!.tr(context)
        : null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 54,
        titleSpacing: 24,
        title: HoldingPortfolioLabel(
          portfolioId: widget.portfolioId,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 24),
            child: Center(
              child: Text(
                'OKANZO',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(24, 14, 24, 18),
          child: FilledButton(
            key: const ValueKey<String>('back-to-portfolio'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(child: Text('Back to portfolio'.tr(context))),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, size: 19),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: <Widget>[
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryContainer,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.check_rounded, size: 32, color: colors.primary),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            heading,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.7,
              height: 1.2,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: HoldingPortfolioLabel(
              portfolioId: widget.portfolioId,
              template: '{name} is now in {portfolio}.'
                  .tr(context)
                  .replaceAll('{name}', name),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: colors.onSurfaceVariant,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            displayAmount,
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 34,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.8,
              height: 1.35,
              color: colors.primary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          if (!priced || localizedNotice != null) ...<Widget>[
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 2, end: 9),
                      child: Icon(
                        Icons.cloud_off_outlined,
                        size: 17,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Saved without a latest price.'.tr(context),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            localizedNotice ??
                                'This asset is excluded until it has a price.'
                                    .tr(context),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Column(
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Portfolio'.tr(context),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 13,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Flexible(
                            fit: FlexFit.tight,
                            child: HoldingPortfolioLabel(
                              portfolioId: widget.portfolioId,
                              alignmentEnd: true,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: StreamBuilder<List<AssetEntity>>(
                      stream: _assets,
                      builder: (context, assetsSnap) =>
                          StreamBuilder<List<LiabilityEntity>>(
                            stream: _liabilities,
                            builder: (context, liabilitiesSnap) =>
                                StreamBuilder<CurrencyConverter>(
                                  stream: _converter,
                                  builder: (context, converterSnap) {
                                    final List<AssetEntity>? assets =
                                        assetsSnap.data;
                                    final List<LiabilityEntity>? liabilities =
                                        liabilitiesSnap.data;
                                    final CurrencyConverter rates =
                                        converterSnap.data ??
                                        const CurrencyConverter.empty();
                                    final NetWorthSummary? summary =
                                        assets != null && liabilities != null
                                        ? const NetWorthCalculator().calculate(
                                            assets: assets,
                                            liabilities: liabilities,
                                            baseCurrency: baseCurrency,
                                            converter: rates,
                                          )
                                        : null;
                                    final bool hasUnpriced =
                                        assets != null &&
                                        assets.any(
                                          (AssetEntity item) =>
                                              item.type.isMarketLinked &&
                                              item.lastPrice == null,
                                        );
                                    final String netWorthText = summary == null
                                        ? '—'
                                        : hideBalances
                                        ? CurrencyUtil.masked(baseCurrency)
                                        : CurrencyUtil.format(
                                            summary.netWorth,
                                            baseCurrency,
                                          );
                                    return Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            (hasUnpriced
                                                    ? 'Net worth (priced holdings)'
                                                    : 'Net worth')
                                                .tr(context),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  fontSize: 13,
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          netWorthText,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: colors.onSurface,
                                                fontFeatures: const <FontFeature>[
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            key: const ValueKey<String>('add-another-holding'),
            onPressed: _busy ? null : _addAnotherHolding,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 50),
              backgroundColor: colors.surfaceContainerLow,
              foregroundColor: colors.onSurface,
              side: BorderSide(color: colors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text('Add another holding'.tr(context)),
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const ValueKey<String>('undo-saved-holding'),
            onPressed: _busy ? null : _undo,
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
              minimumSize: const Size(double.infinity, 44),
            ),
            child: Text(
              (widget.updated ? 'Undo this update' : 'Undo this addition').tr(
                context,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldingKindChoiceCard extends StatelessWidget {
  const _HoldingKindChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: colors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
