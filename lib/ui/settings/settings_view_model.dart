import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/backup/backup_models.dart';
import '../../data/backup/backup_repository.dart';
import '../../data/local/entity/portfolio_entity.dart';
import '../../data/repository/fx_repository.dart';
import '../../data/repository/portfolio_repository.dart';
import '../../data/repository/settings_repository.dart';
import '../../domain/model/app_language.dart';
import '../../domain/model/app_theme.dart';
import '../../domain/model/theme_mode.dart';
import '../../util/result.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required SettingsRepository settingsRepository,
    required PortfolioRepository portfolioRepository,
    required FxRepository fxRepository,
    required BackupRepository backupRepository,
  }) : _settingsRepository = settingsRepository,
       _portfolioRepository = portfolioRepository,
       _fxRepository = fxRepository,
       _backupRepository = backupRepository,
       _settings = settingsRepository.current {
    _settingsSub = settingsRepository.settings.listen((AppSettings settings) {
      _settings = settings;
      notifyListeners();
    });
    _portfolioSub = portfolioRepository.observeAll().listen((
      List<PortfolioEntity> portfolios,
    ) {
      _portfolios = portfolios;
      notifyListeners();
    });
    unawaited(_loadFxTimestamp());
  }

  final SettingsRepository _settingsRepository;
  final PortfolioRepository _portfolioRepository;
  final FxRepository _fxRepository;
  final BackupRepository _backupRepository;

  StreamSubscription<AppSettings>? _settingsSub;
  StreamSubscription<List<PortfolioEntity>>? _portfolioSub;

  AppSettings _settings;
  List<PortfolioEntity> _portfolios = const <PortfolioEntity>[];
  int? _fxUpdatedAt;
  String? _message;
  bool _savingSimpleNetWorth = false;
  bool _disposed = false;

  AppSettings get settings => _settings;

  List<PortfolioEntity> get portfolios => _portfolios;

  int? get fxUpdatedAt => _fxUpdatedAt;

  String? get message => _message;

  bool get isSavingSimpleNetWorth => _savingSimpleNetWorth;

  Future<void> _loadFxTimestamp() async {
    _fxUpdatedAt = await _fxRepository.latestTimestamp();
    notifyListeners();
  }

  void setThemeMode(AppThemeMode mode) =>
      unawaited(_settingsRepository.setThemeMode(mode));

  void setAppTheme(AppTheme theme) =>
      unawaited(_settingsRepository.setAppTheme(theme));

  Future<void> setLanguage(AppLanguage language) =>
      _settingsRepository.setLanguage(language);

  Future<void> markWhatsNewSeen(String version) =>
      _settingsRepository.setLastSeenVersion(version);

  void setDynamicColor(bool enabled) =>
      unawaited(_settingsRepository.setDynamicColor(enabled));

  void setBaseCurrency(String code) =>
      unawaited(_settingsRepository.setBaseCurrency(code));

  Future<void> setSimpleNetWorth(bool enabled) async {
    if (_savingSimpleNetWorth) return;
    _savingSimpleNetWorth = true;
    notifyListeners();
    try {
      await _settingsRepository.setSimpleNetWorth(enabled);
    } on Object catch (error) {
      _message = "Couldn't save simple net worth: $error";
    } finally {
      _savingSimpleNetWorth = false;
      if (!_disposed) notifyListeners();
    }
  }

  void setAppLockEnabled(bool enabled) =>
      unawaited(_settingsRepository.setAppLockEnabled(enabled));

  Future<void> refreshRates() async {
    final Result<void> result = await _fxRepository.refreshRates();
    _fxUpdatedAt = await _fxRepository.latestTimestamp();
    _message = result.isSuccess
        ? 'Exchange rates updated'
        : "Couldn't update rates";
    notifyListeners();
  }

  Future<Uint8List> buildExport(List<int> portfolioIds, String password) =>
      _backupRepository.export(portfolioIds, password);

  Future<ImportResult> importBackup(Uint8List data, String password) =>
      _backupRepository.import(data, password);

  void postMessage(String text) {
    _message = text;
    notifyListeners();
  }

  void consumeMessage() {
    _message = null;
  }

  /// Exposed so the screen can refresh portfolio rows after an import.
  PortfolioRepository get portfolioRepository => _portfolioRepository;

  @override
  void dispose() {
    _disposed = true;
    _settingsSub?.cancel();
    _portfolioSub?.cancel();
    super.dispose();
  }
}
