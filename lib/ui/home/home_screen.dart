import 'package:flutter/material.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../data/local/entity/portfolio_entity.dart';
import '../../di/app_container.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/drag_reorder_column.dart';
import '../components/type_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_style.dart';
import '../theme/colors.dart';
import 'category_groups.dart';
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
                onPressed: viewModel.toggleHideBalances,
                tooltip:
                    (state.hideBalances ? 'Show balances' : 'Hide balances').tr(
                      context,
                    ),
                icon: Icon(
                  state.hideBalances
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
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
              IconButton(
                onPressed: widget.onOpenSettings,
                tooltip: 'Settings'.tr(context),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          floatingActionButton: state.activePortfolio == null
              ? null
              : _AddFab(onPressed: () => _showAddSheet(state.activePortfolio!)),
          body: state.loading
              ? const Center(child: CircularProgressIndicator())
              : _HomeContent(
                  state: state,
                  expanded: _expanded,
                  onToggleExpanded: _toggleExpanded,
                  onOpenAsset: (AssetEntity asset) =>
                      widget.onOpenAssetEditor(asset.portfolioId, asset.id),
                  onOpenLiability: (LiabilityEntity liability) =>
                      widget.onOpenLiabilityEditor(
                        liability.portfolioId,
                        liability.id,
                      ),
                  viewModel: viewModel,
                  showAssets: _showAssets,
                  onSectionSelected: (bool value) =>
                      setState(() => _showAssets = value),
                ),
        );
      },
    );
  }

  Future<void> _showAddSheet(PortfolioEntity portfolio) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Text(
                    'Add to {portfolio}'
                        .tr(context)
                        .replaceAll('{portfolio}', portfolio.name),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
                _AddSheetRow(
                  icon: Icons.account_balance_wallet,
                  label: 'New asset'.tr(context),
                  onTap: () {
                    setState(() => _showAssets = true);
                    Navigator.of(sheetContext).pop();
                    widget.onOpenAssetEditor(portfolio.id, 0);
                  },
                ),
                _AddSheetRow(
                  icon: Icons.inbox,
                  label: 'New liability'.tr(context),
                  onTap: () {
                    setState(() => _showAssets = false);
                    Navigator.of(sheetContext).pop();
                    widget.onOpenLiabilityEditor(portfolio.id, 0);
                  },
                ),
              ],
            ),
          ),
        );
      },
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

class _AddSheetRow extends StatelessWidget {
  const _AddSheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: <Widget>[
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Text(label, style: theme.textTheme.bodyLarge),
          ],
        ),
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
  });

  final HomeState state;
  final ValueNotifier<Set<String>> expanded;
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<AssetEntity> onOpenAsset;
  final ValueChanged<LiabilityEntity> onOpenLiability;
  final HomeViewModel viewModel;
  final bool showAssets;
  final ValueChanged<bool> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final bool colorful = AppStyle.of(context).colorfulCategories;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
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
        const SizedBox(height: 16),
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
                    return ValueListenableBuilder<Set<String>>(
                      valueListenable: expanded,
                      builder:
                          (BuildContext context, Set<String> expandedKeys, _) =>
                              _CategoryCardShell(
                                icon: assetTypeIcon(group.type),
                                accent: colorful
                                    ? categoryColorAt(group.type.index)
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
                                    group.type != state.assetGroups.first.type,
                                onToggle: () => onToggleExpanded(key),
                                expandedContentBuilder: () =>
                                    DragReorderColumn<AssetLine>(
                                      items: group.items,
                                      keyOf: (AssetLine line) => line.asset.id,
                                      onReordered: (List<AssetLine> items) =>
                                          viewModel.onAssetItemsReordered(
                                            items
                                                .map(
                                                  (AssetLine l) => l.asset.id,
                                                )
                                                .toList(),
                                          ),
                                      itemBuilder:
                                          (
                                            BuildContext context,
                                            AssetLine line,
                                            bool itemDragging,
                                          ) => _HoldingItemRow(
                                            title: line.asset.name,
                                            subtitle: assetSubtitle(
                                              line.asset,
                                              group.baseCurrency,
                                              unitsLabel: 'units'.tr(context),
                                            ),
                                            amount: state.hideBalances
                                                ? CurrencyUtil.maskShort
                                                : CurrencyUtil.format(
                                                    line.convertedValue,
                                                    group.baseCurrency,
                                                  ),
                                            isDragging: itemDragging,
                                            onOpen: () =>
                                                onOpenAsset(line.asset),
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
                                DragReorderColumn<LiabilityLine>(
                                  items: group.items,
                                  keyOf: (LiabilityLine line) =>
                                      line.liability.id,
                                  onReordered: (List<LiabilityLine> items) =>
                                      viewModel.onLiabilityItemsReordered(
                                        items
                                            .map(
                                              (LiabilityLine l) =>
                                                  l.liability.id,
                                            )
                                            .toList(),
                                      ),
                                  itemBuilder:
                                      (
                                        BuildContext context,
                                        LiabilityLine line,
                                        bool itemDragging,
                                      ) => _HoldingItemRow(
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
                                        isDragging: itemDragging,
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

class _AddFab extends StatelessWidget {
  const _AddFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final List<Color>? gradient = AppStyle.of(context).fabGradient;
    if (gradient == null) {
      return FloatingActionButton.extended(
        heroTag: 'home-add-holding',
        onPressed: onPressed,
        icon: const Icon(Icons.add),
        label: Text('Add'.tr(context)),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        heroTag: 'home-add-holding',
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 0,
        highlightElevation: 0,
        icon: const Icon(Icons.add),
        label: Text('Add'.tr(context)),
      ),
    );
  }
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
          TypeAvatar(icon, accent: accent, size: 32),
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
          if (showDivider) const Divider(),
          InkWell(onTap: onToggle, child: header),
          if (isExpanded) ...<Widget>[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 4),
            expandedContentBuilder(),
            const SizedBox(height: 4),
          ],
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
    required this.isDragging,
    required this.onOpen,
  });

  final String title;
  final String subtitle;
  final String amount;
  final bool isDragging;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: isDragging
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 8,
            top: 12,
            bottom: 12,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.trim().isNotEmpty)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
              const SizedBox(width: 6),
              Icon(
                Icons.drag_indicator,
                size: 20,
                color: theme.colorScheme.outline,
                semanticLabel: 'Drag to reorder'.tr(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
