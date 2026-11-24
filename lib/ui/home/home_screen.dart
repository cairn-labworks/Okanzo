import 'package:flutter/material.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/local/entity/portfolio_entity.dart';
import '../../di/app_container.dart';
import '../../domain/model/asset_type.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/drag_reorder_column.dart';
import '../components/type_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_style.dart';
import '../theme/colors.dart';
import '../theme/motion.dart';
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
  final Map<String, HoldingSort> _sorts = <String, HoldingSort>{};
  final ValueNotifier<Set<String>> _expanded = ValueNotifier<Set<String>>(
    <String>{},
  );

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
    final Set<String> next = Set<String>.of(_expanded.value);
    if (!next.remove(key)) next.add(key);
    _expanded.value = next;
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onViewModelChanged);
    _viewModel?.dispose();
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
              IconButton(
                onPressed: state.isRefreshing ? null : viewModel.refresh,
                tooltip: 'Refresh prices'.tr(context),
                icon: state.isRefreshing
                    ? const RepaintBoundary(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.refresh),
              ),
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
                  onToggleExpanded: _toggleExpanded,
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

  Future<void> _openAsset(AssetEntity asset) async {
    final HoldingDetailsAction? action = await showHoldingDetails(
      context,
      asset: asset,
      portfolioName: _viewModel!.state.activePortfolio?.name,
      hideBalances: _viewModel!.state.hideBalances,
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

  Future<void> _openLiability(LiabilityEntity liability) async {
    final HoldingDetailsAction? action = await showHoldingDetails(
      context,
      liability: liability,
      portfolioName: _viewModel!.state.activePortfolio?.name,
      hideBalances: _viewModel!.state.hideBalances,
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
    final Widget label = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            state.activePortfolio?.name ?? 'Okanzo',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Icon(Icons.arrow_drop_down),
      ],
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
    required this.onToggleExpanded,
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
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<AssetEntity> onOpenAsset;
  final ValueChanged<LiabilityEntity> onOpenLiability;
  final HomeViewModel viewModel;
  final bool showAssets;
  final ValueChanged<bool> onSectionSelected;
  final Map<String, HoldingSort> sorts;
  final void Function(String, HoldingSort) onSort;

  @override
  Widget build(BuildContext context) {
    final bool colorful = AppStyle.of(context).colorfulCategories;
    final int holdingCount = showAssets
        ? state.assetGroups.fold(
            0,
            (total, group) => total + group.items.length,
          )
        : state.liabilityGroups.fold(
            0,
            (total, group) => total + group.items.length,
          );
    return ListView(
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
        ),
        const SizedBox(height: 24),
        _HoldingSectionTabs(
          showAssets: showAssets,
          onSelected: onSectionSelected,
        ),
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                (showAssets ? 'What you own' : 'What you owe')
                    .tr(context)
                    .toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              holdingCount == 1
                  ? '1 item'.tr(context)
                  : '{count} items'
                        .tr(context)
                        .replaceAll('{count}', '$holdingCount'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (showAssets && !state.hasAnyAssets)
          EmptyState(
            icon: Icons.account_balance_wallet,
            title: 'No assets yet'.tr(context),
            subtitle:
                'Add stocks, cash, property and more to track their value.'.tr(
                  context,
                ),
          ),
        if (showAssets && state.hasAnyAssets)
          _CategoryPanel(
            child: DragReorderColumn<AssetCategoryGroup>(
              items: state.assetGroups,
              keyOf: (AssetCategoryGroup group) => group.type,
              onReordered: (List<AssetCategoryGroup> groups) =>
                  viewModel.onAssetCategoriesReordered(
                    groups.map((AssetCategoryGroup g) => g.type).toList(),
                  ),
              itemBuilder:
                  (
                    BuildContext context,
                    AssetCategoryGroup group,
                    bool dragging,
                  ) {
                    final String key = 'asset-${group.type.storageName}';
                    final String sortKey = '${state.activePortfolio!.id}-$key';
                    final metal = group.items.first.asset.displayedMetal;
                    final bool singleMetal =
                        metal != null &&
                        group.items.every(
                          (line) => line.asset.displayedMetal == metal,
                        );
                    return ValueListenableBuilder<Set<String>>(
                      valueListenable: expanded,
                      builder:
                          (
                            BuildContext context,
                            Set<String> expandedKeys,
                            _,
                          ) => _CategoryCardShell(
                            icon: singleMetal
                                ? metalIcon(metal)
                                : assetTypeIcon(group.type),
                            accent: colorful
                                ? categoryColorAt(group.type.index)
                                : null,
                            title: group.type.displayName.tr(context),
                            count: group.items.length,
                            totalText:
                                group.type == AssetType.metals &&
                                    group.items.every(
                                      (line) => !line.asset.isPriced,
                                    )
                                ? 'Price pending'.tr(context)
                                : state.hideBalances
                                ? CurrencyUtil.maskShort
                                : CurrencyUtil.format(
                                    group.total,
                                    group.baseCurrency,
                                  ),
                            isExpanded: expandedKeys.contains(key),
                            isDragging: dragging,
                            showDivider:
                                group.type != state.assetGroups.first.type,
                            onToggle: () => onToggleExpanded(key),
                            expandedContentBuilder: () =>
                                HoldingGroupList<AssetLine>(
                                  items: group.items,
                                  name: (line) => line.asset.displayName,
                                  value: (line) => line.convertedValue,
                                  priced: (line) => line.asset.isPriced,
                                  sort: sorts[sortKey] ?? HoldingSort.custom,
                                  onSort: (sort) => onSort(sortKey, sort),
                                  onReordered: (List<AssetLine> items) =>
                                      viewModel.onAssetItemsReordered(
                                        items
                                            .map((AssetLine l) => l.asset.id)
                                            .toList(),
                                      ),
                                  itemBuilder: (AssetLine line) =>
                                      _HoldingItemRow(
                                        icon: line.asset.displayedMetal == null
                                            ? null
                                            : metalIcon(
                                                line.asset.displayedMetal!,
                                              ),
                                        title: line.asset.displayName,
                                        subtitle: assetSubtitle(
                                          line.asset,
                                          group.baseCurrency,
                                          unitsLabel: 'units'.tr(context),
                                          hideBalances: state.hideBalances,
                                          localize: (label) =>
                                              label.tr(context),
                                        ),
                                        amount:
                                            line.asset.type ==
                                                    AssetType.metals &&
                                                !line.asset.isPriced
                                            ? 'Price pending'.tr(context)
                                            : state.hideBalances
                                            ? CurrencyUtil.maskShort
                                            : CurrencyUtil.format(
                                                line.convertedValue,
                                                group.baseCurrency,
                                              ),
                                        onOpen: () => onOpenAsset(line.asset),
                                      ),
                                ),
                          ),
                    );
                  },
            ),
          ),
        if (!showAssets && !state.hasAnyLiabilities)
          EmptyState(
            icon: Icons.inbox,
            title: 'No liabilities'.tr(context),
            subtitle: 'Track loans, credit cards and pending payments here.'.tr(
              context,
            ),
          ),
        if (!showAssets && state.hasAnyLiabilities)
          _CategoryPanel(
            child: DragReorderColumn<LiabilityCategoryGroup>(
              items: state.liabilityGroups,
              keyOf: (LiabilityCategoryGroup group) => group.type,
              onReordered: (List<LiabilityCategoryGroup> groups) =>
                  viewModel.onLiabilityCategoriesReordered(
                    groups.map((LiabilityCategoryGroup g) => g.type).toList(),
                  ),
              itemBuilder:
                  (
                    BuildContext context,
                    LiabilityCategoryGroup group,
                    bool dragging,
                  ) {
                    final String key = 'liability-${group.type.storageName}';
                    final String sortKey = '${state.activePortfolio!.id}-$key';
                    return ValueListenableBuilder<Set<String>>(
                      valueListenable: expanded,
                      builder:
                          (
                            BuildContext context,
                            Set<String> expandedKeys,
                            _,
                          ) => _CategoryCardShell(
                            icon: liabilityTypeIcon(group.type),
                            accent: colorful
                                ? categoryColorAt(group.type.index + 5)
                                : null,
                            title: group.type.displayName.tr(context),
                            count: group.items.length,
                            totalText: state.hideBalances
                                ? CurrencyUtil.maskShort
                                : CurrencyUtil.format(
                                    group.total,
                                    group.baseCurrency,
                                  ),
                            isExpanded: expandedKeys.contains(key),
                            isDragging: dragging,
                            showDivider:
                                group.type != state.liabilityGroups.first.type,
                            onToggle: () => onToggleExpanded(key),
                            expandedContentBuilder: () =>
                                HoldingGroupList<LiabilityLine>(
                                  items: group.items,
                                  name: (line) => line.liability.name,
                                  value: (line) => line.convertedValue,
                                  priced: (_) => true,
                                  sort: sorts[sortKey] ?? HoldingSort.custom,
                                  onSort: (sort) => onSort(sortKey, sort),
                                  onReordered: (List<LiabilityLine> items) =>
                                      viewModel.onLiabilityItemsReordered(
                                        items
                                            .map(
                                              (LiabilityLine l) =>
                                                  l.liability.id,
                                            )
                                            .toList(),
                                      ),
                                  itemBuilder: (LiabilityLine line) =>
                                      _HoldingItemRow(
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
                                        onOpen: () =>
                                            onOpenLiability(line.liability),
                                      ),
                                ),
                          ),
                    );
                  },
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _HoldingSectionTabs extends StatelessWidget {
  const _HoldingSectionTabs({
    required this.showAssets,
    required this.onSelected,
  });

  final bool showAssets;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        children: <Widget>[
          for (final bool assets in <bool>[true, false])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Material(
                  color: showAssets == assets
                      ? theme.colorScheme.surfaceContainerHigh
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: Semantics(
                    selected: showAssets == assets,
                    button: true,
                    child: InkWell(
                      key: ValueKey<String>(
                        assets ? 'home-assets-tab' : 'home-liabilities-tab',
                      ),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onSelected(assets),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Center(
                            child: Text(
                              (assets ? 'Assets' : 'Liabilities').tr(context),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: showAssets == assets
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
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
    this.accent,
  });

  final IconData icon;
  final String title;
  final int count;
  final String totalText;
  final bool isExpanded;
  final bool isDragging;
  final VoidCallback onToggle;
  final Widget Function() expandedContentBuilder;
  final bool showDivider;

  /// Per-category accent colour used by the Midnight theme. Null keeps the
  /// neutral Material look.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? accent = this.accent;
    final Widget header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: <Widget>[
          TypeAvatar(icon, accent: accent, size: 40),
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
                  count == 1
                      ? '1 item'.tr(context)
                      : '{count} items'
                            .tr(context)
                            .replaceAll('{count}', '$count'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
