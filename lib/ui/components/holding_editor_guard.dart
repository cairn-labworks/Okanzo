import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'form_components.dart';

Future<bool> confirmHoldingDeletion(
  BuildContext context,
  String name, {
  bool? asset,
  String? portfolioName,
}) async {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return await showDialog<bool>(
        context: context,
        barrierColor: dark ? const Color(0xAA10231B) : const Color(0x7310231B),
        builder: (BuildContext context) {
          final ThemeData theme = Theme.of(context);
          final ColorScheme colors = theme.colorScheme;
          final Color boxBorder = canvasBoxBorderColor(colors);
          final Color dangerBorder = colors.error.withValues(
            alpha: dark ? 0.65 : 0.55,
          );
          final String eyebrow = asset == null
              ? 'Delete holding'.tr(context)
              : (asset ? 'Delete asset' : 'Delete liability').tr(context);
          final String body = portfolioName != null && portfolioName.isNotEmpty
              ? '{name} will be removed from {portfolio}.'
                    .tr(context)
                    .replaceAll('{name}', name)
                    .replaceAll('{portfolio}', portfolioName)
              : 'Remove {name} from this portfolio?'
                    .tr(context)
                    .replaceAll('{name}', name);
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: AlertDialog(
              backgroundColor: colors.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: boxBorder),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    eyebrow.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.35,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Delete holding?'.tr(context),
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
                child: Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13.5,
                    height: 1.55,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              actions: <Widget>[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FilledButton(
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(false),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text('Cancel'.tr(context)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: const ValueKey<String>('confirm-delete-button'),
                      onPressed: () => Navigator.of(context).pop(true),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 50),
                        backgroundColor: colors.surfaceContainerLow,
                        foregroundColor: colors.error,
                        side: BorderSide(color: dangerBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text('Delete'.tr(context)),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ) ??
      false;
}

class HoldingEditorGuard extends StatefulWidget {
  const HoldingEditorGuard({
    required this.dirty,
    required this.onDiscard,
    required this.child,
    super.key,
  });

  final bool dirty;
  final VoidCallback onDiscard;
  final Widget child;

  @override
  State<HoldingEditorGuard> createState() => HoldingEditorGuardState();
}

class HoldingEditorGuardState extends State<HoldingEditorGuard> {
  bool _leaving = false;
  bool _confirming = false;
  DialogRoute<bool>? _confirmationRoute;

  Future<void> close({Route<void>? replacement}) async {
    if (_leaving) return;
    final DialogRoute<bool>? confirmation = _confirmationRoute;
    if (confirmation != null && confirmation.isActive) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).removeRoute(confirmation, false);
    }
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (replacement != null) {
      unawaited(Navigator.of(context).pushReplacement(replacement));
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onBack() async {
    if (_confirming) return;
    _confirming = true;
    final DialogRoute<bool> route = DialogRoute<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Discard changes?'.tr(context)),
        content: Text('This holding has not been saved.'.tr(context)),
        actions: <Widget>[
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep editing'.tr(context)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Discard'.tr(context)),
          ),
        ],
      ),
    );
    _confirmationRoute = route;
    final bool discard =
        await Navigator.of(context, rootNavigator: true).push(route) ?? false;
    _confirmationRoute = null;
    _confirming = false;
    if (!mounted || !discard) return;
    widget.onDiscard();
    await close();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !widget.dirty || _leaving,
    onPopInvokedWithResult: (bool didPop, _) {
      if (!didPop) _onBack();
    },
    child: widget.child,
  );
}
