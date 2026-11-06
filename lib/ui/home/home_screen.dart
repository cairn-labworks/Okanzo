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
import '../theme/theme.dart';
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
  final Map<String, bool> _expanded = <String, bool>{};

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

  @override
  void dispose() {
    _viewModel?.removeListener(_onViewModelChanged);
    _viewModel?.dispose();
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
                  state.hideBalances ? Icons.visibility_off : Icons.visibility,
                ),
              ),
              IconButton(
                onPressed: state.isRefreshing ? null : viewModel.refresh,
                tooltip: 'Refresh prices'.tr(context),
                icon: state.isRefreshing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              IconButton(
                onPressed: widget.onOpenSettings,
                tooltip: 'Settings'.tr(context),
                icon: const Icon(Icons.settings),
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
                  onToggleExpanded: (String key) => setState(() {
                    _expanded[key] = !(_expanded[key] ?? false);
                  }),
                  onOpenAsset: (AssetEntity asset) =>
                      widget.onOpenAssetEditor(asset.portfolioId, asset.id),
                  onOpenLiability: (LiabilityEntity liability) =>
                      widget.onOpenLiabilityEditor(
                        liability.portfolioId,
                        liability.id,
                      ),
                  viewModel: viewModel,
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
                    Navigator.of(sheetContext).pop();
                    widget.onOpenAssetEditor(portfolio.id, 0);
                  },
                ),
                _AddSheetRow(
                  icon: Icons.inbox,
                  label: 'New liability'.tr(context),
                  onTap: () {
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
            style: theme.textTheme.titleLarge?.copyWith(
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
  });

  final HomeState state;
  final Map<String, bool> expanded;
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<AssetEntity> onOpenAsset;
  final ValueChanged<LiabilityEntity> onOpenLiability;
  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final bool colorful = AppStyle.of(context).colorfulCategories;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: NetWorthCard(
            summary: state.summary,
            hideBalances: state.hideBalances,
          ),
        ),
        SectionHeader(
          title: 'Assets'.tr(context),
          trailing: state.hideBalances
              ? CurrencyUtil.maskShort
              : CurrencyUtil.format(
                  state.summary.totalAssets,
                  state.baseCurrency,
                ),
        ),
        if (!state.hasAnyAssets)
          EmptyState(
            icon: Icons.account_balance_wallet,
            title: 'No assets yet'.tr(context),
            subtitle:
                'Add stocks, cash, property and more to track their value.'.tr(
                  context,
                ),
          )
        else
          DragReorderColumn<AssetCategoryGroup>(
            items: state.assetGroups,
            keyOf: (AssetCategoryGroup group) => group.type,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            verticalSpacing: 12,
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
                  return _CategoryCardShell(
                    icon: assetTypeIcon(group.type),
                    accent: colorful ? categoryColorAt(group.type.index) : null,
                    title: group.type.displayName.tr(context),
                    count: group.items.length,
                    totalText: state.hideBalances
                        ? CurrencyUtil.maskShort
                        : CurrencyUtil.format(group.total, group.baseCurrency),
                    isExpanded: expanded[key] ?? false,
                    isDragging: dragging,
                    onToggle: () => onToggleExpanded(key),
                    expandedContent: DragReorderColumn<AssetLine>(
                      items: group.items,
                      keyOf: (AssetLine line) => line.asset.id,
                      onReordered: (List<AssetLine> items) =>
                          viewModel.onAssetItemsReordered(
                            items.map((AssetLine l) => l.asset.id).toList(),
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
                            onOpen: () => onOpenAsset(line.asset),
                          ),
                    ),
                  );
                },
          ),
        const SizedBox(height: 12),
        SectionHeader(
          title: 'Liabilities'.tr(context),
          trailing: state.hideBalances
              ? CurrencyUtil.maskShort
              : CurrencyUtil.format(
                  state.summary.totalLiabilities,
                  state.baseCurrency,
                ),
        ),
        if (!state.hasAnyLiabilities)
          EmptyState(
            icon: Icons.inbox,
            title: 'No liabilities'.tr(context),
            subtitle: 'Track loans, credit cards and pending payments here.'.tr(
              context,
            ),
          )
        else
          DragReorderColumn<LiabilityCategoryGroup>(
            items: state.liabilityGroups,
            keyOf: (LiabilityCategoryGroup group) => group.type,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            verticalSpacing: 12,
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
                  return _CategoryCardShell(
                    icon: liabilityTypeIcon(group.type),
                    accent: colorful
                        ? categoryColorAt(group.type.index + 5)
                        : null,
                    title: group.type.displayName.tr(context),
                    count: group.items.length,
                    totalText: state.hideBalances
                        ? CurrencyUtil.maskShort
                        : CurrencyUtil.format(group.total, group.baseCurrency),
                    isExpanded: expanded[key] ?? false,
                    isDragging: dragging,
                    onToggle: () => onToggleExpanded(key),
                    expandedContent: DragReorderColumn<LiabilityLine>(
                      items: group.items,
                      keyOf: (LiabilityLine line) => line.liability.id,
                      onReordered: (List<LiabilityLine> items) =>
                          viewModel.onLiabilityItemsReordered(
                            items
                                .map((LiabilityLine l) => l.liability.id)
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
                            onOpen: () => onOpenLiability(line.liability),
                          ),
                    ),
                  );
                },
          ),
        const SizedBox(height: 8),
      ],
    );
  }
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
            color: gradient.last.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        heroTag: 'home-add-holding',
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
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
    required this.expandedContent,
    this.accent,
  });

  final IconData icon;
  final String title;
  final int count;
  final String totalText;
  final bool isExpanded;
  final bool isDragging;
  final VoidCallback onToggle;
  final Widget expandedContent;

  /// Per-category accent colour used by the Midnight theme. Null keeps the
  /// neutral Material look.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? accent = this.accent;
    Widget header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          TypeAvatar(icon, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  itemCountLabel(count).tr(context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            totalText,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            isExpanded ? Icons.expand_less : Icons.expand_more,
            color: theme.colorScheme.onSurfaceVariant,
            semanticLabel: (isExpanded ? 'Collapse' : 'Expand').tr(context),
          ),
        ],
      ),
    );
    if (accent != null) {
      header = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        child: header,
      );
    }
    return Card(
      elevation: isDragging ? 8 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeLarge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          InkWell(onTap: onToggle, child: header),
          if (isExpanded) ...<Widget>[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 4),
            expandedContent,
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
          : theme.colorScheme.surface,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.only(
            left: 20,
            right: 16,
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
              Text(amount, style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
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
