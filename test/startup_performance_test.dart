import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okanzo/data/backup/backup_repository.dart';
import 'package:okanzo/data/local/app_database.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/data/local/entity/portfolio_entity.dart';
import 'package:okanzo/data/repository/asset_repository.dart';
import 'package:okanzo/data/repository/currency_converter.dart';
import 'package:okanzo/data/repository/fx_repository.dart';
import 'package:okanzo/data/repository/liability_repository.dart';
import 'package:okanzo/data/repository/portfolio_repository.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/main.dart';
import 'package:okanzo/ui/home/home_view_model.dart';
import 'package:okanzo/ui/lock/lock_screen.dart';
import 'package:okanzo/ui/navigation/app_shell.dart';
import 'package:okanzo/util/app_lock_coordinator.dart';
import 'package:okanzo/util/biometric_authenticator.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'helpers/fake_biometric_authenticator.dart';

class _RecordingDatabase extends Fake implements Database {
  _RecordingDatabase({required this.userVersion});

  int userVersion;
  final List<String> executed = <String>[];
  final List<String> queried = <String>[];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    executed.add(sql);
    final RegExpMatch? setVer = RegExp(
      r'PRAGMA\s+user_version\s*=\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(sql);
    if (setVer != null) {
      userVersion = int.parse(setVer.group(1)!);
    }
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    queried.add(sql);
    if (sql.toUpperCase().contains('PRAGMA USER_VERSION')) {
      return <Map<String, Object?>>[
        <String, Object?>{'user_version': userVersion},
      ];
    }
    if (sql.toUpperCase().contains('PRAGMA JOURNAL_MODE')) {
      return const <Map<String, Object?>>[
        <String, Object?>{'journal_mode': 'wal'},
      ];
    }
    return const <Map<String, Object?>>[];
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => action(_RecordingTransaction(this));
}

class _RecordingTransaction extends Fake implements Transaction {
  _RecordingTransaction(this._db);

  final _RecordingDatabase _db;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _db.execute(sql, arguments);
}

class _CountingPortfolioRepository extends Fake implements PortfolioRepository {
  _CountingPortfolioRepository(this._initial);

  final List<PortfolioEntity> _initial;
  final StreamController<List<PortfolioEntity>> _controller =
      StreamController<List<PortfolioEntity>>.broadcast();
  int ensureDefaultCalls = 0;

  @override
  Stream<List<PortfolioEntity>> observeAll() async* {
    yield _initial;
    yield* _controller.stream;
  }

  @override
  Future<int> ensureDefaultPortfolio([
    String defaultName = 'My Portfolio',
  ]) async {
    ensureDefaultCalls++;
    if (_initial.isEmpty) {
      final PortfolioEntity created = PortfolioEntity(
        id: 1,
        name: defaultName,
        isDefault: true,
        createdAt: 0,
        updatedAt: 0,
      );
      _controller.add(<PortfolioEntity>[created]);
      return 1;
    }
    return _initial.first.id;
  }

  Future<void> dispose() => _controller.close();
}

class _DelayedHoldingsAssetRepository extends Fake implements AssetRepository {
  final Completer<List<AssetEntity>> initial = Completer<List<AssetEntity>>();

  @override
  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<AssetEntity>>.fromFuture(initial.future);
}

class _DelayedHoldingsLiabilityRepository extends Fake
    implements LiabilityRepository {
  final Completer<List<LiabilityEntity>> initial =
      Completer<List<LiabilityEntity>>();

  @override
  Stream<List<LiabilityEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<LiabilityEntity>>.fromFuture(initial.future);
}

class _MultiPortfolioAssetRepository extends Fake implements AssetRepository {
  final Map<int, Completer<List<AssetEntity>>> completers =
      <int, Completer<List<AssetEntity>>>{
        1: Completer<List<AssetEntity>>(),
        2: Completer<List<AssetEntity>>(),
      };

