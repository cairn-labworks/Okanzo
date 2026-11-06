import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';

/// Outlined text field with the app's standard sizing and helper slots.
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

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: singleLine ? 1 : null,
      keyboardType: keyboardType,
      inputFormatters:
          keyboardType == const TextInputType.numberWithOptions(decimal: true)
          ? <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
            ]
          : null,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        hintText: placeholder,
        prefixText: prefix,
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
    super.key,
  });

  final String label;
  final T selected;
  final List<T> options;
  final String Function(T) optionLabel;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<T>(
      initialSelection: selected,
      label: Text(label),
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
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
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<String> get _results {
    final String query = _query.text.trim().toUpperCase();
    final List<String> common = CurrencyUtil.commonCurrencies;
    final List<String> ordered = <String>[
      ...common,
      ...CurrencyUtil.allCurrencies.where(
        (String code) => !common.contains(code),
      ),
    ];
    if (query.isEmpty) return ordered;
    return ordered
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
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Search'.tr(context),
                ),
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
