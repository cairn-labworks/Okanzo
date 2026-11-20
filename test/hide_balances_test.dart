import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okanzo/data/backup/backup_repository.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/data/local/entity/portfolio_entity.dart';
import 'package:okanzo/data/remote/stock/stock_price_service.dart';
import 'package:okanzo/data/remote/stock/stock_search_service.dart';
import 'package:okanzo/data/repository/asset_repository.dart';
import 'package:okanzo/data/repository/currency_converter.dart';
import 'package:okanzo/data/repository/fx_repository.dart';
import 'package:okanzo/data/repository/liability_repository.dart';
import 'package:okanzo/data/repository/portfolio_repository.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_theme.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:okanzo/main.dart';
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/liability/liability_edit_screen.dart';
import 'package:okanzo/ui/portfolio/portfolio_screen.dart';
import 'package:okanzo/ui/settings/settings_screen.dart';
import 'package:okanzo/ui/statistics/statistics_screen.dart';
import 'package:okanzo/util/app_lock_coordinator.dart';
import 'package:okanzo/util/backup_file_picker.dart';
import 'package:okanzo/util/biometric_authenticator.dart';
import 'package:okanzo/util/currency_util.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_biometric_authenticator.dart';

typedef CaptureScreenshot = Future<void> Function(
  WidgetTester tester,
  String name,
);

class _Portfolios extends Fake implements PortfolioRepository {
  static const List<PortfolioEntity> items = <PortfolioEntity>[
    PortfolioEntity(
      id: 1,
      name: 'Long-term',
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
  ];

  @override
  Stream<List<PortfolioEntity>> observeAll() =>
      Stream<List<PortfolioEntity>>.value(items);

  @override
  Future<int> ensureDefaultPortfolio([
    String defaultName = 'My Portfolio',
  ]) async => 1;
}

class _Assets extends Fake implements AssetRepository {
  int portfolioReads = 0;

  final Map<int, List<AssetEntity>> byPortfolio = <int, List<AssetEntity>>{
    1: const <AssetEntity>[
      AssetEntity(
        id: 1,
        portfolioId: 1,
        type: AssetType.crypto,
        name: 'Bitcoin',
        currency: 'USD',
        quantity: 1.25,
        symbol: 'BTC-USD',
        lastPrice: 64000,
        createdAt: 0,
        updatedAt: 0,
      ),
      AssetEntity(
        id: 2,
        portfolioId: 1,
        type: AssetType.stock,
        name: 'LVMH',
        currency: 'EUR',
        quantity: 10,
        symbol: 'MC.PA',
        lastPrice: 650,
        createdAt: 0,
        updatedAt: 0,
      ),
      AssetEntity(
        id: 3,
        portfolioId: 1,
        type: AssetType.gold,
        name: 'Bullion bar',
        currency: 'USD',
        quantity: 50,
        pricePerUnit: 85,
        createdAt: 0,
        updatedAt: 0,
      ),
      AssetEntity(
        id: 4,
        portfolioId: 1,
        type: AssetType.cash,
        name: 'Emergency reserve',
        currency: 'USD',
        manualValue: 12000,
        createdAt: 0,
        updatedAt: 0,
      ),
    ],
    2: const <AssetEntity>[
      AssetEntity(
        id: 5,
        portfolioId: 2,
        type: AssetType.mutualFund,
        name: 'Global Index',
        currency: 'USD',
        quantity: 200,
        symbol: 'VT',
        lastPrice: 120,
        createdAt: 0,
        updatedAt: 0,
      ),
    ],
  };

  @override
  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<AssetEntity>>.value(
        byPortfolio[portfolioId] ?? const <AssetEntity>[],
      );

  @override
  Future<List<AssetEntity>> getForPortfolio(int portfolioId) async {
    portfolioReads++;
    return byPortfolio[portfolioId] ?? const <AssetEntity>[];
  }

  @override
  Future<AssetEntity?> getById(int id) async {
    for (final List<AssetEntity> list in byPortfolio.values) {
      for (final AssetEntity asset in list) {
        if (asset.id == id) return asset;
      }
    }
    return null;
  }

  @override
  Future<Result<StockQuote>> fetchQuote(
    String symbol, {
    required String currency,
    bool isCrypto = false,
  }) async => Result<StockQuote>.offline();
}

class _Liabilities extends Fake implements LiabilityRepository {
  int portfolioReads = 0;

  static const Map<int, List<LiabilityEntity>> byPortfolio =
      <int, List<LiabilityEntity>>{
        1: <LiabilityEntity>[
          LiabilityEntity(
            id: 1,
            portfolioId: 1,
            type: LiabilityType.loan,
            name: 'Margin loan',
            currency: 'USD',
            amount: 4375,
            createdAt: 0,
            updatedAt: 0,
          ),
        ],
      };

  @override
  Stream<List<LiabilityEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<LiabilityEntity>>.value(
        byPortfolio[portfolioId] ?? const <LiabilityEntity>[],
      );

