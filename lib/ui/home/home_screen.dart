import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/local/entity/portfolio_entity.dart';
import '../../di/app_container.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/drag_reorder_column.dart';
import '../components/form_components.dart';
import '../components/type_icons.dart';
import '../components/ui_components.dart';
import '../statistics/chart_format.dart';
import '../theme/app_style.dart';
import '../theme/colors.dart';
import '../theme/motion.dart';
import '../theme/theme.dart';
import 'category_groups.dart';
import 'add_holding_button.dart';
import 'holding_details.dart';
import 'holding_group_list.dart';
import 'home_view_model.dart';
import 'net_worth_card.dart';

/// The main dashboard: net worth, asset and liability categories.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onOpenAssetEditor,
    required this.onOpenLiabilityEditor,
    required this.onManagePortfolios,
    required this.onOpenSettings,
    super.key,
  });

  final void Function(int portfolioId, int assetId) onOpenAssetEditor;
  final void Function(int portfolioId, int liabilityId) onOpenLiabilityEditor;
  final VoidCallback onManagePortfolios;
  final VoidCallback onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeViewModel? _viewModel;
  bool _showAssets = true;
  bool _filterOpen = false;
  String _filterQuery = '';
  final TextEditingController _filterController = TextEditingController();
  final FocusNode _filterFocus = FocusNode();
  final Map<String, HoldingSort> _sorts = <String, HoldingSort>{};
  final ValueNotifier<Set<String>> _expanded = ValueNotifier<Set<String>>(
    <String>{},
  );
  final ValueNotifier<Set<String>> _filterCollapsed =
      ValueNotifier<Set<String>>(<String>{});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final AppContainer container = AppScope.of(context);
    _viewModel = HomeViewModel(
      settingsRepository: container.settingsRepository,
      portfolioRepository: container.portfolioRepository,
      assetRepository: container.assetRepository,
      liabilityRepository: container.liabilityRepository,
      fxRepository: container.fxRepository,
    )..addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() {
    final String? message = _viewModel?.message;
    if (message != null && mounted) {
      _viewModel!.consumeMessage();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.tr(context))));
    }
  }

  void _toggleExpanded(String key) {
    if (_filterQuery.trim().isNotEmpty) {
      final Set<String> next = Set<String>.of(_filterCollapsed.value);
      if (!next.remove(key)) next.add(key);
      _filterCollapsed.value = next;
      return;
    }
    final Set<String> next = Set<String>.of(_expanded.value);
    if (!next.remove(key)) next.add(key);
    _expanded.value = next;
  }

  void _toggleExpandAll(List<String> keys) {
    if (keys.isEmpty) return;
    if (_filterQuery.trim().isNotEmpty) {
      final Set<String> next = Set<String>.of(_filterCollapsed.value);
      final bool allExpanded = keys.every((String k) => !next.contains(k));
      if (allExpanded) {
        next.addAll(keys);
      } else {
        next.removeAll(keys);
      }
      _filterCollapsed.value = next;
      return;
    }
    final Set<String> next = Set<String>.of(_expanded.value);
    final bool allExpanded = keys.every(next.contains);
    if (allExpanded) {
      next.removeAll(keys);
    } else {
      next.addAll(keys);
    }
    _expanded.value = next;
  }

  void _toggleFilter() {
    final bool next = !_filterOpen;
    setState(() {
      _filterOpen = next;
      if (!next) {
        _filterController.clear();
        _filterQuery = '';
        _filterCollapsed.value = <String>{};
      }
    });
    if (next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _filterOpen) _filterFocus.requestFocus();
      });
    } else {
      _filterFocus.unfocus();
    }
  }

  void _clearFilter() {
    _filterController.clear();
    _filterCollapsed.value = <String>{};
    setState(() => _filterQuery = '');
    if (_filterOpen) _filterFocus.requestFocus();
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onViewModelChanged);
    _viewModel?.dispose();
    _filterController.dispose();
    _filterFocus.dispose();
    _filterCollapsed.dispose();
    _expanded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HomeViewModel viewModel = _viewModel!;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (BuildContext context, _) {
        final HomeState state = viewModel.state;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 56,
            titleSpacing: 24,
            title: _PortfolioTitle(
              state: state,
              onSelect: viewModel.selectPortfolio,
              onManagePortfolios: widget.onManagePortfolios,
            ),
            actions: <Widget>[
              HideBalancesButton(
                hideBalances: state.hideBalances,
                onPressed: viewModel.toggleHideBalances,
              ),
              IconButton(
                onPressed: widget.onOpenSettings,
                tooltip: 'Settings'.tr(context),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          floatingActionButton: state.activePortfolio == null
              ? null
              : AddHoldingButton(
                  onAsset: () {
                    setState(() => _showAssets = true);
                    widget.onOpenAssetEditor(state.activePortfolio!.id, 0);
                  },
                  onLiability: () {
                    setState(() => _showAssets = false);
                    widget.onOpenLiabilityEditor(state.activePortfolio!.id, 0);
                  },
                ),
          body: state.loading
              ? const Center(child: CircularProgressIndicator())
              : _HomeContent(
                  state: state,
                  expanded: _expanded,
                  filterCollapsed: _filterCollapsed,
                  onToggleExpanded: _toggleExpanded,
                  onToggleExpandAll: _toggleExpandAll,
                  filterOpen: _filterOpen,
                  filterQuery: _filterQuery,
                  filterController: _filterController,
                  filterFocus: _filterFocus,
                  onToggleFilter: _toggleFilter,
                  onFilterChanged: (String value) {
                    _filterCollapsed.value = <String>{};
                    setState(() => _filterQuery = value);
                  },
                  onClearFilter: _clearFilter,
                  onOpenAsset: _openAsset,
                  onOpenLiability: _openLiability,
                  sorts: _sorts,
                  onSort: (String key, HoldingSort sort) =>
                      setState(() => _sorts[key] = sort),
                  viewModel: viewModel,
                  showAssets: _showAssets,
                  onSectionSelected: (bool value) =>
                      setState(() => _showAssets = value),
                ),
        );
      },
    );
  }

  Future<void> _openAsset(AssetLine line) async {
    final AssetEntity asset = line.asset;
    final HomeState state = _viewModel!.state;
    final HoldingDetailsAction? action = await showHoldingDetails(
      context,
      asset: asset,
      portfolioName: state.activePortfolio?.name,
      hideBalances: state.hideBalances,
      baseCurrency: state.summary.baseCurrency,
      convertedValue: line.convertedValue,
      isConversionApproximate: line.isConversionApproximate,
      portfolioSectionTotal: state.summary.totalAssets,
      isSectionTotalApproximate: state.hasApproximateAssetConversions,
    );
    if (!mounted) return;
    if (action == HoldingDetailsAction.edit) {
      widget.onOpenAssetEditor(asset.portfolioId, asset.id);
    } else if (action == HoldingDetailsAction.delete) {
      try {
        await AppScope.of(context).assetRepository.delete(asset.id);
      } on Object {
        if (mounted) _showDeleteError();
      }
    }
  }

  Future<void> _openLiability(LiabilityLine line) async {
    final LiabilityEntity liability = line.liability;
    final HomeState state = _viewModel!.state;
    final HoldingDetailsAction? action = await showHoldingDetails(
      context,
      liability: liability,
      portfolioName: state.activePortfolio?.name,
      hideBalances: state.hideBalances,
      baseCurrency: state.summary.baseCurrency,
      convertedValue: line.convertedValue,
      isConversionApproximate: line.isConversionApproximate,
      portfolioSectionTotal: state.summary.totalLiabilities,
      isSectionTotalApproximate: state.hasApproximateLiabilityConversions,
    );
    if (!mounted) return;
    if (action == HoldingDetailsAction.edit) {
      widget.onOpenLiabilityEditor(liability.portfolioId, liability.id);
    } else if (action == HoldingDetailsAction.delete) {
      try {
        await AppScope.of(context).liabilityRepository.delete(liability.id);
      } on Object {
        if (mounted) _showDeleteError();
      }
    }
  }

  void _showDeleteError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not delete holding.'.tr(context))),
    );
  }
}

