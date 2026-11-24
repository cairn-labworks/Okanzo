import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../asset/asset_form_state.dart' show filterDecimal;
import 'type_icons.dart';

const EdgeInsets _editorFieldPadding = EdgeInsets.only(top: 24, bottom: 4);

/// Slightly higher-contrast border for Canvas editor boxes and modal panels,
/// matching `--box-line` in the prototype (`#3B5446` dark, `#C5D3C0` light)
/// while keeping row/section dividers on the subtler `outlineVariant`.
Color canvasBoxBorderColor(ColorScheme colors) {
  if (colors.outlineVariant == const Color(0xFF2A3934)) {
    return const Color(0xFF3B5446);
  }
  if (colors.outlineVariant == const Color(0xFFD1DCCE)) {
    return const Color(0xFFC5D3C0);
  }
  return Color.lerp(
    colors.outlineVariant,
    colors.outline,
    colors.brightness == Brightness.dark ? 0.24 : 0.16,
  )!;
}

/// Shared field with optional Canvas outlines and amount emphasis.
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    required this.controller,
    required this.label,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.focusNode,
    this.autofocus = false,
    this.placeholder,
    this.prefix,
    this.suffix,
    this.singleLine = true,
    this.keyboardType,
    this.supportingText,
    this.isError = false,
    this.prominent = false,
    this.maxLength,
    this.canvas = false,
    this.showLabel = true,
    this.inputFormatters,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? placeholder;
  final String? prefix;
  final String? suffix;
  final bool singleLine;
  final TextInputType? keyboardType;
  final String? supportingText;
  final bool isError;
  final bool prominent;
  final int? maxLength;
  final bool canvas;
  final bool showLabel;
  final List<TextInputFormatter>? inputFormatters;

  static final List<TextInputFormatter> _decimalFormatters =
      <TextInputFormatter>[
        TextInputFormatter.withFunction((
          TextEditingValue oldValue,
          TextEditingValue newValue,
        ) {
          final String filtered = filterDecimal(newValue.text);
          if (filtered == newValue.text) return newValue;
          final int cursor = newValue.selection.extentOffset.clamp(
            0,
            newValue.text.length,
          );
          final int filteredCursor = filterDecimal(
            newValue.text.substring(0, cursor),
          ).length;
          return TextEditingValue(
            text: filtered,
            selection: TextSelection.collapsed(offset: filteredCursor),
          );
        }),
      ];

  @override
  Widget build(BuildContext context) {
    final List<TextInputFormatter>? effectiveFormatters =
        inputFormatters ??
        (keyboardType == const TextInputType.numberWithOptions(decimal: true)
            ? _decimalFormatters
            : null);
    final Widget field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      maxLines: singleLine ? 1 : null,
      maxLength: maxLength,
      keyboardType: keyboardType,
      style: prominent
          ? Theme.of(context).textTheme.displaySmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)
          : Theme.of(context).textTheme.bodyLarge,
      inputFormatters: effectiveFormatters,
      decoration: InputDecoration(
        border: prominent ? InputBorder.none : null,
        enabledBorder: prominent ? InputBorder.none : null,
        focusedBorder: prominent ? InputBorder.none : null,
        contentPadding: prominent ? EdgeInsets.zero : _editorFieldPadding,
        label: Transform.translate(
          // Scaled to -6px; the input's +2px makes the label move -4px overall.
          offset: const Offset(0, -8),
          child: Text(label),
        ),
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
    if (canvas) {
      final ThemeData theme = Theme.of(context);
      final ColorScheme colors = theme.colorScheme;
      final TextStyle? inputStyle = prominent
          ? theme.textTheme.displaySmall?.copyWith(
              color: colors.primary,
              fontSize: 32,
              height: 1.3,
            )
          : theme.textTheme.bodyLarge;
      final OutlineInputBorder border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: canvasBoxBorderColor(colors)),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (showLabel) ...<Widget>[
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 7),
            ],
            Semantics(
              label: label,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                textInputAction: textInputAction,
                maxLines: singleLine ? 1 : null,
                maxLength: maxLength,
                keyboardType: keyboardType,
                style: inputStyle,
                inputFormatters: effectiveFormatters,
                decoration: InputDecoration(
                  labelText: null,
                  hintText: placeholder,
                  prefixText: prefix,
                  suffixText: suffix,
                  helperText: supportingText,
                  errorText: isError ? supportingText : null,
                  hintStyle: inputStyle?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  filled: !prominent,
                  fillColor: colors.surfaceContainerLow,
                  border: prominent
                      ? UnderlineInputBorder(
                          borderSide: BorderSide(color: colors.outlineVariant),
                        )
                      : border,
                  enabledBorder: prominent
                      ? UnderlineInputBorder(
                          borderSide: BorderSide(color: colors.outlineVariant),
                        )
                      : border,
                  errorBorder: prominent
                      ? UnderlineInputBorder(
                          borderSide: BorderSide(color: colors.error),
                        )
                      : border.copyWith(
                          borderSide: BorderSide(color: colors.error),
                        ),
                  focusedErrorBorder: prominent
                      ? UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: colors.error,
                            width: 1.5,
                          ),
                        )
                      : border.copyWith(
                          borderSide: BorderSide(
                            color: colors.error,
                            width: 1.5,
                          ),
                        ),
                  focusedBorder: prominent
                      ? UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: colors.primary,
                            width: 1.5,
                          ),
                        )
                      : border.copyWith(
                          borderSide: BorderSide(
                            color: colors.primary,
                            width: 1.5,
                          ),
                        ),
                  contentPadding: prominent
                      ? const EdgeInsets.only(top: 4, bottom: 14)
                      : const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 14,
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return prominent
        ? Transform.translate(offset: const Offset(0, 2), child: field)
        : field;
  }
}

