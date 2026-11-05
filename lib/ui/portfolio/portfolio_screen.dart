import 'package:flutter/material.dart';

import '../../data/local/entity/portfolio_entity.dart';
import '../../di/app_container.dart';
import '../../util/currency_util.dart';
import '../theme/theme.dart';
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
          .showSnackBar(SnackBar(content: Text(message)));
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
        return Scaffold(
          appBar: AppBar(
            title: const Text('Portfolios'),
            leading: widget.onClose == null
                ? null
                : IconButton(
                    tooltip: 'Back',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back),
                  ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'portfolio-create',
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add),
            label: const Text('New'),
          ),
          body: ListView.separated(
            padding: const EdgeInsets.only(
              top: 8,
              bottom: 96,
              left: 16,
              right: 16,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int index) {
              final PortfolioRow row = rows[index];
              return _PortfolioCard(
                row: row,
                onSetDefault: () => viewModel.setDefault(row.portfolio.id),
                onRename: () => _showRenameDialog(row.portfolio),
                onDelete: () => _showDeleteDialog(row.portfolio),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showCreateDialog() async {
    final String? name = await _showNameDialog(
      title: 'New portfolio',
      initial: '',
      confirmLabel: 'Create',
    );
    if (name != null) _viewModel?.create(name);
  }

  Future<void> _showRenameDialog(PortfolioEntity portfolio) async {
    final String? name = await _showNameDialog(
      title: 'Rename portfolio',
      initial: portfolio.name,
      confirmLabel: 'Save',
    );
    if (name != null) _viewModel?.rename(portfolio.id, name);
  }

  Future<void> _showDeleteDialog(PortfolioEntity portfolio) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Delete portfolio?'),
            content: Text(
              '"${portfolio.name}" and all of its assets and liabilities '
              'will be permanently removed.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await _viewModel?.delete(portfolio.id);
  }

  Future<String?> _showNameDialog({
    required String title,
    required String initial,
    required String confirmLabel,
  }) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => _NameDialog(
        title: title,
        initial: initial,
        confirmLabel: confirmLabel,
      ),
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({
    required this.row,
    required this.onSetDefault,
    required this.onRename,
    required this.onDelete,
  });

  final PortfolioRow row;
  final VoidCallback onSetDefault;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    row.portfolio.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (row.portfolio.isDefault)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Chip(label: Text('Default')),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'More',
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
                          const PopupMenuItem<String>(
                            value: 'default',
                            child: Text('Set as default'),
                          ),
                        const PopupMenuItem<String>(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                ),
              ],
            ),
            Text(
              CurrencyUtil.format(row.netWorth, row.baseCurrency),
              style: theme.textTheme.headlineSmall,
            ),
            Text(
              '${row.assetCount} assets · ${row.liabilityCount} liabilities',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canConfirm = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Name',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: canConfirm
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