class _PortfolioTitle extends StatelessWidget {
  const _PortfolioTitle({
    required this.state,
    required this.onSelect,
    required this.onManagePortfolios,
  });

  final HomeState state;
  final ValueChanged<int> onSelect;
  final VoidCallback onManagePortfolios;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Widget label = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.folder_outlined,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                state.activePortfolio?.name ?? 'Okanzo',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
    if (state.portfolios.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: label,
      );
    }
    return PopupMenuButton<Object>(
      tooltip: 'Switch portfolio'.tr(context),
      position: PopupMenuPosition.under,
      borderRadius: BorderRadius.circular(999),
      onSelected: (Object value) {
        if (value is int) {
          onSelect(value);
        } else {
          onManagePortfolios();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Object>>[
        for (final PortfolioEntity portfolio in state.portfolios)
          PopupMenuItem<Object>(
            value: portfolio.id,
            child: Text(
              portfolio.name +
                  (portfolio.isDefault ? '  •  ${'Default'.tr(context)}' : ''),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: 'manage',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.tune),
            title: Text('Manage portfolios'.tr(context)),
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

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.state,
    required this.expanded,
    required this.filterCollapsed,
    required this.onToggleExpanded,
    required this.onToggleExpandAll,
    required this.filterOpen,
    required this.filterQuery,
    required this.filterController,
    required this.filterFocus,
    required this.onToggleFilter,
    required this.onFilterChanged,
    required this.onClearFilter,
    required this.onOpenAsset,
    required this.onOpenLiability,
    required this.viewModel,
    required this.showAssets,
    required this.onSectionSelected,
    required this.sorts,
    required this.onSort,
  });

  final HomeState state;
  final ValueNotifier<Set<String>> expanded;
  final ValueNotifier<Set<String>> filterCollapsed;
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<List<String>> onToggleExpandAll;
  final bool filterOpen;
  final String filterQuery;
  final TextEditingController filterController;
  final FocusNode filterFocus;
  final VoidCallback onToggleFilter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onClearFilter;
  final ValueChanged<AssetLine> onOpenAsset;
  final ValueChanged<LiabilityLine> onOpenLiability;
  final HomeViewModel viewModel;
  final bool showAssets;
  final ValueChanged<bool> onSectionSelected;
  final Map<String, HoldingSort> sorts;
  final void Function(String, HoldingSort) onSort;

  static bool _matchesAsset(AssetLine line, String needle) {
    final AssetEntity asset = line.asset;
    return asset.displayName.toLowerCase().contains(needle) ||
        asset.name.toLowerCase().contains(needle) ||
        (asset.symbol?.toLowerCase().contains(needle) ?? false) ||
        asset.currency.toLowerCase().contains(needle) ||
        (asset.displayedMetal?.label.toLowerCase().contains(needle) ?? false);
  }

  static bool _matchesLiability(LiabilityLine line, String needle) {
    final LiabilityEntity liability = line.liability;
    return liability.name.toLowerCase().contains(needle) ||
        liability.currency.toLowerCase().contains(needle);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final FinanceColors finance = FinanceColors.of(context);
    final bool colorful = AppStyle.of(context).colorfulCategories;
    final String needle = filterQuery.trim().toLowerCase();

    final List<AssetCategoryGroup> visibleAssetGroups = needle.isEmpty
        ? state.assetGroups
        : <AssetCategoryGroup>[
            for (final AssetCategoryGroup group in state.assetGroups)
              if (group.items
                      .where((AssetLine l) => _matchesAsset(l, needle))
                      .toList()
                  case final List<AssetLine> matched when matched.isNotEmpty)
                AssetCategoryGroup(
                  type: group.type,
                  total: sumAssetLines(
                    matched.where((AssetLine l) => l.asset.isPriced),
                  ),
                  baseCurrency: group.baseCurrency,
                  items: matched,
                ),
          ];

    final List<LiabilityCategoryGroup> visibleLiabilityGroups = needle.isEmpty
        ? state.liabilityGroups
        : <LiabilityCategoryGroup>[
            for (final LiabilityCategoryGroup group in state.liabilityGroups)
              if (group.items
                      .where((LiabilityLine l) => _matchesLiability(l, needle))
                      .toList()
                  case final List<LiabilityLine> matched
                  when matched.isNotEmpty)
                LiabilityCategoryGroup(
                  type: group.type,
                  total: sumLiabilityLines(matched),
                  baseCurrency: group.baseCurrency,
                  items: matched,
                ),
          ];

    final int holdingCount = showAssets
        ? visibleAssetGroups.fold(
            0,
            (int total, AssetCategoryGroup group) => total + group.items.length,
          )
        : visibleLiabilityGroups.fold(
            0,
            (int total, LiabilityCategoryGroup group) =>
                total + group.items.length,
          );
    final bool sectionHasHoldings = showAssets
        ? state.hasAnyAssets
        : state.hasAnyLiabilities;
    final List<String> visibleKeys = showAssets
        ? <String>[
            for (final AssetCategoryGroup group in visibleAssetGroups)
              'asset-${group.type.storageName}',
          ]
        : <String>[
            for (final LiabilityCategoryGroup group in visibleLiabilityGroups)
              'liability-${group.type.storageName}',
          ];

    Widget buildAssetGroupWidget(AssetCategoryGroup group, bool dragging) {
      final String key = 'asset-${group.type.storageName}';
      final String sortKey = '${state.activePortfolio!.id}-$key';
      final metal = group.items.first.asset.displayedMetal;
      final bool singleMetal =
          metal != null &&
          group.items.every((line) => line.asset.displayedMetal == metal);
      final bool allPending = group.items.every((line) => !line.asset.isPriced);
      final String shareText = !allPending && state.summary.totalAssets > 0
          ? oneDecimalPercentageLabel(group.total, state.summary.totalAssets)
          : '';
      return ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[expanded, filterCollapsed]),
        builder: (BuildContext context, _) => _CategoryCardShell(
          icon: singleMetal ? metalIcon(metal) : assetTypeIcon(group.type),
          accent: colorful ? categoryColorAt(group.type.index) : null,
          title: group.type.displayName.tr(context),
          count: group.items.length,
          shareText: shareText,
          totalText: allPending
              ? 'Price pending'.tr(context)
              : state.hideBalances
              ? CurrencyUtil.maskShort
              : CurrencyUtil.format(group.total, group.baseCurrency),
          isExpanded: needle.isNotEmpty
              ? !filterCollapsed.value.contains(key)
              : expanded.value.contains(key),
          isDragging: dragging,
          showDivider: group.type != visibleAssetGroups.first.type,
          onToggle: () => onToggleExpanded(key),
          expandedContentBuilder: () => HoldingGroupList<AssetLine>(
            items: group.items,
            name: (line) => line.asset.displayName,
            value: (line) => line.convertedValue,
            priced: (line) => line.asset.isPriced,
            sort: sorts[sortKey] ?? HoldingSort.custom,
            onSort: (sort) => onSort(sortKey, sort),
            canArrange: needle.isEmpty,
            onReordered: (List<AssetLine> items) =>
                viewModel.onAssetItemsReordered(
                  items.map((AssetLine l) => l.asset.id).toList(),
                ),
            itemBuilder: (AssetLine line) => _HoldingItemRow(
              icon: line.asset.displayedMetal == null
                  ? null
                  : metalIcon(line.asset.displayedMetal!),
              title: line.asset.displayName,
              subtitle: assetSubtitle(
                line.asset,
                group.baseCurrency,
                unitsLabel: 'units'.tr(context),
                hideBalances: state.hideBalances,
                localize: (label) => label.tr(context),
              ),
              amount: !line.asset.isPriced
                  ? 'Price pending'.tr(context)
                  : state.hideBalances
                  ? CurrencyUtil.maskShort
                  : CurrencyUtil.format(
                      line.convertedValue,
                      group.baseCurrency,
                    ),
              onOpen: () => onOpenAsset(line),
            ),
          ),
        ),
      );
    }

    Widget buildLiabilityGroupWidget(
      LiabilityCategoryGroup group,
      bool dragging,
    ) {
      final String key = 'liability-${group.type.storageName}';
      final String sortKey = '${state.activePortfolio!.id}-$key';
      final String shareText = state.summary.totalLiabilities > 0
          ? oneDecimalPercentageLabel(
              group.total,
              state.summary.totalLiabilities,
            )
          : '';
      return ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[expanded, filterCollapsed]),
        builder: (BuildContext context, _) => _CategoryCardShell(
          icon: liabilityTypeIcon(group.type),
          accent: colorful ? categoryColorAt(group.type.index + 5) : null,
          avatarAccent: colorful ? null : finance.negative,
          title: group.type.displayName.tr(context),
          count: group.items.length,
          shareText: shareText,
          totalText: state.hideBalances
              ? CurrencyUtil.maskShort
              : CurrencyUtil.format(group.total, group.baseCurrency),
          isExpanded: needle.isNotEmpty
              ? !filterCollapsed.value.contains(key)
              : expanded.value.contains(key),
          isDragging: dragging,
          showDivider: group.type != visibleLiabilityGroups.first.type,
          onToggle: () => onToggleExpanded(key),
          expandedContentBuilder: () => HoldingGroupList<LiabilityLine>(
            items: group.items,
            name: (line) => line.liability.name,
            value: (line) => line.convertedValue,
            priced: (_) => true,
            sort: sorts[sortKey] ?? HoldingSort.custom,
            onSort: (sort) => onSort(sortKey, sort),
            canArrange: needle.isEmpty,
            onReordered: (List<LiabilityLine> items) =>
                viewModel.onLiabilityItemsReordered(
                  items.map((LiabilityLine l) => l.liability.id).toList(),
                ),
            itemBuilder: (LiabilityLine line) => _HoldingItemRow(
              title: line.liability.name,
              subtitle: currencyNote(
                line.liability.currency,
                group.baseCurrency,
              ),
              amount: state.hideBalances
                  ? CurrencyUtil.maskShort
                  : CurrencyUtil.format(
                      line.convertedValue,
                      group.baseCurrency,
                    ),
              onOpen: () => onOpenLiability(line),
            ),
          ),
        ),
      );
    }

    final String refreshLabel = 'Refresh prices'.tr(context);
    return Semantics(
      customSemanticsActions: state.isRefreshing
          ? null
          : <CustomSemanticsAction, VoidCallback>{
              CustomSemanticsAction(label: refreshLabel): () {
                viewModel.refresh();
              },
            },
      child: _HomeBounceRefresh(
        key: const ValueKey<String>('home-refresh-indicator'),
        isRefreshing: state.isRefreshing,
        onRefresh: viewModel.refresh,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            MediaQuery.textScalerOf(context).scale(16) + 80,
          ),
          children: <Widget>[
            NetWorthCard(
              summary: state.summary,
              hideBalances: state.hideBalances,
              simpleNetWorth: state.simpleNetWorth,
              configuredBaseCurrency: state.baseCurrency,
              showingUsd: state.displayInUsd,
              onToggleCurrency: viewModel.toggleDisplayCurrency,
            ),
            const SizedBox(height: 24),
            _HoldingSectionTabs(
              showAssets: showAssets,
              onSelected: onSectionSelected,
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    (showAssets ? 'What you own' : 'What you owe')
                        .tr(context)
                        .toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  holdingCount == 1
                      ? '1 item'.tr(context)
                      : '{count} items'
                            .tr(context)
                            .replaceAll('{count}', '$holdingCount'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (sectionHasHoldings) ...<Widget>[
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey<String>('home-filter-toggle'),
                    tooltip: 'Filter holdings'.tr(context),
                    visualDensity: VisualDensity.compact,
                    onPressed: onToggleFilter,
                    icon: Icon(
                      Icons.search,
                      size: 19,
                      color: filterOpen
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                  ListenableBuilder(
                    listenable: Listenable.merge(<Listenable>[
                      expanded,
                      filterCollapsed,
                    ]),
                    builder: (BuildContext context, _) {
                      final bool allExpanded =
                          visibleKeys.isNotEmpty &&
                          (needle.isNotEmpty
                              ? visibleKeys.every(
                                  (String k) =>
                                      !filterCollapsed.value.contains(k),
                                )
                              : visibleKeys.every(expanded.value.contains));
                      return IconButton(
                        key: const ValueKey<String>('home-expand-all-toggle'),
                        tooltip: (allExpanded ? 'Collapse all' : 'Expand all')
                            .tr(context),
                        visualDensity: VisualDensity.compact,
                        onPressed: visibleKeys.isEmpty
                            ? null
                            : () => onToggleExpandAll(visibleKeys),
                        icon: Icon(
                          allExpanded ? Icons.unfold_less : Icons.unfold_more,
                          size: 19,
                          color: colors.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
            DisclosureSize(
              child: filterOpen && sectionHasHoldings
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 10),
                      child: TextField(
                        key: const ValueKey<String>('home-filter-input'),
                        controller: filterController,
                        focusNode: filterFocus,
                        onChanged: onFilterChanged,
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: colors.surfaceContainerLow,
                          hintText: 'Filter by name, ticker, or currency…'.tr(
                            context,
                          ),
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                          suffixIcon: filterQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear filter'.tr(context),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: onClearFilter,
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13),
                            borderSide: BorderSide(
                              color: canvasBoxBorderColor(colors),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13),
                            borderSide: BorderSide(
                              color: canvasBoxBorderColor(colors),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13),
                            borderSide: BorderSide(
                              color: colors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(height: 12),
            ),
            if (showAssets && !state.hasAnyAssets)
              EmptyState(
                icon: Icons.account_balance_wallet,
                title: 'No assets yet'.tr(context),
                subtitle:
                    'Add stocks, cash, property and more to track their value.'
                        .tr(context),
              ),
            if (showAssets &&
                state.hasAnyAssets &&
                needle.isNotEmpty &&
                visibleAssetGroups.isEmpty)
              EmptyState(
                icon: Icons.search_off,
                title: 'No matching holdings'.tr(context),
                subtitle: 'Try another name, ticker, or currency code.'.tr(
                  context,
                ),
              ),
            if (showAssets && visibleAssetGroups.isNotEmpty)
              _CategoryPanel(
                child: needle.isNotEmpty
                    ? Column(
                        children: <Widget>[
                          for (final AssetCategoryGroup group
                              in visibleAssetGroups)
                            buildAssetGroupWidget(group, false),
                        ],
                      )
                    : DragReorderColumn<AssetCategoryGroup>(
                        items: visibleAssetGroups,
                        keyOf: (AssetCategoryGroup group) => group.type,
                        onReordered: (List<AssetCategoryGroup> groups) =>
                            viewModel.onAssetCategoriesReordered(
                              groups
                                  .map((AssetCategoryGroup g) => g.type)
                                  .toList(),
                            ),
                        itemBuilder: (
                          BuildContext context,
                          AssetCategoryGroup group,
                          bool dragging,
                        ) => buildAssetGroupWidget(group, dragging),
                      ),
              ),
            if (!showAssets && !state.hasAnyLiabilities)
              EmptyState(
                icon: Icons.inbox,
                title: 'No liabilities'.tr(context),
                subtitle: 'Track loans, credit cards and pending payments here.'
                    .tr(context),
              ),
            if (!showAssets &&
                state.hasAnyLiabilities &&
                needle.isNotEmpty &&
                visibleLiabilityGroups.isEmpty)
              EmptyState(
                icon: Icons.search_off,
                title: 'No matching holdings'.tr(context),
                subtitle: 'Try another name, ticker, or currency code.'.tr(
                  context,
                ),
              ),
            if (!showAssets && visibleLiabilityGroups.isNotEmpty)
              _CategoryPanel(
                child: needle.isNotEmpty
                    ? Column(
                        children: <Widget>[
                          for (final LiabilityCategoryGroup group
                              in visibleLiabilityGroups)
                            buildLiabilityGroupWidget(group, false),
                        ],
                      )
                    : DragReorderColumn<LiabilityCategoryGroup>(
                        items: visibleLiabilityGroups,
                        keyOf: (LiabilityCategoryGroup group) => group.type,
                        onReordered: (List<LiabilityCategoryGroup> groups) =>
                            viewModel.onLiabilityCategoriesReordered(
                              groups
                                  .map((LiabilityCategoryGroup g) => g.type)
                                  .toList(),
                            ),
                        itemBuilder: (
                          BuildContext context,
                          LiabilityCategoryGroup group,
                          bool dragging,
                        ) => buildLiabilityGroupWidget(group, dragging),
                      ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _HomeBounceRefresh extends StatefulWidget {
  const _HomeBounceRefresh({
    required this.isRefreshing,
    required this.onRefresh,
    required this.child,
    super.key,
  });

  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<_HomeBounceRefresh> createState() => _HomeBounceRefreshState();
}

class _HomeBounceRefreshState extends State<_HomeBounceRefresh>
    with TickerProviderStateMixin {
  static const double _triggerPullPx = 48.0;

  late final AnimationController _bannerController;
  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnim;
  bool _pullLatched = false;
  bool _refreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.isRefreshing ? 1.0 : 0.0,
    );
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _bounceAnim = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 0.0,
          end: 18.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 18.0,
          end: -3.5,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: -3.5,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 30,
      ),
    ]).animate(_bounceController);
    _bounceController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed &&
          !widget.isRefreshing &&
          !_refreshInFlight &&
          mounted) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _bannerController.value = 0.0;
        } else {
          _bannerController.reverse();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _bounceController.stop();
      _bounceController.value = 0.0;
      _bannerController.stop();
      _bannerController.value = (widget.isRefreshing || _refreshInFlight)
          ? 1.0
          : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant _HomeBounceRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isRefreshing && widget.isRefreshing) {
      _startRefreshVisuals();
    } else if (oldWidget.isRefreshing &&
        !widget.isRefreshing &&
        !_refreshInFlight) {
      _finishRefreshVisuals();
    }
  }

  void _startRefreshVisuals() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _bannerController.value = 1.0;
      _bounceController.value = 0.0;
      return;
    }
    _bannerController.forward();
    if (!_bounceController.isAnimating) {
      _bounceController.forward(from: 0.0);
    }
  }

  void _finishRefreshVisuals() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _bannerController.value = 0.0;
      _bounceController.value = 0.0;
      return;
    }
    if (!_bounceController.isAnimating) {
      _bannerController.reverse();
    }
  }

  Future<void> _triggerRefresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    _startRefreshVisuals();
    try {
      await widget.onRefresh();
    } finally {
      _refreshInFlight = false;
      if (mounted && !widget.isRefreshing) {
        _finishRefreshVisuals();
      }
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final double pixels = notification.metrics.pixels;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        pixels < -_triggerPullPx &&
        !_pullLatched &&
        !widget.isRefreshing &&
        !_refreshInFlight) {
      _pullLatched = true;
      unawaited(_triggerRefresh());
    } else if (pixels >= -4.0 && !widget.isRefreshing && !_refreshInFlight) {
      _pullLatched = false;
    }
    return false;
  }

  @override
  void dispose() {
    _bannerController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool disableAnimations = MediaQuery.disableAnimationsOf(context);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _bannerController,
          _bounceController,
        ]),
        builder: (BuildContext context, Widget? child) {
          final double progress = Curves.easeOutCubic.transform(
            _bannerController.value,
          );
          final double bounceDy = disableAnimations ? 0.0 : _bounceAnim.value;
          final bool showBanner =
              widget.isRefreshing || _bannerController.value > 0.001;

          return ClipRect(
            child: Transform.translate(
              offset: Offset(0, bounceDy),
              child: Column(
                children: <Widget>[
                  if (showBanner)
                    Align(
                      alignment: Alignment.topCenter,
                      heightFactor: progress.clamp(0.0, 1.0),
                      child: Opacity(
                        opacity: progress.clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: DecoratedBox(
                            key: const ValueKey<String>(
                              'home-refreshing-banner',
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: canvasBoxBorderColor(colors),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Text(
                                    'Refreshing Quotes'.tr(context),
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: colors.onSurface,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: child!),
                ],
              ),
            ),
          );
        },
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: widget.child,
        ),
      ),
    );
  }
}

