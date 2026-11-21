import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../data/local/entity/asset_entity.dart';
import '../../data/local/entity/liability_entity.dart';
import '../../di/app_container.dart';
import '../../l10n/app_localizations.dart';
import 'form_components.dart';
import 'holding_create_screen.dart';
import 'holding_glance_dialog.dart';

DialogRoute<void> holdingSavedSummaryRoute(
  BuildContext context, {
  required WidgetBuilder builder,
}) => DialogRoute<void>(
  context: context,
  builder: builder,
  barrierColor: holdingGlanceBarrierColor(context),
  themes: InheritedTheme.capture(
    from: context,
    to: Navigator.of(context).context,
  ),
);

class HoldingSavedSummaryScreen extends StatefulWidget {
  const HoldingSavedSummaryScreen({
    required this.portfolioId,
    required this.updated,
    this.savedAsset,
    this.previousAsset,
    this.savedLiability,
    this.previousLiability,
    this.notice,
    super.key,
  }) : assert((savedAsset == null) != (savedLiability == null));

  final int portfolioId;
  final bool updated;
  final AssetEntity? savedAsset;
  final AssetEntity? previousAsset;
  final LiabilityEntity? savedLiability;
  final LiabilityEntity? previousLiability;
  final String? notice;

  @override
  State<HoldingSavedSummaryScreen> createState() =>
      _HoldingSavedSummaryScreenState();
}

class _HoldingSavedSummaryScreenState extends State<HoldingSavedSummaryScreen> {
  bool _busy = false;
  bool _undoFailed = false;

  Future<void> _undo() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _undoFailed = false;
    });
    final AppContainer container = AppScope.of(context);
    try {
      if (widget.savedAsset case final AssetEntity saved) {
        if (widget.previousAsset case final AssetEntity previous) {
          await container.assetRepository.save(previous);
        } else {
          await container.assetRepository.delete(saved.id);
        }
      } else {
        if (widget.previousLiability case final LiabilityEntity previous) {
          await container.liabilityRepository.save(previous);
        } else {
          await container.liabilityRepository.delete(widget.savedLiability!.id);
        }
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _undoFailed = true;
      });
      return;
    }
    if (!mounted) return;
    final String message =
        (widget.updated ? 'Update undone.' : 'Addition undone.').tr(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addAnotherHolding() async {
    if (_busy) return;
    final bool? asset = await showDialog<bool>(
      context: context,
      barrierColor: holdingGlanceBarrierColor(context),
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        final ColorScheme colors = theme.colorScheme;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: AlertDialog(
            scrollable: true,
            backgroundColor: colors.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: canvasBoxBorderColor(colors)),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Add holding'.tr(context).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.35,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'What would you like to add?'.tr(context),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.6,
                    height: 1.25,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 375,
              child: Column(
                children: <Widget>[
                  _HoldingKindChoiceCard(
                    icon: Icons.trending_up,
                    title: 'An asset'.tr(context),
                    subtitle: 'Something you own'.tr(context),
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: 10),
                  _HoldingKindChoiceCard(
                    icon: Icons.trending_down,
                    title: 'A liability'.tr(context),
                    subtitle: 'Something you owe'.tr(context),
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: colors.onSurfaceVariant,
                  minimumSize: const Size(double.infinity, 44),
                ),
                child: Text('Close'.tr(context)),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || asset == null) return;
    final int portfolioId = widget.portfolioId;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              HoldingCreateScreen(portfolioId: portfolioId, asset: asset),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool hideBalances = AppScope.of(context)
        .settingsRepository
        .current
        .hideBalances;
    final bool priced = widget.savedAsset?.isPriced ?? true;
    final String status = switch ((widget.savedAsset != null, widget.updated)) {
      (true, false) => 'Asset added.',
      (true, true) => 'Asset updated.',
      (false, false) => 'Liability added.',
      (false, true) => 'Liability updated.',
    };
    final String? notice = widget.notice?.trim();
    return PopScope<void>(
      canPop: !_busy,
      child: HoldingGlanceDialog(
        asset: widget.savedAsset,
        liability: widget.savedLiability,
        hideBalances: hideBalances,
        status: status.tr(context),
        notice: !priced || (notice?.isNotEmpty ?? false)
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Saved without a latest price.'.tr(context),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        (notice == null || notice.isEmpty
                                ? 'This asset is excluded until it has a price.'
                                : notice)
                            .tr(context),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        canClose: !_busy,
        closeKey: const ValueKey<String>('close-saved-holding'),
        primaryKey: const ValueKey<String>('back-to-portfolio'),
        primaryLabel: 'Back to portfolio'.tr(context),
        onPrimary: _busy ? null : () => Navigator.of(context).pop(),
        actions: <Widget>[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey<String>('add-another-holding'),
            onPressed: _busy ? null : _addAnotherHolding,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 50),
              backgroundColor: colors.surfaceContainerLow,
              foregroundColor: colors.onSurface,
              side: BorderSide(color: colors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text('Add another holding'.tr(context)),
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const ValueKey<String>('undo-saved-holding'),
            onPressed: _busy ? null : _undo,
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
              minimumSize: const Size(double.infinity, 44),
            ),
            child: Text(
              (widget.updated ? 'Undo this update' : 'Undo this addition').tr(
                context,
              ),
            ),
          ),
          if (_undoFailed)
            Semantics(
              liveRegion: true,
              child: Text(
                'Could not undo this change.'.tr(context),
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _HoldingKindChoiceCard extends StatelessWidget {
  const _HoldingKindChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: colors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