  @override
  Future<List<LiabilityEntity>> getForPortfolio(int portfolioId) async {
    portfolioReads++;
    return byPortfolio[portfolioId] ?? const <LiabilityEntity>[];
  }

  @override
  Future<LiabilityEntity?> getById(int id) async {
    for (final List<LiabilityEntity> list in byPortfolio.values) {
      for (final LiabilityEntity liability in list) {
        if (liability.id == id) return liability;
      }
    }
    return null;
  }
}

class _Fx extends Fake implements FxRepository {
  @override
  Stream<CurrencyConverter> get converter => Stream<CurrencyConverter>.value(
    const CurrencyConverter(<String, double>{'USD': 1.0, 'EUR': 0.8}),
  );

  @override
  Future<Result<void>> ensureFreshRates([int maxAgeMillis = 0]) async =>
      Result<void>.success(null);

  @override
  Future<int?> latestTimestamp() async => null;
}

class _Backups extends Fake implements BackupRepository {}

class _Search extends Fake implements StockSearchService {
  @override
  Future<Result<List<StockSearchResult>>> search(
    String query, {
    required StockSearchType type,
  }) async =>
      Result<List<StockSearchResult>>.success(const <StockSearchResult>[]);
}

class _Container extends Fake implements AppContainer {
  _Container(this.settingsRepository);

  @override
  final SettingsRepository settingsRepository;

  @override
  final PortfolioRepository portfolioRepository = _Portfolios();

  @override
  final _Assets assetRepository = _Assets();

  @override
  final _Liabilities liabilityRepository = _Liabilities();

  @override
  final FxRepository fxRepository = _Fx();

  @override
  final BackupRepository backupRepository = _Backups();

  @override
  final StockSearchService stockSearchService = _Search();

  @override
  final BiometricAuthenticator biometricAuthenticator =
      FakeBiometricAuthenticator();

  @override
  final BackupFilePicker backupFilePicker = const SystemBackupFilePicker();

  @override
  DateTime Function() get clock => DateTime.now;

