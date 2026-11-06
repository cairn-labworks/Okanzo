import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Full-screen gate shown while the app is locked.
class LockScreen extends StatefulWidget {
  const LockScreen({required this.onUnlock, super.key});

  final Future<void> Function() onUnlock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Prompt automatically the first time the lock screen appears.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onUnlock());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outlined,
                  size: 44,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  'Okanzo is locked'.tr(context),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Unlock with your fingerprint or device PIN to view your '
                          'net worth.'
                      .tr(context),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: FilledButton.icon(
                  onPressed: () => widget.onUnlock(),
                  icon: const Icon(Icons.fingerprint, size: 20),
                  label: Text('Unlock'.tr(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
