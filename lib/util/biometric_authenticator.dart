import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

/// Result of querying whether the device can perform an app-lock challenge.
enum BiometricCapability {
  /// Fingerprint / face / device PIN is available and can be used.
  available,

  /// Hardware exists but no biometric or device credential is enrolled.
  notEnrolled,

  /// The device cannot authenticate the user at all.
  unavailable,
}

/// Thin wrapper over `local_auth` mirroring the Android BiometricPrompt flow:
/// biometrics *or* the device credential (PIN/pattern/passcode) unlock the app.
enum BiometricResult {
  success,
  cancelled,
  notEnrolled,
  unavailable,
  failed;

  String? get message => switch (this) {
    notEnrolled =>
      'Set up a screen lock or fingerprint in system settings first',
    unavailable => "This device can't authenticate you",
    failed => 'Authentication failed',
    success || cancelled => null,
  };
}

abstract interface class BiometricAuthenticator {
  Future<BiometricCapability> capability();

  Future<BiometricResult> authenticate({
    required String title,
    required String subtitle,
  });
}

class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Mirrors `BiometricManager.canAuthenticate(BIOMETRIC_WEAK or
  /// DEVICE_CREDENTIAL)`: a device secured with a PIN/pattern/passcode or with
  /// enrolled biometrics can run the challenge.
  @override
  Future<BiometricCapability> capability() async {
    try {
      if (await _auth.isDeviceSupported()) return BiometricCapability.available;
      if (await _auth.canCheckBiometrics) {
        return BiometricCapability.notEnrolled;
      }
      return BiometricCapability.unavailable;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          BiometricCapability.notEnrolled,
        _ => BiometricCapability.unavailable,
      };
    }
  }

  @override
  Future<BiometricResult> authenticate({
    required String title,
    required String subtitle,
  }) async {
    try {
      final bool ok = await _auth.authenticate(
        localizedReason: subtitle,
        authMessages: <AuthMessages>[
          AndroidAuthMessages(signInTitle: title),
          const IOSAuthMessages(),
        ],
        persistAcrossBackgrounding: false,
      );
      return ok ? BiometricResult.success : BiometricResult.cancelled;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled => BiometricResult.cancelled,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          BiometricResult.notEnrolled,
        LocalAuthExceptionCode.noBiometricHardware =>
          BiometricResult.unavailable,
        _ => _failure(error),
      };
    }
  }

  BiometricResult _failure(LocalAuthException error) {
    debugPrint('Device authentication failed: ${error.code.name}');
    return BiometricResult.failed;
  }
}