TextInputAction requiredFieldInputAction(
  Map<FocusNode, TextEditingController> fields, {
  FocusNode? current,
}) =>
    fields.entries.any(
      (entry) => entry.key != current && entry.value.text.trim().isEmpty,
    )
    ? TextInputAction.next
    : TextInputAction.done;

void focusNextRequiredField(
  BuildContext context,
  Map<FocusNode, TextEditingController> fields,
) {
  for (final entry in fields.entries) {
    if (entry.value.text.trim().isEmpty) {
      entry.key.requestFocus();
      return;
    }
  }
  FocusScope.of(context).unfocus();
}

Widget buildPopupMenuOption(
  BuildContext context, {
  required String label,
  IconData? icon,
  bool selected = false,
}) {
  if (icon == null) return Text(label);
  final ColorScheme colors = Theme.of(context).colorScheme;
  return Row(
    children: <Widget>[
      Icon(
        icon,
        size: 18,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(label)),
    ],
  );
}

/// A generic enum-style dropdown selector.
class DropdownSelector<T> extends StatelessWidget {
  const DropdownSelector({
    required this.label,
    required this.selected,
    required this.options,
    required this.optionLabel,
    required this.onSelected,
    this.dialogEyebrow,
    this.dialogTitle,
    this.searchPlaceholder,
    this.supportingText,
    this.optionSubtitle,
    this.optionIcon,
    this.compact = false,
    this.canvas = false,
    super.key,
  });

  final String label;
  final String? dialogEyebrow;
  final String? dialogTitle;
  final String? searchPlaceholder;
  final String? supportingText;
  final T selected;
  final List<T> options;
  final String Function(T) optionLabel;
  final String? Function(T)? optionSubtitle;
  final IconData Function(T)? optionIcon;
  final ValueChanged<T> onSelected;
  final bool compact;
  final bool canvas;

  @override
  Widget build(BuildContext context) {
    if (compact || canvas) {
      return Tooltip(
        message: '$label: ${optionLabel(selected)}',
        child: PickerChip(
          fieldLabel: canvas ? label : null,
          supportingText: canvas ? supportingText : null,
          label: optionLabel(selected),
          icon: optionIcon?.call(selected),
          onPressed: () async {
            final T? picked = await showSelectionPickerDialog<T>(
              context,
              eyebrow: dialogEyebrow,
              title: dialogTitle ?? label,
              searchPlaceholder: searchPlaceholder,
              selected: selected,
              options: options,
              optionLabel: optionLabel,
              optionSubtitle: optionSubtitle,
              optionIcon: optionIcon,
            );
            if (picked != null && context.mounted) onSelected(picked);
          },
        ),
      );
    }
    return DropdownMenu<T>(
      initialSelection: selected,
      label: Text(label),
      leadingIcon: optionIcon == null
          ? null
          : Icon(optionIcon!(selected), size: 20),
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      textStyle: Theme.of(context).textTheme.bodyMedium,
      onSelected: (T? value) {
        if (value != null) onSelected(value);
      },
      dropdownMenuEntries: <DropdownMenuEntry<T>>[
        for (final T option in options)
          DropdownMenuEntry<T>(
            value: option,
            label: optionLabel(option),
            leadingIcon: optionIcon == null
                ? null
                : Icon(optionIcon!(option), size: 18),
          ),
      ],
    );
  }
}

