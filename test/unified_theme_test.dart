import 'package:flutter_test/flutter_test.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/domain/model/app_theme.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Preferences extends Fake implements SharedPreferences {
  _Preferences(
    Map<String, String> values, {
    this.failKey,
    this.throwOnFailure = false,
  }) : stored = Map<String, String>.of(values),
       cache = Map<String, String>.of(values);

  final Map<String, String> stored;
  final Map<String, String> cache;
  String? failKey;
  final bool throwOnFailure;
  int reloads = 0;

  @override
  String? getString(String key) => cache[key];
  @override
  bool? getBool(String key) => null;
  @override
  int? getInt(String key) => null;
  @override
  List<String>? getStringList(String key) => null;

  @override
  Future<bool> setString(String key, String value) async {
    cache[key] = value;
    if (key == failKey) {
      failKey = null;
      if (throwOnFailure) throw StateError('Storage unavailable');
      return false;
    }
    stored[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    cache.remove(key);
    stored.remove(key);
    return true;
  }

  @override
  Future<void> reload() async {
    reloads++;
    cache
      ..clear()
      ..addAll(stored);
  }
}

void main() {
  test('legacy Midnight remains dark despite an older light/system value', () {
    for (final AppThemeMode mode in AppThemeMode.values) {
      expect(
        AppSettings(
          baseCurrency: 'USD',
          appTheme: AppTheme.midnight,
          themeMode: mode,
        ).appearanceMode,
        AppThemeMode.dark,
      );
      expect(
        AppSettings(baseCurrency: 'USD', themeMode: mode).appearanceMode,
        mode,
      );
    }
  });

  for (final AppThemeMode mode in AppThemeMode.values) {
    test(
      '$mode saves one coherent appearance and survives reopening',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'app_theme': 'MIDNIGHT',
          'theme_mode': 'LIGHT',
          'base_currency': 'INR',
          'dynamic_color': true,
          'hide_balances': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final repository = SettingsRepository(prefs);
        addTearDown(repository.dispose);
        final List<AppSettings> changes = <AppSettings>[];
        final subscription = repository.settings.listen(changes.add);
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);
        await repository.setAppearanceMode(mode);
        await Future<void>.delayed(Duration.zero);
        expect(changes, hasLength(2));
        expect(changes.last.appearanceMode, mode);
        final reopened = SettingsRepository(prefs);
        addTearDown(reopened.dispose);
        expect(reopened.current.appearanceMode, mode);
        expect(
          reopened.current.appTheme,
          mode == AppThemeMode.dark ? AppTheme.midnight : AppTheme.classic,
        );
        expect(reopened.current.themeMode, mode);
        expect(reopened.current.baseCurrency, 'INR');
        expect(reopened.current.dynamicColor, isTrue);
        expect(reopened.current.hideBalances, isTrue);
      },
    );
  }

  for (final String failedKey in <String>['theme_mode', 'app_theme']) {
    for (final bool throws in <bool>[false, true]) {
      test(
        '$failedKey write failure restores both appearance keys (throws=$throws)',
        () async {
          final original = <String, String>{
            'theme_mode': 'LIGHT',
            'app_theme': 'CLASSIC',
            'base_currency': 'USD',
          };
          final prefs = _Preferences(
            original,
            failKey: failedKey,
            throwOnFailure: throws,
          );
          final repository = SettingsRepository(prefs);
          addTearDown(repository.dispose);
          final List<AppSettings> changes = <AppSettings>[];
          final subscription = repository.settings.listen(changes.add);
          addTearDown(subscription.cancel);
          await Future<void>.delayed(Duration.zero);
          await expectLater(
            repository.setAppearanceMode(AppThemeMode.dark),
            throwsStateError,
          );
          await Future<void>.delayed(Duration.zero);
          expect(prefs.stored, original);
          expect(prefs.cache, original);
          expect(prefs.reloads, 1);
          expect(repository.current.appearanceMode, AppThemeMode.light);
          expect(changes, hasLength(1));
        },
      );
    }
  }
}
