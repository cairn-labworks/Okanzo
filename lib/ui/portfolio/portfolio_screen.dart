import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local/entity/portfolio_entity.dart';
import '../../data/repository/portfolio_repository.dart';
import '../../di/app_container.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/ui_components.dart';
import '../theme/theme.dart';
import '../theme/app_material.dart';
import 'portfolio_list_view_model.dart';

/// Manage portfolios: create, rename, set default and delete.
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({this.onClose, super.key});

  /// When null the screen is hosted in the navigation shell and shows no
  /// back button.
  final VoidCallback? onClose;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  PortfolioListViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final AppContainer container = AppScope.of(context);
    _viewModel = PortfolioListViewModel(
      portfolioRepository: container.portfolioRepository,
      assetRepository: container.assetRepository,
      liabilityRepository: container.liabilityRepository,
      fxRepository: container.fxRepository,
      settingsRepository: container.settingsRepository,
    )..addListener(_onChanged);
  }

  void _onChanged() {
    final String? message = _viewModel?.message;
    if (message != null && mounted) {
      _viewModel!.consumeMessage();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.tr(context))));
    }
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onChanged);
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PortfolioListViewModel viewModel = _viewModel!;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (BuildContext context, _) {
        final List<PortfolioRow> rows = viewModel.rows;
        final bool hideBalances = viewModel.hideBalances;
        return Scaffold(
          appBar: AppBar(
            title: Text('Portfolios'.tr(context)),
            leading: widget.onClose == null
                ? null
                : IconButton(
                    tooltip: 'Back'.tr(context),
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back),
                  ),
            actions: <Widget>[
              HideBalancesButton(
                hideBalances: hideBalances,
                onPressed: viewModel.toggleHideBalances,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'portfolio-create',
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add),
            label: Text('New'.tr(context)),
          ),
          body: ListView.separated(
            padding: const EdgeInsets.only(
              top: 16,
              bottom: 96,
              left: 24,
              right: 24,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int index) {
              final PortfolioRow row = rows[index];
              return _PortfolioCard(
                row: row,
                hideBalances: hideBalances,
                onSelect: () =>
                    unawaited(viewModel.selectPortfolio(row.portfolio.id)),
                onSetDefault: () =>
                    unawaited(viewModel.setDefault(row.portfolio.id)),
                onRename: () => _showRenameDialog(row.portfolio),
                onDelete: () => _showDeleteDialog(row.portfolio),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showCreateDialog() {
    final PortfolioListViewModel viewModel = _viewModel!;
    return _showNameDialog(
      title: 'New portfolio'.tr(context),
      initial: '',
      confirmLabel: 'Create'.tr(context),
      onSave: viewModel.create,
    );
  }

  Future<void> _showRenameDialog(PortfolioEntity portfolio) {
    final PortfolioListViewModel viewModel = _viewModel!;
    return _showNameDialog(
      title: 'Rename portfolio'.tr(context),
      initial: portfolio.name,
      confirmLabel: 'Save'.tr(context),
      onSave: (name) => viewModel.rename(portfolio.id, name),
    );
  }

  Future<void> _showDeleteDialog(PortfolioEntity portfolio) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('Delete portfolio?'.tr(context)),
            content: Text(
              'This permanently deletes "{portfolio}" and all its assets '
                      'and liabilities.'
                  .tr(context)
                  .replaceAll('{portfolio}', portfolio.name),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'.tr(context)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Delete'.tr(context)),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await _viewModel?.delete(portfolio.id);
  }

  Future<void> _showNameDialog({
    required String title,
    required String initial,
    required String confirmLabel,
    required Future<void> Function(String) onSave,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _NameDialog(
        title: title,
        initial: initial,
        confirmLabel: confirmLabel,
        onSave: onSave,
      ),
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({
    required this.row,
    required this.hideBalances,
    required this.onSelect,
    required this.onSetDefault,
    required this.onRename,
    required this.onDelete,
  });

  final PortfolioRow row;
  final bool hideBalances;
  final VoidCallback onSelect;
  final VoidCallback onSetDefault;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final FinanceColors finance = FinanceColors.of(context);
    final bool isNegative = !hideBalances && row.netWorth < -0.005;
    return AppCard(
      clipBehavior: Clip.antiAlias,
      color: row.isViewing
          ? colors.surfaceContainer
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeLarge),
        side: BorderSide(
          color: row.isViewing
              ? colors.primary.withValues(alpha: 0.65)
              : colors.outlineVariant,
          width: row.isViewing ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(shapeLarge),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    row.isViewing ? Icons.folder : Icons.folder_outlined,
                    size: 19,
                    color: row.isViewing
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      row.portfolio.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More'.tr(context),
                    icon: const Icon(Icons.more_vert),
                    onSelected: (String value) {
                      switch (value) {
                        case 'default':
                          onSetDefault();
                        case 'rename':
                          onRename();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          if (!row.portfolio.isDefault)
                            PopupMenuItem<String>(
                              value: 'default',
                              child: Text('Set as default'.tr(context)),
                            ),
                          PopupMenuItem<String>(
                            value: 'rename',
                            child: Text('Rename'.tr(context)),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Delete'.tr(context)),
                          ),
                        ],
                  ),
                ],
              ),
              if (row.isViewing || row.portfolio.isDefault) ...<Widget>[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    if (row.isViewing)
                      _PortfolioBadge(
                        icon: Icons.check,
                        label: 'Viewing'.tr(context),
                        background: colors.primaryContainer,
                        foreground: colors.onPrimaryContainer,
                      ),
                    if (row.portfolio.isDefault)
                      _PortfolioBadge(
                        icon: Icons.star_outline,
                        label: 'Default'.tr(context),
                        background: colors.primary.withValues(alpha: 0.10),
                        foreground: colors.primary,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Text(
                hideBalances
                    ? CurrencyUtil.masked(row.baseCurrency)
                    : CurrencyUtil.format(row.netWorth, row.baseCurrency),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: isNegative ? finance.negative : colors.primary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Text(
                '{assets} assets · {liabilities} liabilities'
                    .tr(context)
                    .replaceAll('{assets}', '${row.assetCount}')
                    .replaceAll('{liabilities}', '${row.liabilityCount}'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (row.assetCount + row.liabilityCount > 0) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '${'Assets'.tr(context)} ${hideBalances ? CurrencyUtil.maskShort : CurrencyUtil.format(row.totalAssets, row.baseCurrency)}'
                  '  ·  '
                  '${'Liabilities'.tr(context)} ${hideBalances ? CurrencyUtil.maskShort : CurrencyUtil.format(row.totalLiabilities, row.baseCurrency)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PortfolioBadge extends StatelessWidget {
  const _PortfolioBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: foreground),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
    required this.onSave,
  });

  final String title;
  final String initial;
  final String confirmLabel;
  final Future<void> Function(String) onSave;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving || _controller.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_controller.text);
      if (mounted) Navigator.of(context).pop();
    } on DuplicatePortfolioNameException {
      if (mounted) {
        setState(() => _error = 'Name already in use. Try another');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canConfirm = _controller.text.trim().isNotEmpty;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          readOnly: _saving,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
            labelText: 'Name'.tr(context),
            errorText: _error?.tr(context),
            errorMaxLines: 2,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text('Cancel'.tr(context)),
          ),
          TextButton(
            onPressed: canConfirm && !_saving ? _save : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
