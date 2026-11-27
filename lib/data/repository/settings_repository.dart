import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/model/app_language.dart';
import '../../domain/model/app_theme.dart';
import '../../domain/model/release_notes.dart';
import '../../domain/model/stock_exchange.dart';
import '../../domain/model/theme_mode.dart';
import '../../util/currency_util.dart';
import '../../util/screenshot_protection.dart';

/// All user-facing app preferences.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.appTheme = AppTheme.classic,
    required this.baseCurrency,
    this.appLockEnabled = false,
    this.blockScreenshots = true,
    this.hideBalances = false,
    this.simpleNetWorth = false,
    this.selectedPortfolioId,
    this.preferredExchanges = const <StockExchange>[StockExchange.us],
    this.language = AppLanguage.system,
    this.lastSeenVersion,
  });

  final AppThemeMode themeMode;
  final AppTheme appTheme;
  final String baseCurrency;
  final bool appLockEnabled;
  final bool blockScreenshots;
  final bool hideBalances;
  final bool simpleNetWorth;
  final int? selectedPortfolioId;
  final List<StockExchange> preferredExchanges;
  final AppLanguage language;
  final String? lastSeenVersion;

  /// Midnight was previously selectable independently of light/dark mode.
  AppThemeMode get appearanceMode =>
      appTheme == AppTheme.midnight ? AppThemeMode.dark : themeMode;

  AppTheme get themeStyle =>
      appTheme == AppTheme.midnight ? AppTheme.classic : appTheme;
}

/// Section names used when persisting a portfolio's custom category order.
class CategorySection {
  const CategorySection._();

  static const String asset = 'asset';
  static const String liability = 'liability';
}

/// Reads and writes app preferences, mirroring the Android DataStore keys so an
/// existing installation's semantics are preserved.
class SettingsRepository {
  SettingsRepository(this._prefs);

  static const String _keyThemeMode = 'theme_mode';
  static const String _keyAppTheme = 'app_theme';
  static const String _keyBaseCurrency = 'base_currency';
  static const String _keyAppLock = 'app_lock_enabled';
  static const String _keyBlockScreenshots = 'block_screenshots';
  static const String _keyHideBalances = 'hide_balances';
  static const String _keySimpleNetWorth = 'simple_net_worth';
  static const String _keyPreferredExchanges = 'preferred_stock_exchanges';
  static const String _keyLanguage = 'app_language';
  static const String _keyLastSeenVersion = 'last_seen_version';
  final SharedPreferences _prefs;
  // SharedPreferences updates its cache before confirming a write.
  bool? _blockScreenshots;
  bool? _simpleNetWorth;
  int? _selectedPortfolioId;
  List<String>? _cachedExchangeNames;
  List<StockExchange>? _cachedPreferredExchanges;
  Future<void>? _appearanceWrite;
  final StreamController<AppSettings> _controller =
      StreamController<AppSettings>.broadcast();

  /// Emits the current settings immediately and again after every change.
  Stream<AppSettings> get settings async* {
    yield current;
    yield* _controller.stream;
  }

  AppSettings get current => AppSettings(
    themeMode: AppThemeMode.fromName(_prefs.getString(_keyThemeMode)),
    appTheme: AppTheme.fromName(_prefs.getString(_keyAppTheme)),
    baseCurrency:
        _prefs.getString(_keyBaseCurrency) ?? CurrencyUtil.deviceCurrencyCode(),
    appLockEnabled: _prefs.getBool(_keyAppLock) ?? false,
    blockScreenshots: _blockScreenshots ??=
        _prefs.getBool(_keyBlockScreenshots) ?? true,
    hideBalances: _prefs.getBool(_keyHideBalances) ?? false,
    simpleNetWorth: _simpleNetWorth ??=
        _prefs.getBool(_keySimpleNetWorth) ?? false,
    selectedPortfolioId: _selectedPortfolioId,
    preferredExchanges: _preferredExchanges,
    language: AppLanguage.fromName(_prefs.getString(_keyLanguage)),
    lastSeenVersion: _prefs.getString(_keyLastSeenVersion),
  );

  Future<void> setLastSeenVersion(String version) async {
    final String normalized = AppReleaseNotes.normalizeVersion(version);
    if (normalized.isEmpty) {
      throw ArgumentError.value(version, 'version', 'Must not be empty');
    }
    bool saved = false;
    try {
      saved = await _prefs.setString(_keyLastSeenVersion, normalized);
      if (!saved) {
        throw StateError('Last seen version could not be saved');
      }
    } finally {
      if (!saved) await _prefs.reload();
    }
    _emit();
  }

  List<StockExchange> get _preferredExchanges {
    final List<String>? stored = _prefs.getStringList(_keyPreferredExchanges);
    if (stored == null) return const <StockExchange>[StockExchange.us];
    if (_cachedPreferredExchanges != null &&
        listEquals(stored, _cachedExchangeNames)) {
      return _cachedPreferredExchanges!;
    }
    _cachedExchangeNames = List<String>.of(stored, growable: false);
    return _cachedPreferredExchanges = List<StockExchange>.unmodifiable(
      StockExchange.values.where(
        (StockExchange exchange) => stored.contains(exchange.name),
      ),
    );
  }

  Future<void> setPreferredExchanges(List<StockExchange> exchanges) async {
    final bool saved = await _prefs.setStringList(
      _keyPreferredExchanges,
      <String>[
        for (final StockExchange exchange in StockExchange.values)
          if (exchanges.contains(exchange)) exchange.name,
      ],
    );
    if (!saved) throw StateError('Exchange preferences could not be saved');
    _emit();
  }

