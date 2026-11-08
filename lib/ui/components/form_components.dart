import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';

/// Underlined field with shared helper slots and optional amount emphasis.
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    required this.controller,
    required this.label,
    this.onChanged,
    this.placeholder,
    this.prefix,
    this.suffix,
    this.singleLine = true,
    this.keyboardType,
    this.supportingText,
    this.isError = false,
    this.prominent = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final String? placeholder;
  final String? prefix;
  final String? suffix;
  final bool singleLine;
  final TextInputType? keyboardType;
  final String? supportingText;
  final bool isError;
  final bool prominent;

  static final List<TextInputFormatter> _decimalFormatters =
      <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
      ];

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: singleLine ? 1 : null,
      keyboardType: keyboardType,
      style: prominent
          ? Theme.of(context).textTheme.displaySmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)
          : Theme.of(context).textTheme.bodyMedium,
      inputFormatters:
          keyboardType == const TextInputType.numberWithOptions(decimal: true)
          ? _decimalFormatters
          : null,
      decoration: InputDecoration(
        border: prominent ? InputBorder.none : null,
        enabledBorder: prominent ? InputBorder.none : null,
        focusedBorder: prominent ? InputBorder.none : null,
        contentPadding: prominent ? EdgeInsets.zero : null,
        labelText: label,
        hintText: placeholder,
        prefixText: prefix,
        prefixStyle: prominent
            ? Theme.of(context).textTheme.displaySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)
            : null,
        suffixText: suffix,
        helperText: supportingText,
        errorText: isError ? supportingText : null,
      ),
    );
  }
}

/// A generic enum-style dropdown selector.
class DropdownSelector<T> extends StatelessWidget {
  const DropdownSelector({
    required this.label,
    required this.selected,
    required this.options,
    required this.optionLabel,
    required this.onSelected,
    this.compact = false,
    super.key,
  });

  final String label;
  final T selected;
  final List<T> options;
  final String Function(T) optionLabel;
  final ValueChanged<T> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return PopupMenuButton<T>(
        tooltip: label,
        onSelected: onSelected,
        itemBuilder: (_) => <PopupMenuEntry<T>>[
          for (final T option in options)
            PopupMenuItem<T>(value: option, child: Text(optionLabel(option))),
        ],
        child: PickerChip(label: optionLabel(selected)),
      );
    }
    return DropdownMenu<T>(
      initialSelection: selected,
      label: Text(label),
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      textStyle: Theme.of(context).textTheme.bodyMedium,
      onSelected: (T? value) {
        if (value != null) onSelected(value);
      },
      dropdownMenuEntries: <DropdownMenuEntry<T>>[
        for (final T option in options)
          DropdownMenuEntry<T>(value: option, label: optionLabel(option)),
      ],
    );
  }
}

class PickerChip extends StatelessWidget {
  const PickerChip({required this.label, this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Text(label, style: theme.textTheme.bodySmall),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.expand_more, size: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FormFieldPair extends StatelessWidget {
  const FormFieldPair({required this.first, required this.second, super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      if (constraints.maxWidth >= 300 &&
          MediaQuery.textScalerOf(context).scale(14) <= 18) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ],
        );
      }
      return Column(
        children: <Widget>[first, const SizedBox(height: 16), second],
      );
    },
  );
}

class CurrencySelector extends StatelessWidget {
  const CurrencySelector({
    required this.currency,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final String currency;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message:
            '${'Currency'.tr(context)}: '
            '$currency — ${CurrencyUtil.displayName(currency)}',
        child: PickerChip(label: currency, onPressed: onTap),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 48,
      leading: Tooltip(
        message: 'Currency'.tr(context),
        child: const Icon(Icons.payments_outlined, size: 20),
      ),
      title: Text(
        '$currency — ${CurrencyUtil.displayName(currency)}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      trailing: const Icon(Icons.expand_more, size: 20),
      onTap: onTap,
    );
  }
}

class OptionalNotesField extends StatefulWidget {
  const OptionalNotesField({
    required this.controller,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<OptionalNotesField> createState() => _OptionalNotesFieldState();
}

class _OptionalNotesFieldState extends State<OptionalNotesField> {
  late bool _expanded = widget.controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
    title: Text(
      'Notes (optional)'.tr(context),
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    initiallyExpanded: _expanded,
    onExpansionChanged: (bool value) => setState(() => _expanded = value),
    trailing: Icon(
      _expanded ? Icons.remove : Icons.add,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    maintainState: true,
    shape: const Border(),
    collapsedShape: const Border(),
    children: <Widget>[
      TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        minLines: 2,
        maxLines: null,
        decoration: InputDecoration(hintText: 'Notes (optional)'.tr(context)),
      ),
    ],
  );
}

/// A searchable currency picker dialog. Returns the chosen code, or null.
Future<String?> showCurrencyPickerDialog(
  BuildContext context, {
  required String selected,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) =>
        _CurrencyPickerDialog(selected: selected),
  );
}

class _CurrencyPickerDialog extends StatefulWidget {
  const _CurrencyPickerDialog({required this.selected});

  final String selected;

  @override
  State<_CurrencyPickerDialog> createState() => _CurrencyPickerDialogState();
}

class _CurrencyPickerDialogState extends State<_CurrencyPickerDialog> {
  static final Set<String> _commonSet = CurrencyUtil.commonCurrencies.toSet();
  static final List<String> _orderedCurrencies = List<String>.unmodifiable(
    <String>[
      ...CurrencyUtil.commonCurrencies,
      ...CurrencyUtil.allCurrencies.where(
        (String code) => !_commonSet.contains(code),
      ),
    ],
  );

  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<String> get _results {
    final String query = _query.text.trim().toUpperCase();
    if (query.isEmpty) return _orderedCurrencies;
    return _orderedCurrencies
        .where(
          (String code) =>
              code.contains(query) ||
              CurrencyUtil.displayName(code).toUpperCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<String> results = _results;
    return AlertDialog(
      title: Text('Choose currency'.tr(context)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Search'.tr(context)),
              ),
            ),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (BuildContext context, int index) {
                    final String code = results[index];
                    return ListTile(
                      title: Text('$code — ${CurrencyUtil.displayName(code)}'),
                      trailing: code == widget.selected
                          ? Text(
                              '✓',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(code),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close'.tr(context)),
        ),
      ],
    );
  }
}