class PickerChip extends StatelessWidget {
  const PickerChip({
    required this.label,
    this.icon,
    this.onPressed,
    this.focusNode,
    this.fieldLabel,
    this.supportingText,
    this.buttonKey,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final String? fieldLabel;
  final String? supportingText;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (fieldLabel != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            fieldLabel!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 7),
          Material(
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: canvasBoxBorderColor(theme.colorScheme)),
            ),
            child: InkWell(
              key: buttonKey,
              focusNode: focusNode,
              borderRadius: BorderRadius.circular(10),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 14,
                ),
                child: Row(
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 19, color: theme.colorScheme.primary),
                      const SizedBox(width: 9),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.expand_more, size: 16),
                  ],
                ),
              ),
            ),
          ),
          if (supportingText != null && supportingText!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              supportingText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: buttonKey,
        focusNode: focusNode,
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
                    if (icon != null) ...<Widget>[
                      Icon(
                        icon,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

/// Paired secondary Cancel and primary Save actions for editor forms.
class FormActionRow extends StatelessWidget {
  const FormActionRow({
    required this.onCancel,
    required this.onSave,
    this.isSaving = false,
    this.showCancel = true,
    super.key,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onSave;
  final bool isSaving;
  final bool showCancel;

  @override
  Widget build(BuildContext context) {
    final Widget cancelButton = OutlinedButton(
      onPressed: onCancel,
      child: Text('Cancel'.tr(context)),
    );
    final Widget saveButton = FilledButton(
      onPressed: onSave,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isSaving) ...<Widget>[
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text('Save'.tr(context))),
        ],
      ),
    );
    if (!showCancel) return SizedBox(width: double.infinity, child: saveButton);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= 260 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20) {
          return Row(
            children: <Widget>[
              Expanded(child: cancelButton),
              const SizedBox(width: 12),
              Expanded(child: saveButton),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            cancelButton,
            const SizedBox(height: 10),
            saveButton,
          ],
        );
      },
    );
  }
}

class CurrencySelector extends StatelessWidget {
  const CurrencySelector({
    required this.currency,
    required this.onTap,
    this.supportingText,
    this.compact = false,
    this.canvas = false,
    super.key,
  });

  final String currency;
  final VoidCallback onTap;
  final String? supportingText;
  final bool compact;
  final bool canvas;

  @override
  Widget build(BuildContext context) {
    final IconData icon = currencyIcon(currency);
    if (compact || canvas) {
      return Tooltip(
        message:
            '${'Currency'.tr(context)}: '
            '$currency — ${CurrencyUtil.displayName(currency)}',
        child: PickerChip(
          label: currency,
          icon: icon,
          onPressed: onTap,
          fieldLabel: canvas ? 'Currency'.tr(context) : null,
          supportingText: canvas ? supportingText : null,
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 48,
      leading: Tooltip(
        message: 'Currency'.tr(context),
        child: Icon(icon, size: 20),
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

class OptionalCustomNameField extends StatefulWidget {
  const OptionalCustomNameField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.placeholder,
    this.maxLength = 60,
    this.textInputAction,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final int maxLength;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<OptionalCustomNameField> createState() =>
      _OptionalCustomNameFieldState();
}

class _OptionalCustomNameFieldState extends State<OptionalCustomNameField> {
  final FocusNode _focusNode = FocusNode();
  late bool _expanded = widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFromController);
  }

  @override
  void didUpdateWidget(OptionalCustomNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
    }
    _syncFromController();
  }

  void _syncFromController() {
    if (!_expanded && widget.controller.text.trim().isNotEmpty) {
      setState(() => _expanded = true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    final bool next = !_expanded;
    setState(() => _expanded = next);
    if (next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else {
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: const ValueKey<String>('custom-name-toggle'),
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _expanded
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded ? Icons.remove : Icons.edit_outlined,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: LabeledTextField(
                canvas: true,
                showLabel: false,
                controller: widget.controller,
                focusNode: _focusNode,
                label: widget.label,
                placeholder: widget.placeholder,
                maxLength: widget.maxLength,
                textInputAction: widget.textInputAction,
                onSubmitted: widget.onSubmitted,
                onChanged: widget.onChanged,
              ),
            ),
        ],
      ),
    );
  }
}

/// A searchable currency picker dialog. Returns the chosen code, or null.
Future<String?> showCurrencyPickerDialog(
  BuildContext context, {
  required String selected,
  String? eyebrow,
}) => showSelectionPickerDialog<String>(
  context,
  eyebrow: eyebrow ?? 'Holding currency'.tr(context),
  title: 'Choose currency'.tr(context),
  searchPlaceholder: 'e.g. INR, USD, Euro, Yen'.tr(context),
  selected: selected,
  options: <String>[
    ...CurrencyUtil.commonCurrencies,
    ...CurrencyUtil.allCurrencies.where(
      (String code) => !CurrencyUtil.commonCurrencies.contains(code),
    ),
  ],
  optionLabel: (String code) => '$code — ${CurrencyUtil.displayName(code)}',
  optionIcon: currencyIcon,
);

Future<T?> showSelectionPickerDialog<T>(
  BuildContext context, {
  required String title,
  required T? selected,
  required List<T> options,
  required String Function(T) optionLabel,
  String? eyebrow,
  String? searchPlaceholder,
  String? Function(T)? optionSubtitle,
  IconData Function(T)? optionIcon,
  bool searchable = true,
}) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return showDialog<T>(
    context: context,
    barrierColor: dark ? const Color(0xAA10231B) : const Color(0x7310231B),
    builder: (BuildContext context) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: _SelectionPickerDialog<T>(
        eyebrow: eyebrow,
        title: title,
        searchPlaceholder: searchPlaceholder,
        selected: selected,
        options: options,
        optionLabel: optionLabel,
        optionSubtitle: optionSubtitle,
        optionIcon: optionIcon,
        searchable: searchable,
      ),
    ),
  );
}

class _SelectionPickerDialog<T> extends StatefulWidget {
  const _SelectionPickerDialog({
    required this.title,
    required this.selected,
    required this.options,
    required this.optionLabel,
    this.eyebrow,
    this.searchPlaceholder,
    this.optionSubtitle,
    this.optionIcon,
    required this.searchable,
  });

