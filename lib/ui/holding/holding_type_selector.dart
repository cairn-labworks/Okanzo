import 'package:flutter/material.dart';

import '../../domain/model/holding_type.dart';
import '../../l10n/app_localizations.dart';
import '../components/form_components.dart';
import '../components/type_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_style.dart';
import '../theme/colors.dart';
import '../theme/theme.dart';

/// Compact type selector covering all asset and liability categories.
class HoldingTypeSelector extends StatelessWidget {
  const HoldingTypeSelector({
    required this.selected,
    required this.onSelected,
    this.supportingText,
    this.canvas = false,
    this.enabled = true,
    super.key,
  });

  final HoldingType selected;
  final ValueChanged<HoldingType> onSelected;
  final String? supportingText;
  final bool canvas;
  final bool enabled;

  Future<void> _openSheet(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final HoldingType? chosen = await showHoldingTypePickerSheet(
      context,
      selected: selected,
    );
    if (chosen != null && context.mounted) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final String label = selected.pickerLabel.tr(context);
    final IconData icon = selected.isAsset
        ? assetTypeIcon(selected.assetType!)
        : liabilityTypeIcon(selected.liabilityType!);
    return Tooltip(
      message: '${'Type'.tr(context)}: $label',
      child: PickerChip(
        buttonKey: const ValueKey<String>('holding-type-chip'),
        fieldLabel: canvas ? 'Type'.tr(context) : null,
        supportingText: canvas ? supportingText : null,
        icon: icon,
        label: label,
        onPressed: enabled ? () => _openSheet(context) : null,
      ),
    );
  }
}

Future<HoldingType?> showHoldingTypePickerSheet(
  BuildContext context, {
  required HoldingType selected,
}) {
  return showModalBottomSheet<HoldingType>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) =>
        _HoldingTypePickerSheet(selected: selected),
  );
}

class _HoldingTypePickerSheet extends StatelessWidget {
  const _HoldingTypePickerSheet({required this.selected});

  final HoldingType selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FinanceColors finance = FinanceColors.of(context);
    final bool colorful = AppStyle.of(context).colorfulCategories;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.82;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Choose type'.tr(context),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Asset or liability is detected automatically'.tr(context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              key: const ValueKey<String>('holding-type-list'),
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                _TypeSectionHeader(
                  icon: Icons.trending_up,
                  accent: finance.positive,
                  label: 'Assets'.tr(context),
                ),
                for (final HoldingType option in HoldingType.assetTypes)
                  _TypeOptionRow(
                    key: ValueKey<HoldingType>(option),
                    icon: assetTypeIcon(option.assetType!),
                    accent: colorful
                        ? categoryColorAt(option.assetType!.index)
                        : null,
                    label: option.pickerLabel.tr(context),
                    subtitle: option.pickerHint.tr(context),
                    selected: option == selected,
                    onTap: () => Navigator.of(context).pop(option),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Divider(height: 1),
                ),
                _TypeSectionHeader(
                  icon: Icons.trending_down,
                  accent: finance.negative,
                  label: 'Liabilities'.tr(context),
                ),
                for (final HoldingType option in HoldingType.liabilityTypes)
                  _TypeOptionRow(
                    key: ValueKey<HoldingType>(option),
                    icon: liabilityTypeIcon(option.liabilityType!),
                    accent: colorful
                        ? categoryColorAt(option.liabilityType!.index + 5)
                        : null,
                    label: option.pickerLabel.tr(context),
                    subtitle: option.pickerHint.tr(context),
                    selected: option == selected,
                    onTap: () => Navigator.of(context).pop(option),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeSectionHeader extends StatelessWidget {
  const _TypeSectionHeader({
    required this.icon,
    required this.accent,
    required this.label,
  });

  final IconData icon;
  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: accent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeOptionRow extends StatelessWidget {
  const _TypeOptionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.accent,
    super.key,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        button: true,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 2,
          ),
          selected: selected,
          selectedTileColor: colors.primaryContainer.withValues(alpha: 0.45),
          leading: ExcludeSemantics(
            child: TypeAvatar(icon, accent: accent, size: 32),
          ),
          title: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          trailing: selected
              ? ExcludeSemantics(
                  child: Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                )
              : null,
          onTap: onTap,
        ),
      ),
    );
  }
}
