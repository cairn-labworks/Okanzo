import 'package:flutter/material.dart';

import '../../domain/model/stock_exchange.dart';
import '../../l10n/app_localizations.dart';

enum _ExchangeAction { preferences }

/// Keeps the selected listing visible even when it is no longer preferred.
class StockExchangeField extends StatefulWidget {
  const StockExchangeField({
    required this.selected,
    required this.preferredExchanges,
    required this.onSelected,
    required this.onSavePreferences,
    super.key,
  });

  final StockExchange? selected;
  final List<StockExchange> preferredExchanges;
  final ValueChanged<StockExchange> onSelected;
  final Future<void> Function(List<StockExchange>) onSavePreferences;

  static const String manageLabel = 'Select preferred exchanges...';

  @override
  State<StockExchangeField> createState() => _StockExchangeFieldState();
}

class _StockExchangeFieldState extends State<StockExchangeField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.text = widget.selected?.displayName.tr(context) ?? '';
  }

  @override
  void didUpdateWidget(StockExchangeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.text = widget.selected?.displayName.tr(context) ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DropdownMenu<Object>(
    controller: _controller,
    initialSelection: widget.selected,
    label: Text('Exchange'.tr(context)),
    hintText: 'Choose preferred exchanges'.tr(context),
    expandedInsets: EdgeInsets.zero,
    requestFocusOnTap: false,
    enableSearch: false,
    dropdownMenuEntries: <DropdownMenuEntry<Object>>[
      for (final StockExchange exchange in widget.preferredExchanges)
        DropdownMenuEntry<Object>(
          value: exchange,
          label: exchange.displayName.tr(context),
        ),
      DropdownMenuEntry<Object>(
        value: _ExchangeAction.preferences,
        label: StockExchangeField.manageLabel.tr(context),
        leadingIcon: const Icon(Icons.tune),
      ),
    ],
    onSelected: (Object? value) async {
      if (value is StockExchange) {
        widget.onSelected(value);
      } else if (value == _ExchangeAction.preferences) {
        _controller.text = widget.selected?.displayName.tr(context) ?? '';
        await showDialog<void>(
          context: context,
          builder: (_) => _PreferredExchangesDialog(
            selected: widget.preferredExchanges,
            onSave: widget.onSavePreferences,
          ),
        );
        if (context.mounted) {
          _controller.text = widget.selected?.displayName.tr(context) ?? '';
        }
      }
    },
  );
}

class _PreferredExchangesDialog extends StatefulWidget {
  const _PreferredExchangesDialog({
    required this.selected,
    required this.onSave,
  });

  final List<StockExchange> selected;
  final Future<void> Function(List<StockExchange>) onSave;

  @override
  State<_PreferredExchangesDialog> createState() =>
      _PreferredExchangesDialogState();
}

class _PreferredExchangesDialogState extends State<_PreferredExchangesDialog> {
  late final Set<StockExchange> _selected = widget.selected.toSet();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_selected.toList());
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('Preferred exchanges'.tr(context)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Choose the exchanges shown in stock and fund dropdowns.'.tr(
                context,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final StockExchange exchange in StockExchange.values)
                      CheckboxListTile(
                        key: ValueKey<StockExchange>(exchange),
                        contentPadding: EdgeInsets.zero,
                        title: Text(exchange.displayName.tr(context)),
                        value: _selected.contains(exchange),
                        onChanged: _saving
                            ? null
                            : (bool? checked) => setState(() {
                                if (checked == true) {
                                  _selected.add(exchange);
                                } else {
                                  _selected.remove(exchange);
                                }
                              }),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _selected.isEmpty
                  ? 'None selected. Use "{action}" to add exchanges later.'
                        .tr(context)
                        .replaceAll(
                          '{action}',
                          StockExchangeField.manageLabel.tr(context),
                        )
                  : '{count} selected'
                        .tr(context)
                        .replaceAll('{count}', '${_selected.length}'),
            ),
            if (_error != null)
              Text(
                "Couldn't save preferred exchanges: {error}"
                    .tr(context)
                    .replaceAll('{error}', _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr(context)),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text((_saving ? 'Saving...' : 'Save').tr(context)),
        ),
      ],
    ),
  );
}
