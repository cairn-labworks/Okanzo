import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/helpers/device_test_cleanup.dart';

class _Preferences extends Fake implements SharedPreferences {
  _Preferences(
    Map<String, Object> values, {
    this.failedKey,
    this.throwOnWrite = false,
  }) : stored = Map<String, Object>.of(values);

  final Map<String, Object> stored;
  final String? failedKey;
  final bool throwOnWrite;

  Future<bool> _write(String key, Object? value) async {
    if (key == failedKey) {
      if (throwOnWrite) throw StateError('Storage unavailable');
      return false;
    }
    if (value == null) {
      stored.remove(key);
    } else {
      stored[key] = value;
    }
    return true;
  }

  @override
  Future<bool> setString(String key, String value) => _write(key, value);

  @override
  Future<bool> setBool(String key, bool value) => _write(key, value);

  @override
  Future<bool> remove(String key) => _write(key, null);
}

void main() {
  test(
    'cleanup restores protections despite UI and fixture failures',
    () async {
      final preferences = _Preferences(<String, Object>{
        'app_lock_enabled': false,
        'block_screenshots': false,
        'app_theme': 'LIQUID_GLASS',
      });
      const original = <String, Object>{
        'app_lock_enabled': true,
        'block_screenshots': true,
        'app_theme': 'SCULPTED',
      };
      bool nativeProtection = false;
      bool databaseClosed = false;

      await expectLater(
        runDeviceTestCleanup(<DeviceTestCleanupStep>[
          ('restore native protection', () async => nativeProtection = true),
          for (final entry in original.entries)
            (
              'restore ${entry.key}',
              () => restoreDeviceTestPreference(
                preferences,
                entry.key,
                entry.value,
              ),
            ),
          ('unmount', () async => throw StateError('UI settling failed')),
          ('fixture', () async => throw StateError('Fixture deletion failed')),
          ('close database', () async => databaseClosed = true),
        ]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'failures',
            allOf(contains('unmount'), contains('fixture')),
          ),
        ),
      );
      expect(nativeProtection, isTrue);
      expect(preferences.stored, original);
      expect(databaseClosed, isTrue);
    },
  );

  for (final bool throws in <bool>[false, true]) {
    test(
      'cleanup continues after native and preference restore failures (throws=$throws)',
      () async {
        final preferences = _Preferences(
          <String, Object>{
            'app_theme': 'LIQUID_GLASS',
            'app_lock_enabled': false,
            'last_seen_version': '1.7.0',
          },
          failedKey: 'app_theme',
          throwOnWrite: throws,
        );
        const original = <String, Object?>{
          'app_theme': 'SCULPTED',
          'app_lock_enabled': true,
          'last_seen_version': null,
        };
        bool databaseClosed = false;

        await expectLater(
          runDeviceTestCleanup(<DeviceTestCleanupStep>[
            (
              'restore native protection',
              () async => throw StateError('Native protection unavailable'),
            ),
            for (final entry in original.entries)
              (
                'restore ${entry.key}',
                () => restoreDeviceTestPreference(
                  preferences,
                  entry.key,
                  entry.value,
                ),
              ),
            ('close database', () async => databaseClosed = true),
          ]),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'failures',
              allOf(
                contains('restore native protection'),
                contains('restore app_theme'),
              ),
            ),
          ),
        );
        expect(preferences.stored['app_lock_enabled'], isTrue);
        expect(preferences.stored.containsKey('last_seen_version'), isFalse);
        expect(databaseClosed, isTrue);
      },
    );
  }
}