class _HoldingSectionTabs extends StatefulWidget {
  const _HoldingSectionTabs({
    required this.showAssets,
    required this.onSelected,
  });

  final bool showAssets;
  final ValueChanged<bool> onSelected;

  @override
  State<_HoldingSectionTabs> createState() => _HoldingSectionTabsState();
}

class _HoldingSectionTabsState extends State<_HoldingSectionTabs> {
  bool _dragging = false;
  double _dragDeltaX = 0;

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _dragDeltaX = 0;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragDeltaX += details.delta.dx;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final double dir = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;
    final double signedDx = _dragDeltaX * dir;
    final double signedVx = (details.primaryVelocity ?? 0.0) * dir;
    setState(() {
      _dragging = false;
      _dragDeltaX = 0;
    });
    if (widget.showAssets && (signedDx > 18.0 || signedVx > 180.0)) {
      widget.onSelected(false);
    } else if (!widget.showAssets && (signedDx < -18.0 || signedVx < -180.0)) {
      widget.onSelected(true);
    }
  }

  void _handleDragCancel() {
    setState(() {
      _dragging = false;
      _dragDeltaX = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Duration duration = _dragging
        ? Duration.zero
        : interactionDuration(context);
    final double dir = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;

    return GestureDetector(
      key: const ValueKey<String>('home-section-toggle'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: _handleDragCancel,
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double halfWidth = constraints.maxWidth / 2;
              final double baseT = widget.showAssets ? 0.0 : 1.0;
              final double effectiveT =
                  _dragging &&
                      halfWidth > 0 &&
                      !MediaQuery.disableAnimationsOf(context)
                  ? (baseT + (dir * _dragDeltaX / halfWidth)).clamp(0.0, 1.0)
                  : baseT;

              return Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: AnimatedAlign(
                      alignment: AlignmentDirectional.lerp(
                        AlignmentDirectional.centerStart,
                        AlignmentDirectional.centerEnd,
                        effectiveT,
                      )!,
                      duration: duration,
                      curve: interactionCurve,
                      child: FractionallySizedBox(
                        widthFactor: 0.5,
                        heightFactor: 1.0,
                        child: DecoratedBox(
                          key: const ValueKey<String>('home-section-thumb'),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      for (final bool assets in <bool>[true, false])
                        Expanded(
                          child: Material(
                            type: MaterialType.transparency,
                            child: Semantics(
                              selected: widget.showAssets == assets,
                              button: true,
                              child: InkWell(
                                key: ValueKey<String>(
                                  assets
                                      ? 'home-assets-tab'
                                      : 'home-liabilities-tab',
                                ),
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => widget.onSelected(assets),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 48,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    child: Center(
                                      child: AnimatedDefaultTextStyle(
                                        duration: interactionDuration(context),
                                        curve: interactionCurve,
                                        style:
                                            (theme.textTheme.bodySmall ??
                                                    const TextStyle())
                                                .copyWith(
                                                  color:
                                                      widget.showAssets ==
                                                          assets
                                                      ? colors.onSurface
                                                      : colors.onSurfaceVariant,
                                                  fontWeight:
                                                      widget.showAssets ==
                                                          assets
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                ),
                                        child: Text(
                                          (assets ? 'Assets' : 'Liabilities')
                                              .tr(context),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey<String>('home-category-panel'),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    ),
  );
}

class _CategoryCardShell extends StatelessWidget {
  const _CategoryCardShell({
    required this.icon,
    required this.title,
    required this.count,
    required this.totalText,
    required this.isExpanded,
    required this.isDragging,
    required this.onToggle,
    required this.expandedContentBuilder,
    required this.showDivider,
    this.shareText,
    this.accent,
    this.avatarAccent,
  });

  final IconData icon;
  final String title;
  final int count;
  final String? shareText;
  final String totalText;
  final bool isExpanded;
  final bool isDragging;
  final VoidCallback onToggle;
  final Widget Function() expandedContentBuilder;
  final bool showDivider;

  /// Per-category accent colour used by the Midnight theme. Null keeps the
  /// neutral Material look.
  final Color? accent;

  /// Optional avatar-only tint (e.g. warm terracotta on liability categories).
  final Color? avatarAccent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? accent = this.accent;
    final String countLabel = count == 1
        ? '1 item'.tr(context)
        : '{count} items'.tr(context).replaceAll('{count}', '$count');
    final String subtitleText = (shareText == null || shareText!.isEmpty)
        ? countLabel
        : '$countLabel · $shareText';
    final Widget header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: <Widget>[
          TypeAvatar(icon, accent: accent ?? avatarAccent, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            fit: FlexFit.tight,
            child: Text(
              totalText,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
            semanticLabel: (isExpanded ? 'Collapse' : 'Expand').tr(context),
          ),
        ],
      ),
    );
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: isDragging ? 8 : 0,
      borderRadius: isDragging ? BorderRadius.circular(20) : null,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          if (showDivider) const Divider(height: 1),
          InkWell(onTap: onToggle, child: header),
          DisclosureSize(
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: expandedContentBuilder(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _HoldingItemRow extends StatelessWidget {
  const _HoldingItemRow({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.onOpen,
    this.icon,
  });

  final String title;
  final String subtitle;
  final String amount;
  final VoidCallback onOpen;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(top: 16, bottom: 16),
          child: Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 19, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                fit: FlexFit.tight,
                child: Text(
                  amount,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
