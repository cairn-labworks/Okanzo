import 'package:flutter/foundation.dart';

import 'biometric_authenticator.dart';

class AppLockCoordinator extends ChangeNotifier {
  AppLockCoordinator({
    required BiometricAuthenticator authenticator,
    DateTime Function()? now,
  }) : _authenticator = authenticator,
       _now = now ?? DateTime.now;

  final BiometricAuthenticator _authenticator;
  final DateTime Function() _now;
  bool _unlocked = false;
  bool _authenticating = false;
  _PickerHandoff? _picker;
  _PickerHandoff? _pausedPicker;

  bool get unlocked => _unlocked;
  bool get authenticating => _authenticating;

  void markUnlocked() {
    _unlocked = true;
    notifyListeners();
  }

  void lock() {
    _unlocked = false;
    notifyListeners();
  }

  Future<BiometricResult> authenticate({
    required String title,
    required String subtitle,
  }) async {
    if (_authenticating) return BiometricResult.cancelled;
    _authenticating = true;
    try {
      switch (await _authenticator.capability()) {
        case BiometricCapability.notEnrolled:
          return BiometricResult.notEnrolled;
        case BiometricCapability.unavailable:
          return BiometricResult.unavailable;
        case BiometricCapability.available:
          return await _authenticator.authenticate(
            title: title,
            subtitle: subtitle,
          );
      }
    } finally {
      _authenticating = false;
    }
  }

  Future<T> withFilePicker<T>(Future<T> Function() action) async {
    final _PickerHandoff handoff = _PickerHandoff(_now());
    _picker = handoff;
    try {
      return await action();
    } finally {
      if (identical(_picker, handoff)) _picker = null;
    }
  }

  bool deferPickerPause() {
    final _PickerHandoff? picker = _picker;
    if (picker == null ||
        picker.used ||
        _now().difference(picker.started) > const Duration(seconds: 60)) {
      return false;
    }
    picker.used = true;
    picker.paused = _now();
    _pausedPicker = picker;
    return true;
  }

  bool consumeExpiredPickerPause() {
    final _PickerHandoff? picker = _pausedPicker;
    _pausedPicker = null;
    return picker != null &&
        _now().difference(picker.paused!) > const Duration(seconds: 60);
  }
}

class _PickerHandoff {
  _PickerHandoff(this.started);

  final DateTime started;
  DateTime? paused;
  bool used = false;
}
