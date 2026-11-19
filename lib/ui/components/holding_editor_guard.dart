import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

Future<bool> confirmHoldingDeletion(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Delete holding?'.tr(context)),
        content: Text(
          'Remove {name} from this portfolio?'
              .tr(context)
              .replaceAll('{name}', name),
        ),
        actions: <Widget>[
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'.tr(context)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text('Delete'.tr(context)),
          ),
        ],
      ),
    ) ??
    false;

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

  Future<void> close() async {
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
    if (mounted) Navigator.of(context).pop();
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