  @override
  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<AssetEntity>>.fromFuture(completers[portfolioId]!.future);
}

class _MultiPortfolioLiabilityRepository extends Fake
    implements LiabilityRepository {
  final Map<int, Completer<List<LiabilityEntity>>> completers =
      <int, Completer<List<LiabilityEntity>>>{
        1: Completer<List<LiabilityEntity>>(),
        2: Completer<List<LiabilityEntity>>(),
      };

  @override
  Stream<List<LiabilityEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<LiabilityEntity>>.fromFuture(completers[portfolioId]!.future);
}

class _DecoupledFreshPortfolioRepository extends Fake
    implements PortfolioRepository {
  final StreamController<List<PortfolioEntity>> controller =
      StreamController<List<PortfolioEntity>>.broadcast();
  final Completer<int> ensureCompleter = Completer<int>();
  int ensureCalls = 0;

  @override
  Stream<List<PortfolioEntity>> observeAll() async* {
    yield const <PortfolioEntity>[];
    yield* controller.stream;
  }

  @override
  Future<int> ensureDefaultPortfolio([String defaultName = 'My Portfolio']) {
    ensureCalls++;
    return ensureCompleter.future;
  }

  Future<void> dispose() => controller.close();
}

class _SequencedFxRepository extends Fake implements FxRepository {
  int ensureFreshCalls = 0;

  @override
  Stream<CurrencyConverter> get converter =>
      Stream<CurrencyConverter>.value(const CurrencyConverter.empty());

  @override
  Future<Result<void>> ensureFreshRates([int maxAgeMillis = 0]) async {
    ensureFreshCalls++;
    return Result<void>.success(null);
  }
}

class _FakeContainer extends Fake implements AppContainer {
  _FakeContainer({
    required this.settingsRepository,
    required this.appLock,
    required this.portfolioRepository,
    required this.assetRepository,
    required this.liabilityRepository,
    required this.fxRepository,
  });

  @override
  final SettingsRepository settingsRepository;
  @override
  final AppLockCoordinator appLock;
  @override
  final PortfolioRepository portfolioRepository;
  @override
  final AssetRepository assetRepository;
  @override
  final LiabilityRepository liabilityRepository;
  @override
  final FxRepository fxRepository;
  @override
  final BackupRepository backupRepository = _NoopBackupRepository();
  @override
  BiometricAuthenticator get biometricAuthenticator =>
      FakeBiometricAuthenticator();
}

class _NoopBackupRepository extends Fake implements BackupRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppDatabase.prepareOpen skips DDL index round-trips when already at schemaVersion and enables WAL', () async {
    final _RecordingDatabase upToDate = _RecordingDatabase(
      userVersion: AppDatabase.schemaVersion,
    );
    await AppDatabase.prepareOpen(upToDate);

    expect(
      upToDate.executed.where(
        (String s) => s.toUpperCase().contains('CREATE INDEX'),
      ),
      isEmpty,
    );
    expect(
      upToDate.executed.where(
        (String s) => s.toUpperCase().contains('CREATE TABLE'),
      ),
      isEmpty,
    );
    expect(
      <String>[
        ...upToDate.executed,
        ...upToDate.queried,
      ].any((String s) => s.toUpperCase().contains('JOURNAL_MODE')),
      isTrue,
    );
    expect(
      upToDate.executed.any(
        (String s) =>
            RegExp(r'SYNCHRONOUS\s*=\s*FULL', caseSensitive: false).hasMatch(s),
      ),
      isTrue,
    );
    expect(
      upToDate.executed.any(
        (String s) => RegExp(
          r'SYNCHRONOUS\s*=\s*NORMAL',
          caseSensitive: false,
        ).hasMatch(s),
      ),
      isFalse,
    );

