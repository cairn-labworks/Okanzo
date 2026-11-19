import 'dart:async';

import 'package:okanzo/util/biometric_authenticator.dart';

class FakeBiometricAuthenticator implements BiometricAuthenticator {
  BiometricCapability available = BiometricCapability.available;
  BiometricResult result = BiometricResult.cancelled;
  Completer<BiometricResult>? pending;
  final List<String> reasons = <String>[];

  @override
  Future<BiometricCapability> capability() async => available;

  @override
  Future<BiometricResult> authenticate({
    required String title,
    required String subtitle,
  }) async {
    reasons.add(subtitle);
    return pending == null ? result : pending!.future;
  }
}
