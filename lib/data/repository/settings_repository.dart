import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/model/app_language.dart';
import '../../domain/model/app_theme.dart';
import '../../domain/model/release_notes.dart';
import '../../domain/model/stock_exchange.dart';
import '../../domain/model/theme_mode.dart';
import '../../util/currency_util.dart';

/// All user-facing app preferences.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.appTheme = AppTheme.classic,
    this.dynamicColor = true,
    required this.baseCurrency,
    this.appLockEnabled = false,
    this.hideBalances = false,
    this.selectedPortfolioId,
    this.preferredExchanges = const <StockExchange>[StockExchange.us],
    this.language = AppLanguage.system,
    this.lastSeenVersion,
  });

  final AppThemeMode themeMode;
  final AppTheme appTheme;
  final bool dynamicColor;
  final String baseCurrency;
  final bool appLockEnabled;
  final bool hideBalances;
  final int? selectedPortfolioId;
  final List<StockExchange> preferredExchanges;
  final AppLanguage language;
  final String? lastSeenVersion;
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
  static const String _keyDynamicColor = 'dynamic_color';
  static const String _keyBaseCurrency = 'base_currency';
  static const String _keyAppLock = 'app_lock_enabled';
  static const String _keyHideBalances = 'hide_balances';
  static const String _keySelectedPortfolio = 'selected_portfolio_id';
  static const String _keyPreferredExchanges = 'preferred_stock_exchanges';
  static const String _keyLanguage = 'app_language';
  static const String _keyLastSeenVersion = 'last_seen_version';

  final SharedPreferences _prefs;
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
    dynamicColor: _prefs.getBool(_keyDynamicColor) ?? true,
    baseCurrency:
        _prefs.getString(_keyBaseCurrency) ?? CurrencyUtil.deviceCurrencyCode(),
    appLockEnabled: _prefs.getBool(_keyAppLock) ?? false,
    hideBalances: _prefs.getBool(_keyHideBalances) ?? false,
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
    return List<StockExchange>.unmodifiable(
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

  int? get _selectedPortfolioId {
    final int? id = _prefs.getInt(_keySelectedPortfolio);
    return (id != null && id > 0) ? id : null;
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    await _prefs.setString(_keyThemeMode, mode.storageName);
    _emit();
  }

  Future<void> setAppTheme(AppTheme theme) async {
    await _prefs.setString(_keyAppTheme, theme.storageName);
    _emit();
  }

  Future<void> setDynamicColor(bool enabled) async {
    await _prefs.setBool(_keyDynamicColor, enabled);
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

  Future<void> setHideBalances(bool hidden) async {
    await _prefs.setBool(_keyHideBalances, hidden);
    _emit();
  }

  Future<void> setSelectedPortfolioId(int? id) async {
    if (id == null) {
      await _prefs.remove(_keySelectedPortfolio);
    } else {
      await _prefs.setInt(_keySelectedPortfolio, id);
    }
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
