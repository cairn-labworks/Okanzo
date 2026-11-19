import 'package:flutter/material.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/holding_editor_guard.dart';
import 'category_groups.dart';

enum HoldingDetailsAction { edit, delete }

Future<HoldingDetailsAction?> showHoldingDetails(
  BuildContext context, {
  AssetEntity? asset,
  LiabilityEntity? liability,
  required bool hideBalances,
}) async {
  assert((asset == null) != (liability == null));
  final String name = asset?.displayName ?? liability!.name;
  final String currency = asset?.currency ?? liability!.currency;
  String money(double value) => hideBalances
      ? CurrencyUtil.maskShort
      : CurrencyUtil.format(value, currency);
  String quantity(double value) =>
      hideBalances ? CurrencyUtil.maskShort : formatQuantity(value);
  final Map<String, String> rows = <String, String>{
    'Type': (asset?.type.displayName ?? liability!.type.displayName).tr(
      context,
    ),
    'Currency': currency,
    'Value': money(asset?.value ?? liability!.value),
    if (asset?.symbol != null) 'Ticker symbol': asset!.symbol!,
    if (asset?.quantity != null) 'Quantity': quantity(asset!.quantity!),
    if (asset?.lastPrice != null) 'Price': money(asset!.lastPrice!),
    if (asset?.pricePerUnit != null)
      'Price per {unit}'
          .tr(context)
          .replaceAll('{unit}', asset!.type.unitLabel ?? ''): money(
        asset.pricePerUnit!,
      ),
    if ((asset?.notes ?? liability?.notes)?.isNotEmpty ?? false)
      'Notes (optional)': (asset?.notes ?? liability!.notes)!,
  };
  final HoldingDetailsAction? action = await showDialog<HoldingDetailsAction>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(name),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final entry in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.key.tr(context),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(entry.value),
                ],
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close'.tr(context)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(HoldingDetailsAction.delete),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text('Delete'.tr(context)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(HoldingDetailsAction.edit),
          child: Text(
            (asset != null ? 'Edit asset' : 'Edit liability').tr(context),
          ),
        ),
      ],
    ),
  );
  if (!context.mounted || action != HoldingDetailsAction.delete) return action;
  return await confirmHoldingDeletion(context, name)
      ? HoldingDetailsAction.delete
      : null;
}
