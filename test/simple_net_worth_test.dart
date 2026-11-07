import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:okanzo/data/backup/backup_repository.dart';
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
import 'package:okanzo/domain/model/net_worth_summary.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/home/home_view_model.dart';
import 'package:okanzo/ui/home/net_worth_card.dart';
import 'package:okanzo/ui/settings/settings_screen.dart';
import 'package:okanzo/ui/settings/settings_view_model.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PortfolioRepository extends Fake implements PortfolioRepository {
  @override
  Stream<List<PortfolioEntity>> observeAll() =>
      Stream<List<PortfolioEntity>>.value(const <PortfolioEntity>[
        PortfolioEntity(
          id: 1,
          name: 'Personal',
          isDefault: true,
          createdAt: 0,
          updatedAt: 0,
        ),
      ]);

  @override
  Future<int> ensureDefaultPortfolio([
    String defaultName = 'My Portfolio',
  ]) async => 1;
}

class _AssetRepository extends Fake implements AssetRepository {
  @override
  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<AssetEntity>>.value(const <AssetEntity>[
        AssetEntity(
          id: 1,
          portfolioId: 1,
          type: AssetType.cash,
          name: 'Cash',
          currency: 'INR',
          manualValue: 17534234,
          createdAt: 0,
          updatedAt: 0,
        ),
      ]);
}

class _LiabilityRepository extends Fake implements LiabilityRepository {
  @override
  Stream<List<LiabilityEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<LiabilityEntity>>.value(const <LiabilityEntity>[
        LiabilityEntity(
          id: 1,
          portfolioId: 1,
          type: LiabilityType.loan,
          name: 'Loan',
          currency: 'INR',
          amount: 1000000,
          createdAt: 0,
          updatedAt: 0,
        ),
      ]);
}

class _FxRepository extends Fake implements FxRepository {
  @override
  Stream<CurrencyConverter> get converter =>
      Stream<CurrencyConverter>.value(const CurrencyConverter.empty());

  @override
  Future<Result<void>> ensureFreshRates([int maxAgeMillis = 0]) async =>
      Result<void>.success(null);

  @override
  Future<int?> latestTimestamp() async => null;
}

class _BackupRepository extends Fake implements BackupRepository {}

class _Container extends Fake implements AppContainer {
  _Container(this.settingsRepository);

  @override
  final SettingsRepository settingsRepository;

  @override
  final PortfolioRepository portfolioRepository = _PortfolioRepository();

  @override
  final AssetRepository assetRepository = _AssetRepository();

  @override
  final LiabilityRepository liabilityRepository = _LiabilityRepository();

  @override
  final FxRepository fxRepository = _FxRepository();

  @override
  final BackupRepository backupRepository = _BackupRepository();
}

class _RejectingPreferences extends Fake implements SharedPreferences {
  _RejectingPreferences({required this.throwOnWrite});

  final bool throwOnWrite;
  bool cachedValue = false;
  int reloads = 0;

  @override
  String? getString(String key) => key == 'base_currency' ? 'INR' : null;

  @override
  bool? getBool(String key) => key == 'simple_net_worth' ? cachedValue : null;

  @override
  int? getInt(String key) => null;

  @override
  List<String>? getStringList(String key) => null;

  @override
  Future<bool> setBool(String key, bool value) async {
    cachedValue = value;
    if (throwOnWrite) throw StateError('Storage unavailable');
    return false;
  }

  @override
  Future<void> reload() async {
    reloads++;
    cachedValue = false;
  }
}

class _DelayedSettingsRepository extends SettingsRepository {
  _DelayedSettingsRepository(super.preferences);

  final Completer<void> pending = Completer<void>();
  int writes = 0;

  @override
  Future<void> setSimpleNetWorth(bool enabled) async {
    writes++;
    await pending.future;
    await super.setSimpleNetWorth(enabled);
  }
}

Widget _app(_Container container, Widget home) => AppScope(
  container: container,
  child: MaterialApp(home: home),
);

