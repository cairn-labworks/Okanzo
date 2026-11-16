import 'package:flutter/services.dart';

/// Syncs Android's `FLAG_SECURE` window flag through `MainActivity`.
///
/// Platforms or test harnesses without a window-flag handler ignore
/// [MissingPluginException]; native failures surface as [PlatformException].
class ScreenshotProtection {
  const ScreenshotProtection._();

  static const MethodChannel channel = MethodChannel(
    'com.cairnlabworks.okanzo/security',
  );

  static Future<void> setEnabled(bool enabled) async {
    try {
      final bool? applied = await channel.invokeMethod<bool>(
        'setScreenshotProtection',
        enabled,
      );
      if (applied == false) {
        throw PlatformException(
          code: 'SCREENSHOT_PROTECTION_FAILED',
          message: 'Screenshot protection could not be updated',
        );
      }
    } on MissingPluginException {
      // Non-Android platforms and headless widget tests have no window flag.
    }
  }
}