  final String? eyebrow;
  final String title;
  final String? searchPlaceholder;
  final T? selected;
  final List<T> options;
  final String Function(T) optionLabel;
  final String? Function(T)? optionSubtitle;
  final IconData Function(T)? optionIcon;
  final bool searchable;

  @override
  State<_SelectionPickerDialog<T>> createState() =>
      _SelectionPickerDialogState<T>();
}

class _SelectionPickerDialogState<T> extends State<_SelectionPickerDialog<T>> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<T> get _results {
    final String query = _query.text.trim().toUpperCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where((T option) {
          if (widget.optionLabel(option).toUpperCase().contains(query)) {
            return true;
          }
          final String? subtitle = widget.optionSubtitle?.call(option);
          return subtitle != null && subtitle.toUpperCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final List<T> results = _results;
    final String searchLabel = 'Search'.tr(context);
    final Color boxBorder = canvasBoxBorderColor(colors);
    final OutlineInputBorder searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: boxBorder),
    );
    return AlertDialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: boxBorder),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
      actionsAlignment: MainAxisAlignment.center,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.eyebrow != null) ...<Widget>[
            Text(
              widget.eyebrow!.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.35,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 5),
          ],
          Text(
            widget.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.6,
              height: 1.25,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 375,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.searchable) ...<Widget>[
              Text(
                searchLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 7),
              Semantics(
                label: searchLabel,
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurface,
                  ),
                  decoration: InputDecoration(
                    labelText: null,
                    hintText: widget.searchPlaceholder ?? searchLabel,
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: theme.brightness == Brightness.dark
                        ? colors.surfaceContainerLow
                        : colors.surfaceContainerLowest,
                    border: searchBorder,
                    enabledBorder: searchBorder,
                    focusedBorder: searchBorder.copyWith(
                      borderSide: BorderSide(color: colors.primary, width: 1.5),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: widget.optionSubtitle != null ? 318 : 342,
                ),
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 16,
                        ),
                        child: Text(
                          'No matching options.'.tr(context),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ClipRect(
                        child: Material(
                          type: MaterialType.transparency,
                          clipBehavior: Clip.hardEdge,
                          child: Scrollbar(
                            controller: _scroll,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: results.length,
                              itemBuilder: (BuildContext context, int index) {
                                final T option = results[index];
                                final bool isSelected =
                                    option == widget.selected;
                                final bool nextIsSelected =
                                    index + 1 < results.length &&
                                    results[index + 1] == widget.selected;
                                final bool showDivider =
                                    !isSelected &&
                                    !nextIsSelected &&
                                    index < results.length - 1;
                                final String? subtitle = widget.optionSubtitle
                                    ?.call(option);
                                final bool hasSubtitle =
                                    subtitle != null && subtitle.isNotEmpty;
                                final Widget tile = ListTile(
                                  minTileHeight: hasSubtitle ? 62 : 56,
                                  minLeadingWidth: 22,
                                  horizontalTitleGap: 12,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: hasSubtitle ? 3 : 0,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  selected: isSelected,
                                  selectedTileColor: colors.primaryContainer,
                                  leading: widget.optionIcon == null
                                      ? null
                                      : Icon(
                                          widget.optionIcon!(option),
                                          size: 20,
                                          color: colors.primary,
                                        ),
                                  title: Text(
                                    widget.optionLabel(option),
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  subtitle: !hasSubtitle
                                      ? null
                                      : Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            subtitle,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: colors.primary,
                                        )
                                      : null,
                                  onTap: () =>
                                      Navigator.of(context).pop(option),
                                );
                                if (!showDivider) return tile;
                                return DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: colors.outlineVariant,
                                      ),
                                    ),
                                  ),
                                  child: tile,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
              minimumSize: const Size.fromHeight(48),
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text('Close'.tr(context)),
          ),
        ),
      ],
    );
  }
}