SettingsViewModel _settingsViewModel(_Container container) => SettingsViewModel(
  settingsRepository: container.settingsRepository,
  portfolioRepository: container.portfolioRepository,
  fxRepository: container.fxRepository,
  backupRepository: container.backupRepository,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late SettingsRepository repository;
  late _Container container;

  setUp(() async {
    final String? originalLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en_IN';
    addTearDown(() => Intl.defaultLocale = originalLocale);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'INR',
    });
    preferences = await SharedPreferences.getInstance();
    repository = SettingsRepository(preferences);
    container = _Container(repository);
    addTearDown(repository.dispose);
  });

  test(
    'simple net worth is opt-in and persists without altering balances',
    () async {
      expect(repository.current.simpleNetWorth, isFalse);
      await repository.setHideBalances(true);
      for (final bool enabled in <bool>[true, false]) {
        await repository.setSimpleNetWorth(enabled);
        await preferences.reload();
        final SettingsRepository reopened = SettingsRepository(preferences);
        expect(reopened.current.simpleNetWorth, enabled);
        expect(reopened.current.baseCurrency, 'INR');
        expect(reopened.current.hideBalances, isTrue);
        await reopened.dispose();
      }
    },
  );

  test(
    'saved changes reach the home state without changing net worth',
    () async {
      final HomeViewModel home = HomeViewModel(
        settingsRepository: repository,
        portfolioRepository: container.portfolioRepository,
        assetRepository: container.assetRepository,
        liabilityRepository: container.liabilityRepository,
        fxRepository: container.fxRepository,
      );
      addTearDown(home.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(home.state.simpleNetWorth, isFalse);
      expect(home.state.summary.netWorth, 16534234);
      for (final bool enabled in <bool>[true, false]) {
        await repository.setSimpleNetWorth(enabled);
        await Future<void>.delayed(Duration.zero);
        expect(home.state.simpleNetWorth, enabled);
        expect(home.state.summary.netWorth, 16534234);
      }
    },
  );

  for (final bool throwOnWrite in <bool>[false, true]) {
    test(
      'failed writes restore cache and notify users (throws: $throwOnWrite)',
      () async {
        final _RejectingPreferences rejected = _RejectingPreferences(
          throwOnWrite: throwOnWrite,
        );
        final SettingsRepository failing = SettingsRepository(rejected);
        addTearDown(failing.dispose);
        final List<bool> emitted = <bool>[];
        final StreamSubscription<AppSettings> subscription = failing.settings
            .listen(
              (AppSettings settings) => emitted.add(settings.simpleNetWorth),
            );
        addTearDown(subscription.cancel);
        await Future<void>.delayed(Duration.zero);
        await expectLater(failing.setSimpleNetWorth(true), throwsStateError);
        expect(failing.current.simpleNetWorth, isFalse);
        expect(rejected.reloads, 1);
        final SettingsViewModel settings = _settingsViewModel(
          _Container(failing),
        );
        addTearDown(settings.dispose);
        await settings.setSimpleNetWorth(true);
        expect(settings.message, startsWith("Couldn't save simple net worth:"));
        expect(settings.settings.simpleNetWorth, isFalse);
        expect(settings.isSavingSimpleNetWorth, isFalse);
        expect(emitted, <bool>[false]);
      },
    );
  }

  test(
    'pending saves are gated and can finish after leaving settings',
    () async {
      final _DelayedSettingsRepository delayed = _DelayedSettingsRepository(
        preferences,
      );
      addTearDown(delayed.dispose);
      final SettingsViewModel settings = _settingsViewModel(
        _Container(delayed),
      );
      await Future<void>.delayed(Duration.zero);
      final Future<void> save = settings.setSimpleNetWorth(true);
      expect(settings.isSavingSimpleNetWorth, isTrue);
      await settings.setSimpleNetWorth(false);
      expect(delayed.writes, 1);
      settings.dispose();
      delayed.pending.complete();
      await save;
      expect(delayed.current.simpleNetWorth, isTrue);
    },
  );

  testWidgets(
    'settings switch controls only the home headline and preserves masking',
    (WidgetTester tester) async {
      Widget home() => HomeScreen(
        onOpenAssetEditor: (_, _) {},
        onOpenLiabilityEditor: (_, _) {},
        onManagePortfolios: () {},
        onOpenSettings: () {},
      );
      await tester.pumpWidget(_app(container, home()));
      await tester.pumpAndSettle();
      final Finder card = find.byType(NetWorthCard);
      Finder headline(String value) =>
          find.descendant(of: card, matching: find.text(value));
      expect(headline('₹1,65,34,234'), findsOneWidget);
      await tester.pumpWidget(_app(container, SettingsScreen(onClose: () {})));
      await tester.pumpAndSettle();
      final Finder toggle = find.text('Simple net worth');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(repository.current.simpleNetWorth, isTrue);
      await tester.pumpWidget(_app(container, home()));
      await tester.pumpAndSettle();
      expect(headline('₹1.65 Cr'), findsOneWidget);
      expect(headline('₹1,75,34,234'), findsOneWidget);
      expect(headline('₹10,00,000'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide balances'));
      await tester.pumpAndSettle();
      expect(headline('₹ ••••'), findsOneWidget);
      expect(headline('₹1.65 Cr'), findsNothing);
      expect(headline('••••'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Show balances'));
      await tester.pumpAndSettle();
      expect(headline('₹1.65 Cr'), findsOneWidget);
      await repository.setSimpleNetWorth(false);
      await tester.pumpAndSettle();
      expect(headline('₹1,65,34,234'), findsOneWidget);
      expect(headline('₹1.65 Cr'), findsNothing);
    },
  );

  testWidgets('failed saves show a snackbar and leave simple net worth off', (
    WidgetTester tester,
  ) async {
    final SettingsRepository failing = SettingsRepository(
      _RejectingPreferences(throwOnWrite: false),
    );
    addTearDown(failing.dispose);
    await tester.pumpWidget(
      _app(_Container(failing), SettingsScreen(onClose: () {})),
    );
    await tester.pumpAndSettle();
    final Finder toggle = find.text('Simple net worth');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(failing.current.simpleNetWorth, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining("Couldn't save simple net worth:"),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact headline supports USD, negative and small net worth', (
    WidgetTester tester,
  ) async {
    for (final (String, double, double, String) example
        in <(String, double, double, String)>[
          ('USD', 166342340, 1000000, '\$165.3M'),
          ('USD', 8054, 1000, '\$7K'),
          ('USD', 0, 7054, '-\$7K'),
          ('INR', 0, 16534234, '-₹1.65 Cr'),
          ('INR', 1200, 200, '₹1K'),
          ('INR', 1200, 201, '₹999'),
          ('INR', 0, 0, '₹0'),
        ]) {
      final (
        String currency,
        double assets,
        double liabilities,
        String expected,
      ) = example;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetWorthCard(
              summary: NetWorthSummary(
                baseCurrency: currency,
                totalAssets: assets,
                totalLiabilities: liabilities,
                assetBreakdown: const <CategoryTotal>[],
                liabilityBreakdown: const <CategoryTotal>[],
                hasApproximateConversions: false,
              ),
              hideBalances: false,
              simpleNetWorth: true,
            ),
          ),
        ),
      );
      expect(find.text(expected), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  test(
    'simple net worth messages are translated in all supported languages',
    () {
      for (final Locale locale in AppLocalizations.supportedLocales.skip(1)) {
        final AppLocalizations strings = AppLocalizations(locale);
        for (final String key in <String>[
          'Simple net worth',
          'Shorten the home net worth using currency-specific units',
          "Couldn't save simple net worth: {error}",
        ]) {
          expect(strings.text(key), isNot(key), reason: '$locale: $key');
        }
        expect(
          strings.text("Couldn't save simple net worth: Storage unavailable"),
          contains('Storage unavailable'),
        );
      }
    },
  );
}
