import 'package:flutter/material.dart';

import '../../data/local/entity/portfolio_entity.dart';
import '../../di/app_container.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/donut_chart.dart';
import '../components/ui_components.dart';
import '../theme/colors.dart';
import '../theme/theme.dart';
import 'chart_format.dart';
import 'statistics_view_model.dart';

/// Donut-chart breakdown of the active portfolio.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  StatisticsViewModel? _viewModel;
  int? _overviewSelection;
  int? _assetsSelection;
  int? _liabilitiesSelection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final AppContainer container = AppScope.of(context);
    _viewModel = StatisticsViewModel(
      settingsRepository: container.settingsRepository,
      portfolioRepository: container.portfolioRepository,
      assetRepository: container.assetRepository,
      liabilityRepository: container.liabilityRepository,
      fxRepository: container.fxRepository,
    );
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  void _clearAllSelections() {
    setState(() {
      _overviewSelection = null;
      _assetsSelection = null;
      _liabilitiesSelection = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final StatisticsViewModel viewModel = _viewModel!;
    final FinanceColors finance = FinanceColors.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (BuildContext context, _) {
        final StatisticsState state = viewModel.state;
        return Scaffold(
          appBar: AppBar(
            title: _PortfolioMenuTitle(
              portfolios: state.portfolios,
              activeName: state.activePortfolio?.name ?? 'Statistics'.tr,
              onSelect: viewModel.selectPortfolio,
            ),
          ),
          body: !state.hasAnything
              ? Center(
                  child: EmptyState(
                    icon: Icons.pie_chart,
                    title: 'Nothing to chart yet'.tr,
                    subtitle:
                        'Add assets or liabilities to this portfolio to '
                            'see its breakdown.'
                        .tr,
                  ),
                )
              : GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _clearAllSelections,
                  child: ListView(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: 24,
                      left: 16,
                      right: 16,
                    ),
                    children: <Widget>[
                      _ChartCard(
                        title: 'Overview'.tr,
                        subtitle: 'Assets vs. liabilities'.tr,
                        slices: <PieSlice>[
                          if (state.totalAssets > 0)
                            PieSlice(
                              'Assets'.tr,
                              state.totalAssets,
                              finance.positive,
                            ),
                          if (state.totalLiabilities > 0)
                            PieSlice(
                              'Liabilities'.tr,
                              state.totalLiabilities,
                              finance.negative,
                            ),
                        ],
                        defaultCenterLabel: 'Net worth'.tr,
                        defaultCenterValue: state.netWorth,
                        baseCurrency: state.baseCurrency,
                        hideBalances: state.hideBalances,
                        selectedIndex: _overviewSelection,
                        onSelectedChange: (int? index) =>
                            setState(() => _overviewSelection = index),
                      ),
                      if (state.hasAssets) ...<Widget>[
                        const SizedBox(height: 16),
                        _ChartCard(
                          title: 'Assets'.tr,
                          subtitle: 'By type'.tr,
                          slices: <PieSlice>[
                            for (int i = 0; i < state.assetsByType.length; i++)
                              PieSlice(
                                state.assetsByType[i].label.tr,
                                state.assetsByType[i].amount,
                                chartColorAt(i),
                              ),
                          ],
                          defaultCenterLabel: 'Assets'.tr,
                          defaultCenterValue: state.totalAssets,
                          baseCurrency: state.baseCurrency,
                          hideBalances: state.hideBalances,
                          selectedIndex: _assetsSelection,
                          onSelectedChange: (int? index) =>
                              setState(() => _assetsSelection = index),
                        ),
                      ],
                      if (state.hasLiabilities) ...<Widget>[
                        const SizedBox(height: 16),
                        _ChartCard(
                          title: 'Liabilities'.tr,
                          subtitle: 'By type'.tr,
                          slices: <PieSlice>[
                            for (
                              int i = 0;
                              i < state.liabilitiesByType.length;
                              i++
                            )
                              PieSlice(
                                state.liabilitiesByType[i].label.tr,
                                state.liabilitiesByType[i].amount,
                                chartColorAt(i),
                              ),
                          ],
                          defaultCenterLabel: 'Liabilities'.tr,
                          defaultCenterValue: state.totalLiabilities,
                          baseCurrency: state.baseCurrency,
                          hideBalances: state.hideBalances,
                          selectedIndex: _liabilitiesSelection,
                          onSelectedChange: (int? index) =>
                              setState(() => _liabilitiesSelection = index),
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _PortfolioMenuTitle extends StatelessWidget {
  const _PortfolioMenuTitle({
    required this.portfolios,
    required this.activeName,
    required this.onSelect,
  });

  final List<PortfolioEntity> portfolios;
  final String activeName;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final Widget label = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            activeName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const Icon(Icons.arrow_drop_down),
      ],
    );
    if (portfolios.isEmpty) return label;
    return PopupMenuButton<int>(
      tooltip: 'Switch portfolio'.tr,
      position: PopupMenuPosition.under,
      onSelected: onSelect,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
        for (final PortfolioEntity portfolio in portfolios)
          PopupMenuItem<int>(
            value: portfolio.id,
            child: Text(
              portfolio.name +
                  (portfolio.isDefault ? '  •  ${'Default'.tr}' : ''),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: label,
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.slices,
    required this.defaultCenterLabel,
    required this.defaultCenterValue,
    required this.baseCurrency,
    required this.hideBalances,
    required this.selectedIndex,
    required this.onSelectedChange,
  });

  final String title;
  final String subtitle;
  final List<PieSlice> slices;
  final String defaultCenterLabel;
  final double defaultCenterValue;
  final String baseCurrency;
  final bool hideBalances;
  final int? selectedIndex;
  final ValueChanged<int?> onSelectedChange;

  String _money(double amount) => hideBalances
      ? CurrencyUtil.masked(baseCurrency)
      : CurrencyUtil.format(amount, baseCurrency);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Guard against a stale index if the underlying data shrinks.
    final int? selected =
        (selectedIndex != null &&
            selectedIndex! >= 0 &&
            selectedIndex! < slices.length)
        ? selectedIndex
        : null;
    final PieSlice? selectedSlice = selected == null ? null : slices[selected];
    final double total = slices.fold<double>(
      0,
      (double sum, PieSlice slice) => sum + slice.value,
    );

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: DonutChart(
                slices: slices,
                selectedIndex: selected,
                onSelect: onSelectedChange,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        selectedSlice?.label ?? defaultCenterLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _money(selectedSlice?.value ?? defaultCenterValue),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (selectedSlice != null)
                        Text(
                          percentageLabel(selectedSlice.value, total),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (int index = 0; index < slices.length; index++)
              _LegendRow(
                color: slices[index].color,
                label: slices[index].label,
                valueText: _money(slices[index].value),
                highlighted: selected == index,
                onTap: () => onSelectedChange(selected == index ? null : index),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.valueText,
    required this.highlighted,
    required this.onTap,
  });

  final Color color;
  final String label;
  final String valueText;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FontWeight weight = highlighted ? FontWeight.w600 : FontWeight.normal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(shapeSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: <Widget>[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: weight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Text(
              valueText,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: weight,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