  @override
  late final AppLockCoordinator appLock = AppLockCoordinator(
    authenticator: biometricAuthenticator,
    now: clock,
  );
}

void main({bool deviceViewport = false, CaptureScreenshot? capture}) {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Container container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'USD',
      'dynamic_color': false,
      'theme_mode': AppThemeMode.light.storageName,
      'app_theme': AppTheme.classic.storageName,
      'last_seen_version': AppReleaseNotes.currentVersion,
    });
    final SettingsRepository settings = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    addTearDown(settings.dispose);
    container = _Container(settings);
    addTearDown(container.appLock.dispose);
  });

  Future<void> start(WidgetTester tester) async {
    if (!deviceViewport) {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey<String>('hide-balances-evidence'),
        child: AppScope(container: container, child: const OkanzoApp()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Home expanded rows omit holding quantities while Hide Balances is active',
    (WidgetTester tester) async {
      await start(tester);

      await tester.tap(find.text('Cryptocurrency'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stock'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Metals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Metals'));
      await tester.pumpAndSettle();

      expect(find.text('1.25 × BTC-USD'), findsOneWidget);
      expect(find.text('10 × MC.PA  ·  EUR'), findsOneWidget);
      expect(find.text('50 g'), findsOneWidget);

      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hide balances'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('net-worth-headline')),
            )
            .data,
        CurrencyUtil.masked('USD'),
      );
      expect(find.text('1.25 × BTC-USD'), findsNothing);
      expect(find.text('BTC-USD'), findsOneWidget);
      expect(find.text('10 × MC.PA  ·  EUR'), findsNothing);
      expect(find.text('MC.PA  ·  EUR'), findsOneWidget);
      expect(find.text('50 g'), findsNothing);

      if (capture != null) {
        await capture(tester, 'after-home-masked');
      }

      // Switch to Retirement portfolio to verify symbol-less market & foreign Gold.
      // Stock and Gold remain expanded across portfolio switches.
      container.assetRepository.byPortfolio[2] = const <AssetEntity>[
        AssetEntity(
          id: 5,
          portfolioId: 2,
          type: AssetType.mutualFund,
          name: 'Global Index',
          currency: 'USD',
          quantity: 200,
          symbol: 'VT',
          lastPrice: 120,
          createdAt: 0,
          updatedAt: 0,
        ),
        AssetEntity(
          id: 6,
          portfolioId: 2,
          type: AssetType.stock,
          name: 'Private placement',
          currency: 'USD',
          quantity: 2.5,
          lastPrice: 400,
          createdAt: 0,
          updatedAt: 0,
        ),
        AssetEntity(
          id: 7,
          portfolioId: 2,
          type: AssetType.gold,
          name: 'Vault coins',
          currency: 'EUR',
          quantity: 20,
          pricePerUnit: 80,
          createdAt: 0,
          updatedAt: 0,
        ),
      ];
      await tester.tap(find.text('Long-term'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirement').last);
      await tester.pumpAndSettle();

      expect(find.text('Private placement'), findsOneWidget);
      expect(find.text('2.5 units'), findsNothing);
      expect(find.text('Vault coins'), findsOneWidget);
      expect(find.text('20 g  ·  EUR'), findsNothing);
      expect(find.text('·  EUR'), findsOneWidget);

      await tester.tap(find.byTooltip('Show balances'));
      await tester.pumpAndSettle();
      expect(find.text('2.5 units'), findsOneWidget);
      expect(find.text('20 g  ·  EUR'), findsOneWidget);
    },
  );

  testWidgets(
    'Portfolios masks net worth, keeps structure and counts, and toggles Hide Balances without reloading holdings',
    (WidgetTester tester) async {
      await start(tester);

      await tester.tap(find.byTooltip('Hide balances'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Portfolios'));
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioScreen), findsOneWidget);
      expect(find.text('Long-term'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('4 assets · 1 liabilities'), findsOneWidget);
      expect(find.text('Retirement'), findsOneWidget);
      expect(find.text('1 assets · 0 liabilities'), findsOneWidget);
      expect(find.text(r'$100,000'), findsNothing);
      expect(find.text(r'$24,000'), findsNothing);
      expect(find.text(CurrencyUtil.masked('USD')), findsNWidgets(2));

      if (capture != null) {
        await capture(tester, 'after-portfolios-masked');
      }

      final int assetReadsBeforeToggle =
          container.assetRepository.portfolioReads;
      final int liabilityReadsBeforeToggle =
          container.liabilityRepository.portfolioReads;

      // Toggle directly from the Portfolios app bar to reveal figures.
      await tester.tap(find.byTooltip('Show balances'));
      await tester.pumpAndSettle();

      expect(container.settingsRepository.current.hideBalances, isFalse);
      expect(container.assetRepository.portfolioReads, assetReadsBeforeToggle);
      expect(
        container.liabilityRepository.portfolioReads,
        liabilityReadsBeforeToggle,
      );
      expect(find.text(r'$100,000'), findsOneWidget);
      expect(find.text(r'$24,000'), findsOneWidget);

      // Toggle back to masked from Portfolios and verify pushed PortfolioScreen(onClose: ...) too.
      await tester.tap(find.byTooltip('Hide balances'));
      await tester.pumpAndSettle();
      expect(container.settingsRepository.current.hideBalances, isTrue);
      expect(find.text(CurrencyUtil.masked('USD')), findsNWidgets(2));

      final BuildContext navContext = tester.element(
        find.byType(PortfolioScreen),
      );
      unawaited(
        Navigator.of(navContext).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                PortfolioScreen(onClose: () => Navigator.of(context).pop()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.text(CurrencyUtil.masked('USD')), findsNWidgets(2));
      expect(find.byTooltip('Show balances'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Statistics toggles Hide Balances in the app bar, keeps percentages visible, leaves editors unmasked, and adds no Settings row',
    (WidgetTester tester) async {
      await start(tester);

      await tester.tap(find.text('Statistics'));
      await tester.pumpAndSettle();
      expect(find.byType(StatisticsScreen), findsOneWidget);
      expect(find.text(r'$104,375'), findsWidgets);
      expect(find.byTooltip('Hide balances'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide balances'));
      await tester.pumpAndSettle();

      expect(container.settingsRepository.current.hideBalances, isTrue);
      expect(find.text(r'$100,000'), findsNothing);
      expect(find.text(r'$104,375'), findsNothing);
      expect(find.text(CurrencyUtil.masked('USD')), findsWidgets);

      if (capture != null) {
        await capture(tester, 'after-statistics-masked');
      }

      // Selecting a legend row keeps relative allocation percentage visible.
      await tester.tap(find.text('Assets').first);
      await tester.pumpAndSettle();
      expect(find.text('95%'), findsOneWidget);
      expect(find.text(r'$104,375'), findsNothing);

      // Persists across restart and synchronizes back to Home; editors stay editable.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final SettingsRepository reopened = SettingsRepository(prefs);
      addTearDown(reopened.dispose);
      expect(reopened.current.hideBalances, isTrue);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show balances'), findsOneWidget);

      await tester.tap(find.text('Cryptocurrency'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bitcoin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit asset'));
      await tester.pumpAndSettle();
      expect(find.byType(AssetEditScreen), findsOneWidget);
      expect(find.text('1.25'), findsOneWidget);
      expect(find.text(r'$80,000'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('home-liabilities-tab')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Margin loan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit liability'));
      await tester.pumpAndSettle();
      expect(find.byType(LiabilityEditScreen), findsOneWidget);
      expect(find.text('4375'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Settings -> Security contains no duplicate Hide balances switch.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(find.text('Security'));
      await tester.pumpAndSettle();
      expect(find.text('App lock'), findsOneWidget);
      expect(find.text('Block screenshots'), findsOneWidget);
      expect(find.text('Hide balances'), findsNothing);
    },
  );
}
