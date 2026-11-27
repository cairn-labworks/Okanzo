import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../data/backup/backup_repository.dart';
import '../data/local/app_database.dart';
import '../data/local/dao/asset_dao.dart';
import '../data/local/dao/fx_rate_dao.dart';
import '../data/local/dao/liability_dao.dart';
import '../data/local/dao/portfolio_dao.dart';
import '../data/remote/api_client.dart';
import '../data/remote/fx/fx_api.dart';
import '../data/remote/stock/chart_response.dart';
import '../data/remote/stock/stock_price_service.dart';
import '../data/remote/stock/stock_search_service.dart';
import '../data/repository/asset_repository.dart';
import '../data/repository/fx_repository.dart';
import '../data/repository/liability_repository.dart';
import '../data/repository/portfolio_repository.dart';
import '../data/repository/settings_repository.dart';
import '../data/security/database_key_provider.dart';
import '../util/app_lock_coordinator.dart';
import '../util/backup_file_picker.dart';
import '../util/biometric_authenticator.dart';

/// Lightweight manual dependency container holding the encrypted database and
/// every repository. A single instance is created at startup and handed to the
/// widget tree through [AppScope].
class AppContainer {
  AppContainer._({
    required this.database,
    required this.settingsRepository,
    required this.portfolioRepository,
    required this.assetRepository,
    required this.stockSearchService,
    required this.liabilityRepository,
    required this.fxRepository,
    required this.backupRepository,
    required this.biometricAuthenticator,
    required this.backupFilePicker,
    required this.clock,
    AppLockCoordinator? appLock,
  }) : appLock =
           appLock ??
           AppLockCoordinator(
             authenticator: biometricAuthenticator,
             now: clock,
           );

  static Future<AppContainer> create({
    SharedPreferences? preferences,
    SettingsRepository? settingsRepository,
    AppLockCoordinator? appLock,
    Future<String>? passphraseFuture,
    Future<String>? databasesDirFuture,
    BiometricAuthenticator? biometricAuthenticator,
    BackupFilePicker backupFilePicker = const SystemBackupFilePicker(),
    DateTime Function()? clock,
  }) async {
    const DatabaseKeyProvider keyProvider = DatabaseKeyProvider();
    final Future<SharedPreferences> prefsFuture = preferences != null
        ? Future<SharedPreferences>.value(preferences)
        : SharedPreferences.getInstance();
    final Future<String> effectivePassphraseFuture =
        passphraseFuture ?? keyProvider.getOrCreatePassphrase();
    final Future<String> effectiveDatabasesDirFuture =
        databasesDirFuture ?? getDatabasesPath();

    final String databasesDir = await effectiveDatabasesDirFuture;
    final String path = p.join(databasesDir, AppDatabase.databaseName);
    await _migrateLegacyDatabase(databasesDir, path);
    final AppDatabase database = await AppDatabase.open(
      path: path,
      password: await effectivePassphraseFuture,
    );
    final SharedPreferences prefs = await prefsFuture;

    final ApiClient client = ApiClient();
    final StockPriceService stockPriceService = StockPriceService(
      StockApi(client: client),
    );

    final PortfolioDao portfolioDao = PortfolioDao(database);
    final AssetDao assetDao = AssetDao(database);
    final LiabilityDao liabilityDao = LiabilityDao(database);
    final FxRateDao fxRateDao = FxRateDao(database);
    final FxRepository fxRepository = FxRepository(
      fxRateDao,
      FxApi(client: client),
    );
    final BiometricAuthenticator resolvedAuthenticator =
        biometricAuthenticator ?? LocalBiometricAuthenticator();
    final DateTime Function() resolvedClock = clock ?? DateTime.now;

    return AppContainer._(
      database: database,
      settingsRepository: settingsRepository ?? SettingsRepository(prefs),
      portfolioRepository: PortfolioRepository(portfolioDao),
      assetRepository: AssetRepository(
        assetDao,
        stockPriceService,
        fxRepository,
      ),
      stockSearchService: StockSearchService(client: client),
      liabilityRepository: LiabilityRepository(liabilityDao),
      fxRepository: fxRepository,
      backupRepository: BackupRepository(portfolioDao, assetDao, liabilityDao),
      biometricAuthenticator: resolvedAuthenticator,
      backupFilePicker: backupFilePicker,
      clock: resolvedClock,
      appLock: appLock,
    );
  }

  /// Before the app was renamed to Okanzo its encrypted database lived at
  /// `mywealth.db`. When an existing user upgrades, move the old file (and its
  /// SQLCipher/WAL sidecars) to the current name so their data survives the
  /// rename. Runs only when the new database does not already exist.
  static Future<void> _migrateLegacyDatabase(
    String directory,
    String currentPath,
  ) async {
    if (await File(currentPath).exists()) return;
    for (final String suffix in const <String>[
      '',
      '-wal',
      '-shm',
      '-journal',
    ]) {
      final File legacy = File(
        p.join(directory, '${AppDatabase.legacyDatabaseName}$suffix'),
      );
      if (await legacy.exists()) {
        await legacy.rename('$currentPath$suffix');
      }
    }
  }

  final AppDatabase database;
  final SettingsRepository settingsRepository;
  final PortfolioRepository portfolioRepository;
  final AssetRepository assetRepository;
  final StockSearchService stockSearchService;
  final LiabilityRepository liabilityRepository;
  final FxRepository fxRepository;
  final BackupRepository backupRepository;
  final BiometricAuthenticator biometricAuthenticator;
  final BackupFilePicker backupFilePicker;
  final DateTime Function() clock;
  final AppLockCoordinator appLock;
}

/// Makes the [AppContainer] available to the whole widget tree.
class AppScope extends InheritedWidget {
  const AppScope({required this.container, required super.child, super.key});

  final AppContainer container;

  static AppContainer of(BuildContext context) {
    final AppScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope was not found in the widget tree');
    return scope!.container;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      container != oldWidget.container;
}
