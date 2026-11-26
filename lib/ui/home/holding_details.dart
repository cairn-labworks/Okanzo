import 'package:flutter/material.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../l10n/app_localizations.dart';
import '../components/holding_editor_guard.dart';
import '../components/holding_glance_dialog.dart';

enum HoldingDetailsAction { edit, delete }

Future<HoldingDetailsAction?> showHoldingDetails(
  BuildContext context, {
  AssetEntity? asset,
  LiabilityEntity? liability,
  String? portfolioName,
  required bool hideBalances,
  String? baseCurrency,
  double? convertedValue,
  double? portfolioSectionTotal,
}) async {
  assert((asset == null) != (liability == null));
  final bool isAsset = asset != null;
  final HoldingDetailsAction? action = await showDialog<HoldingDetailsAction>(
    context: context,
    barrierColor: holdingGlanceBarrierColor(context),
    builder: (BuildContext context) {
      final ThemeData theme = Theme.of(context);
      final ColorScheme colors = theme.colorScheme;
      final Color dangerBorder = colors.error.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.65 : 0.55,
      );
      return HoldingGlanceDialog(
        asset: asset,
        liability: liability,
        portfolioName: portfolioName,
        hideBalances: hideBalances,
        baseCurrency: baseCurrency,
        convertedValue: convertedValue,
        portfolioSectionTotal: portfolioSectionTotal,
        closeKey: const ValueKey<String>('close-holding-details'),
        primaryLabel: (isAsset ? 'Edit asset' : 'Edit liability').tr(context),
        onPrimary: () => Navigator.of(context).pop(HoldingDetailsAction.edit),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: colors.outlineVariant),
          ),
          OutlinedButton(
            key: const ValueKey<String>('delete-holding-button'),
            onPressed: () =>
                Navigator.of(context).pop(HoldingDetailsAction.delete),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 50),
              backgroundColor: colors.surfaceContainerLow,
              foregroundColor: colors.error,
              side: BorderSide(color: dangerBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: Text(
              (isAsset ? 'Delete asset' : 'Delete liability').tr(context),
            ),
          ),
        ],
      );
    },
  );
  if (!context.mounted || action != HoldingDetailsAction.delete) return action;
  return await confirmHoldingDeletion(
        context,
        asset?.displayName ?? liability!.name,
        asset: isAsset,
        portfolioName: portfolioName,
      )
      ? HoldingDetailsAction.delete
      : null;
}