  Future<void> setLanguage(AppLanguage language) async {
    bool saved = false;
    try {
      saved = language == AppLanguage.system
          ? await _prefs.remove(_keyLanguage)
          : await _prefs.setString(_keyLanguage, language.storageName);
      if (!saved) {
        throw StateError('App language preference could not be saved');
      }
    } finally {
      if (!saved) await _prefs.reload();
    }
    _emit();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    await _prefs.setString(_keyThemeMode, mode.storageName);
    _emit();
  }

  Future<void> setAppTheme(AppTheme theme) => _updateAppearance(() {
    final AppThemeMode mode = theme == AppTheme.midnight
        ? AppThemeMode.dark
        : current.appearanceMode;
    return (
      mode,
      theme == AppTheme.classic && mode == AppThemeMode.dark
          ? AppTheme.midnight
          : theme,
    );
  });

  Future<void> setAppearanceMode(AppThemeMode mode) => _updateAppearance(() {
    final AppTheme theme = current.themeStyle;
    return (
      mode,
      theme == AppTheme.classic && mode == AppThemeMode.dark
          ? AppTheme.midnight
          : theme,
    );
  });

  Future<void> _updateAppearance(
    (AppThemeMode, AppTheme) Function() choose,
  ) async {
    final Future<void>? previous = _appearanceWrite;
    final Completer<void> completed = Completer<void>();
    _appearanceWrite = completed.future;
    try {
      if (previous != null) await previous;
      final (AppThemeMode mode, AppTheme theme) = choose();
      await _saveAppearance(mode, theme);
    } finally {
      completed.complete();
      if (identical(_appearanceWrite, completed.future)) {
        _appearanceWrite = null;
      }
    }
  }

  Future<void> _saveAppearance(AppThemeMode mode, AppTheme theme) async {
    final Map<String, String?> original = <String, String?>{
      _keyThemeMode: _prefs.getString(_keyThemeMode),
      _keyAppTheme: _prefs.getString(_keyAppTheme),
    };
    bool saved = false;
    try {
      if (!await _prefs.setString(_keyThemeMode, mode.storageName) ||
          !await _prefs.setString(_keyAppTheme, theme.storageName)) {
        throw StateError('Theme preference could not be saved');
      }
      saved = true;
    } finally {
      if (!saved) {
        try {
          for (final MapEntry<String, String?> entry in original.entries) {
            final String? value = entry.value;
            final bool restored = value == null
                ? await _prefs.remove(entry.key)
                : await _prefs.setString(entry.key, value);
            if (!restored) {
              throw StateError(
                'Theme preference could not be saved or restored',
              );
            }
          }
        } finally {
          await _prefs.reload();
        }
      }
    }
    _emit();
  }

  Future<void> setBaseCurrency(String code) async {
    await _prefs.setString(_keyBaseCurrency, code);
    _emit();
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    await _prefs.setBool(_keyAppLock, enabled);
    _emit();
  }

  Future<void> setBlockScreenshots(bool enabled) async {
    final bool? original = _prefs.getBool(_keyBlockScreenshots);
    bool prefsSaved = false;
    bool applied = false;
    try {
      prefsSaved = await _prefs.setBool(_keyBlockScreenshots, enabled);
      if (!prefsSaved) {
        throw StateError('Screenshot protection preference could not be saved');
      }
      await ScreenshotProtection.setEnabled(enabled);
      applied = true;
    } finally {
      if (!applied) {
        try {
          if (prefsSaved) {
            final bool restored = original == null
                ? await _prefs.remove(_keyBlockScreenshots)
                : await _prefs.setBool(_keyBlockScreenshots, original);
            if (!restored) {
              throw StateError(
                'Screenshot protection preference could not be restored',
              );
            }
          }
        } finally {
          await _prefs.reload();
        }
      }
    }
    _blockScreenshots = enabled;
    _emit();
  }

  Future<void> setHideBalances(bool hidden) async {
    await _prefs.setBool(_keyHideBalances, hidden);
    _emit();
  }

  Future<void> setSimpleNetWorth(bool enabled) async {
    bool saved = false;
    try {
      saved = await _prefs.setBool(_keySimpleNetWorth, enabled);
      if (!saved) {
        throw StateError('Simple net worth preference could not be saved');
      }
    } finally {
      if (!saved) await _prefs.reload();
    }
    _simpleNetWorth = enabled;
    _emit();
  }

  Future<void> setSelectedPortfolioId(int? id) async {
    _selectedPortfolioId = (id != null && id > 0) ? id : null;
    _emit();
  }

  /// The custom category order for a portfolio section (asset/liability).
  List<String> categoryOrder(int portfolioId, String section) {
    final String? raw = _prefs.getString(
      _categoryOrderKey(portfolioId, section),
    );
    if (raw == null) return const <String>[];
    return raw
        .split(',')
        .where((String name) => name.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> setCategoryOrder(
    int portfolioId,
    String section,
    List<String> order,
  ) async {
    await _prefs.setString(
      _categoryOrderKey(portfolioId, section),
      order.join(','),
    );
    _emit();
  }

  String _categoryOrderKey(int portfolioId, String section) =>
      'cat_order_${section}_$portfolioId';

  void _emit() {
    if (!_controller.isClosed) _controller.add(current);
  }

  Future<void> dispose() => _controller.close();
}
