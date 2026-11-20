import 'package:flutter/material.dart';

import '../../domain/model/stock_exchange.dart';
import '../../l10n/app_localizations.dart';
import '../components/form_components.dart';
import '../components/type_icons.dart';

enum _ExchangeAction { preferences }

/// Keeps the selected listing visible even when it is no longer preferred.
class StockExchangeField extends StatefulWidget {
  const StockExchangeField({
    required this.selected,
    required this.preferredExchanges,
    required this.onSelected,
    required this.onSavePreferences,
    this.isMutualFund = false,
    this.compact = false,
    this.canvas = false,
    super.key,
  });

  final StockExchange? selected;
  final List<StockExchange> preferredExchanges;
  final ValueChanged<StockExchange> onSelected;
  final Future<void> Function(List<StockExchange>) onSavePreferences;
  final bool isMutualFund;
  final bool compact;
  final bool canvas;

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
  Widget build(BuildContext context) {
    final IconData selectedIcon = widget.selected == null
        ? Icons.candlestick_chart
        : stockExchangeIcon(widget.selected!);
    if (widget.compact || widget.canvas) {
      final StockExchange? selectedExchange = widget.selected;
      final String label = selectedExchange == StockExchange.us
          ? 'US exchange'.tr(context)
          : selectedExchange?.displayName.tr(context) ?? 'Exchange'.tr(context);
      final String? suffix = selectedExchange?.suffix;
      final String help = suffix == null || suffix.isEmpty
          ? 'Enter a Yahoo Finance ticker with or without an exchange suffix.'
                .tr(context)
          : 'Okanzo adds {suffix} automatically. You can also enter a full Yahoo Finance ticker.'
                .tr(context)
                .replaceAll('{suffix}', suffix);
      final String exampleHint;
      if (selectedExchange == null) {
        exampleHint = 'e.g. US (NYSE / Nasdaq), BSE (India), Euronext'.tr(
          context,
        );
      } else {
        final (String exName, String exTicker) = selectedExchange
            .exampleHolding(fund: widget.isMutualFund);
        if (selectedExchange.suffix.isNotEmpty) {
          exampleHint = 'Adds {suffix} automatically (e.g. {example})'
              .tr(context)
              .replaceAll('{suffix}', selectedExchange.suffix)
              .replaceAll('{example}', selectedExchange.qualify(exTicker));
        } else if (selectedExchange == StockExchange.other) {
          exampleHint = 'Full Yahoo ticker with suffix (e.g. {example})'
              .tr(context)
              .replaceAll('{example}', exTicker);
        } else {
          exampleHint = 'e.g. {name} ({ticker}) · NYSE / Nasdaq'
              .tr(context)
              .replaceAll('{name}', exName)
              .replaceAll('{ticker}', exTicker);
        }
      }
      return Tooltip(
        message: '${'Exchange'.tr(context)}: $label\n$help',
        child: PickerChip(
          label: label,
          icon: selectedIcon,
          fieldLabel: widget.canvas ? 'Exchange'.tr(context) : null,
          supportingText: widget.canvas ? exampleHint : null,
          onPressed: _openPicker,
        ),
      );
    }
    return DropdownMenu<Object>(
      controller: _controller,
      initialSelection: widget.selected,
      label: Text('Exchange'.tr(context)),
      leadingIcon: Icon(selectedIcon, size: 20),
      hintText: 'Choose preferred exchanges'.tr(context),
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      enableSearch: false,
      dropdownMenuEntries: <DropdownMenuEntry<Object>>[
        for (final StockExchange exchange in widget.preferredExchanges)
          DropdownMenuEntry<Object>(
            value: exchange,
            label: exchange.displayName.tr(context),
            leadingIcon: Icon(stockExchangeIcon(exchange), size: 18),
          ),
        DropdownMenuEntry<Object>(
          value: _ExchangeAction.preferences,
          label: StockExchangeField.manageLabel.tr(context),
          leadingIcon: const Icon(Icons.tune, size: 18),
        ),
      ],
      onSelected: _select,
    );
  }

  Future<void> _openPicker() async {
    final Object? picked = await showSelectionPickerDialog<Object>(
      context,
      eyebrow: 'Market listing'.tr(context),
      title: 'Exchange'.tr(context),
      searchPlaceholder: 'e.g. US, BSE, Euronext, Tokyo'.tr(context),
      selected: widget.selected,
      options: <Object>[
        ...widget.preferredExchanges,
        _ExchangeAction.preferences,
      ],
      optionLabel: (Object option) => option is StockExchange
          ? option.displayName.tr(context)
          : StockExchangeField.manageLabel.tr(context),
      optionSubtitle: (Object option) =>
          option is StockExchange && option.suffix.isNotEmpty
          ? 'Adds {suffix} automatically'
                .tr(context)
                .replaceAll('{suffix}', option.suffix)
          : null,
      optionIcon: (Object option) =>
          option is StockExchange ? stockExchangeIcon(option) : Icons.tune,
    );
    if (mounted) await _select(picked);
  }

  Future<void> _select(Object? value) async {
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
      if (mounted) {
        _controller.text = widget.selected?.displayName.tr(context) ?? '';
      }
    }
  }
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
                child: ClipRect(
                  child: Material(
                    type: MaterialType.transparency,
                    clipBehavior: Clip.hardEdge,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final StockExchange exchange
                            in StockExchange.values)
                          CheckboxListTile(
                            key: ValueKey<StockExchange>(exchange),
                            contentPadding: EdgeInsets.zero,
                            minLeadingWidth: 20,
                            horizontalTitleGap: 10,
                            secondary: Icon(
                              stockExchangeIcon(exchange),
                              size: 20,
                              color: _selected.contains(exchange)
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                            ),
                            title: Text(
                              exchange.displayName.tr(context),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
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