    // Fresh database (version 0) still creates all tables and stamps schemaVersion.
    final _RecordingDatabase fresh = _RecordingDatabase(userVersion: 0);
    await AppDatabase.prepareOpen(fresh);
    expect(fresh.userVersion, AppDatabase.schemaVersion);
    expect(
      fresh.executed.where(
        (String s) => s.toUpperCase().contains('CREATE TABLE'),
      ),
      isNotEmpty,
    );
  });

  test('HomeViewModel skips redundant ensureDefaultPortfolio when a default exists, '
      'waits for initial holdings before clearing loading, and defers ensureFreshRates', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'USD',
    });
    final SettingsRepository settings = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    addTearDown(settings.dispose);

    final _CountingPortfolioRepository portfolios =
        _CountingPortfolioRepository(const <PortfolioEntity>[
          PortfolioEntity(
            id: 1,
            name: 'Personal',
            isDefault: true,
            createdAt: 0,
            updatedAt: 0,
          ),
        ]);
    addTearDown(portfolios.dispose);
    final _DelayedHoldingsAssetRepository assets =
        _DelayedHoldingsAssetRepository();
    final _DelayedHoldingsLiabilityRepository liabilities =
        _DelayedHoldingsLiabilityRepository();
    final _SequencedFxRepository fx = _SequencedFxRepository();

    final List<HomeState> emitted = <HomeState>[];
    final HomeViewModel vm = HomeViewModel(
      settingsRepository: settings,
      portfolioRepository: portfolios,
      assetRepository: assets,
      liabilityRepository: liabilities,
      fxRepository: fx,
    );
    addTearDown(vm.dispose);
    vm.addListener(() => emitted.add(vm.state));

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // Default portfolio already exists -> no redundant ensureDefaultPortfolio query.
    expect(portfolios.ensureDefaultCalls, 0);
    // Holdings have not emitted yet -> must NOT flash an empty $0 non-loading state,
    // and background FX network check has not contended with initial DB reads yet.
    expect(vm.state.loading, isTrue);
    expect(emitted.where((HomeState s) => !s.loading), isEmpty);
    expect(fx.ensureFreshCalls, 0);

    assets.initial.complete(const <AssetEntity>[
      AssetEntity(
        id: 1,
        portfolioId: 1,
        type: AssetType.cash,
        name: 'Checking',
        currency: 'USD',
        manualValue: 2500,
        createdAt: 0,
        updatedAt: 0,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    // Liabilities still pending -> still loading.
    expect(vm.state.loading, isTrue);

    liabilities.initial.complete(const <LiabilityEntity>[
      LiabilityEntity(
        id: 1,
        portfolioId: 1,
        type: LiabilityType.loan,
        name: 'Card',
        currency: 'USD',
        amount: 500,
        createdAt: 0,
        updatedAt: 0,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // First non-loading state already carries final net worth ($2,000), zero $0 flash!
    final List<HomeState> readyStates = emitted
        .where((HomeState s) => !s.loading)
        .toList();
    expect(readyStates, isNotEmpty);
    expect(readyStates.first.summary.netWorth, 2000);
    expect(fx.ensureFreshCalls, 1);
  });

  test('HomeViewModel publishes loading state with new active portfolio and live settings during portfolio switch', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'USD',
    });
    final SettingsRepository settings = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    addTearDown(settings.dispose);

    final _CountingPortfolioRepository portfolios =
        _CountingPortfolioRepository(const <PortfolioEntity>[
          PortfolioEntity(
            id: 1,
            name: 'Personal',
            isDefault: true,
            createdAt: 0,
            updatedAt: 0,
          ),
          PortfolioEntity(
            id: 2,
            name: 'Retirement',
            isDefault: false,
            createdAt: 0,
            updatedAt: 0,
          ),
        ]);
    addTearDown(portfolios.dispose);
    final _MultiPortfolioAssetRepository assets =
        _MultiPortfolioAssetRepository();
    final _MultiPortfolioLiabilityRepository liabilities =
        _MultiPortfolioLiabilityRepository();
    final _SequencedFxRepository fx = _SequencedFxRepository();

    final HomeViewModel vm = HomeViewModel(
      settingsRepository: settings,
      portfolioRepository: portfolios,
      assetRepository: assets,
      liabilityRepository: liabilities,
      fxRepository: fx,
    );
    addTearDown(vm.dispose);

    assets.completers[1]!.complete(const <AssetEntity>[
      AssetEntity(
        id: 1,
        portfolioId: 1,
        type: AssetType.cash,
        name: 'Checking',
        currency: 'USD',
        manualValue: 2500,
        createdAt: 0,
        updatedAt: 0,
      ),
    ]);
    liabilities.completers[1]!.complete(const <LiabilityEntity>[
      LiabilityEntity(
        id: 1,
        portfolioId: 1,
        type: LiabilityType.loan,
        name: 'Card',
        currency: 'USD',
        amount: 500,
        createdAt: 0,
        updatedAt: 0,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(vm.state.loading, isFalse);
    expect(vm.state.activePortfolio?.id, 1);
    expect(vm.state.summary.netWorth, 2000);
    expect(vm.state.hideBalances, isFalse);

    // Switch to portfolio 2 while its holdings queries are still pending.
    vm.selectPortfolio(2);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(vm.state.loading, isTrue);
    expect(vm.state.activePortfolio?.id, 2);

    // Privacy toggle updates immediately even while portfolio 2 holdings load.
    vm.toggleHideBalances();
    await Future<void>.delayed(Duration.zero);
    expect(vm.state.loading, isTrue);
    expect(vm.state.hideBalances, isTrue);

    assets.completers[2]!.complete(const <AssetEntity>[
      AssetEntity(
        id: 2,
        portfolioId: 2,
        type: AssetType.cash,
        name: 'IRA',
        currency: 'USD',
        manualValue: 9000,
        createdAt: 0,
        updatedAt: 0,
      ),
    ]);
    liabilities.completers[2]!.complete(const <LiabilityEntity>[
      LiabilityEntity(
        id: 2,
        portfolioId: 2,
        type: LiabilityType.loan,
        name: 'Margin',
        currency: 'USD',
        amount: 1000,
        createdAt: 0,
        updatedAt: 0,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(vm.state.loading, isFalse);
    expect(vm.state.activePortfolio?.id, 2);
    expect(vm.state.hideBalances, isTrue);
    expect(vm.state.summary.netWorth, 8000);
  });

  test('HomeViewModel waits for observeAll and holdings after ensureDefaultPortfolio and handles disposal cleanly', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'USD',
    });
    final SettingsRepository settings = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    addTearDown(settings.dispose);

    // Part 1: ensureDefaultPortfolio finishes BEFORE observeAll delivers the row.
    final _DecoupledFreshPortfolioRepository freshPortfolios =
        _DecoupledFreshPortfolioRepository();
    addTearDown(freshPortfolios.dispose);
    final _DelayedHoldingsAssetRepository assets =
        _DelayedHoldingsAssetRepository();
    final _DelayedHoldingsLiabilityRepository liabilities =
        _DelayedHoldingsLiabilityRepository();
    final _SequencedFxRepository fx = _SequencedFxRepository();

    final HomeViewModel vm = HomeViewModel(
      settingsRepository: settings,
      portfolioRepository: freshPortfolios,
      assetRepository: assets,
      liabilityRepository: liabilities,
      fxRepository: fx,
    );
    addTearDown(vm.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(freshPortfolios.ensureCalls, 1);
    expect(vm.state.loading, isTrue);
    expect(fx.ensureFreshCalls, 0);

    // ensureDefaultPortfolio resolves BEFORE observeAll delivers the created row.
    freshPortfolios.ensureCompleter.complete(1);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // Must NOT mark empty Home ready or start FX prematurely!
    expect(vm.state.loading, isTrue);
    expect(fx.ensureFreshCalls, 0);

    // Now observeAll delivers the newly created default portfolio.
    freshPortfolios.controller.add(const <PortfolioEntity>[
      PortfolioEntity(
        id: 1,
        name: 'My Portfolio',
        isDefault: true,
        createdAt: 0,
        updatedAt: 0,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(vm.state.loading, isTrue);
    expect(vm.state.activePortfolio?.id, 1);
    expect(fx.ensureFreshCalls, 0);

    assets.initial.complete(const <AssetEntity>[]);
    liabilities.initial.complete(const <LiabilityEntity>[]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(vm.state.loading, isFalse);
    expect(vm.state.activePortfolio?.id, 1);
    expect(fx.ensureFreshCalls, 1);

    // Part 2: Disposing while ensureDefaultPortfolio is pending must not notify after dispose.
    final _DecoupledFreshPortfolioRepository pendingCreate =
        _DecoupledFreshPortfolioRepository();
    addTearDown(pendingCreate.dispose);
    int postDisposeNotifications = 0;
    bool disposed = false;
    final HomeViewModel disposableVm = HomeViewModel(
      settingsRepository: settings,
      portfolioRepository: pendingCreate,
      assetRepository: _DelayedHoldingsAssetRepository(),
      liabilityRepository: _DelayedHoldingsLiabilityRepository(),
      fxRepository: _SequencedFxRepository(),
    );
    disposableVm.addListener(() {
      if (disposed) postDisposeNotifications++;
    });
    await Future<void>.delayed(Duration.zero);
    expect(pendingCreate.ensureCalls, 1);

    disposed = true;
    disposableVm.dispose();
    pendingCreate.ensureCompleter.complete(1);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(postDisposeNotifications, 0);
  });

  testWidgets(
    'OkanzoBootstrap renders LockScreen and prompts biometric immediately while database is still opening',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'base_currency': 'USD',
        'app_lock_enabled': true,
        'last_seen_version': AppReleaseNotes.currentVersion,
      });
      final SettingsRepository settings = SettingsRepository(
        await SharedPreferences.getInstance(),
      );
      addTearDown(settings.dispose);

      final FakeBiometricAuthenticator authenticator =
          FakeBiometricAuthenticator()..result = BiometricResult.cancelled;
      final AppLockCoordinator appLock = AppLockCoordinator(
        authenticator: authenticator,
      );
      addTearDown(appLock.dispose);

      final Completer<AppContainer> containerCompleter =
          Completer<AppContainer>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await tester.pumpWidget(
        OkanzoBootstrap(
          settingsRepository: settings,
          appLock: appLock,
          containerFuture: containerCompleter.future,
        ),
      );
      await tester.pump();
      await tester.pump();

      // Even before SQLCipher finishes opening, LockScreen is painted and biometrics prompted!
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(authenticator.reasons, hasLength(1));

      // Now unlock and finish opening the database -> transitions seamlessly into AppShell.
      appLock.markUnlocked();
      final _CountingPortfolioRepository portfolios =
          _CountingPortfolioRepository(const <PortfolioEntity>[
            PortfolioEntity(
              id: 1,
              name: 'Personal',
              isDefault: true,
              createdAt: 0,
              updatedAt: 0,
            ),
          ]);
      addTearDown(portfolios.dispose);
      final _DelayedHoldingsAssetRepository assets =
          _DelayedHoldingsAssetRepository()
            ..initial.complete(const <AssetEntity>[]);
      final _DelayedHoldingsLiabilityRepository liabilities =
          _DelayedHoldingsLiabilityRepository()
            ..initial.complete(const <LiabilityEntity>[]);
      containerCompleter.complete(
        _FakeContainer(
          settingsRepository: settings,
          appLock: appLock,
          portfolioRepository: portfolios,
          assetRepository: assets,
          liabilityRepository: liabilities,
          fxRepository: _SequencedFxRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);

      // Re-mounting a fresh OkanzoBootstrap instance (e.g. relaunch test) does not collide GlobalKeys.
      await tester.pumpWidget(
        OkanzoBootstrap(
          key: UniqueKey(),
          settingsRepository: settings,
          appLock: appLock,
          containerFuture: containerCompleter.future,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
    },
  );
}
