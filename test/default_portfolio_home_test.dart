import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/navigation/app_shell.dart';
import 'package:okanzo/ui/portfolio/portfolio_screen.dart';
import 'package:okanzo/ui/statistics/statistics_screen.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemoryPortfolioRepository extends Fake implements PortfolioRepository {
  _InMemoryPortfolioRepository([List<PortfolioEntity>? initial])
    : _items = List<PortfolioEntity>.of(initial ?? const <PortfolioEntity>[]);

  final List<PortfolioEntity> _items;
  final StreamController<List<PortfolioEntity>> _controller =
      StreamController<List<PortfolioEntity>>.broadcast();
  int _nextId = 10;

  List<PortfolioEntity> _sorted() {
    final List<PortfolioEntity> copy = List<PortfolioEntity>.of(_items);
    copy.sort((PortfolioEntity a, PortfolioEntity b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return List<PortfolioEntity>.unmodifiable(copy);
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_sorted());
  }

  @override
  Stream<List<PortfolioEntity>> observeAll() async* {
    yield _sorted();
    yield* _controller.stream;
  }

  @override
  Future<List<PortfolioEntity>> getAll() async => _sorted();

  @override
  Future<PortfolioEntity?> getDefault() async {
    for (final PortfolioEntity item in _items) {
      if (item.isDefault) return item;
    }
    return null;
  }

  @override
  Future<int> create(String name, {bool makeDefault = false}) async {
    final bool isFirst = _items.isEmpty;
    final int id = _nextId++;
    _items.add(
      PortfolioEntity(
        id: id,
        name: name.trim(),
        isDefault: false,
        createdAt: 0,
        updatedAt: 0,
      ),
    );
    if (isFirst || makeDefault) {
      await setDefault(id);
    } else {
      _emit();
    }
    return id;
  }

  @override
  Future<void> setDefault(int id) async {
    for (int i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(isDefault: _items[i].id == id);
    }
    _emit();
  }

  @override
  Future<bool> delete(int id) async {
    if (_items.length <= 1) return false;
    final int index = _items.indexWhere(
      (PortfolioEntity item) => item.id == id,
    );
    if (index < 0) return false;
    final PortfolioEntity removed = _items.removeAt(index);
    _emit();
    if (removed.isDefault && _items.isNotEmpty) {
      await setDefault(_sorted().first.id);
    }
    return true;
  }

  @override
  Future<int> ensureDefaultPortfolio([
    String defaultName = 'My Portfolio',
  ]) async {
    final PortfolioEntity? existing = await getDefault();
    if (existing != null) return existing.id;
    if (_items.isNotEmpty) {
      final int firstId = _sorted().first.id;
      await setDefault(firstId);
      return firstId;
    }
    return create(defaultName, makeDefault: true);
  }

  Future<void> dispose() => _controller.close();
}

class _EmptyAssetRepository extends Fake implements AssetRepository {
  @override
  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<AssetEntity>>.value(const <AssetEntity>[]);

  @override
  Future<List<AssetEntity>> getForPortfolio(int portfolioId) async =>
      const <AssetEntity>[];
}

class _EmptyLiabilityRepository extends Fake implements LiabilityRepository {
  @override
  Stream<List<LiabilityEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<LiabilityEntity>>.value(const <LiabilityEntity>[]);

  @override
  Future<List<LiabilityEntity>> getForPortfolio(int portfolioId) async =>
      const <LiabilityEntity>[];
}

class _NoopFxRepository extends Fake implements FxRepository {
  @override
  Stream<CurrencyConverter> get converter =>
      Stream<CurrencyConverter>.value(const CurrencyConverter.empty());

  @override
  Future<Result<void>> ensureFreshRates([int maxAgeMillis = 0]) async =>
      Result<void>.success(null);

  @override
  Future<int?> latestTimestamp() async => null;
}

class _FakeBackupRepository extends Fake implements BackupRepository {}

class _TestContainer extends Fake implements AppContainer {
  _TestContainer({
    required this.settingsRepository,
    required this.portfolioRepository,
  });

  @override
  final SettingsRepository settingsRepository;

  @override
  final PortfolioRepository portfolioRepository;

  @override
  final AssetRepository assetRepository = _EmptyAssetRepository();

  @override
  final LiabilityRepository liabilityRepository = _EmptyLiabilityRepository();

  @override
  final FxRepository fxRepository = _NoopFxRepository();

  @override
  final BackupRepository backupRepository = _FakeBackupRepository();
}

Widget _shellApp(_TestContainer container) => AppScope(
  container: container,
  child: const MaterialApp(home: AppShell()),
);

Finder _homeTitle(String name) => find.descendant(
  of: find.descendant(
    of: find.byType(HomeScreen),
    matching: find.byType(AppBar),
  ),
  matching: find.text(name),
);

Finder _statsTitle(String name) => find.descendant(
  of: find.descendant(
    of: find.byType(StatisticsScreen),
    matching: find.byType(AppBar),
  ),
  matching: find.text(name),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold launch starts with no selected portfolio override even if legacy pref exists', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'USD',
      'selected_portfolio_id': 1,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsRepository firstSession = SettingsRepository(prefs);
    addTearDown(firstSession.dispose);

    expect(firstSession.current.selectedPortfolioId, isNull);

    await firstSession.setSelectedPortfolioId(2);
    expect(firstSession.current.selectedPortfolioId, 2);

    // A new session (simulating app relaunch) resets to null so Home shows Default.
    final SettingsRepository relaunchedSession = SettingsRepository(prefs);
    addTearDown(relaunchedSession.dispose);
    expect(relaunchedSession.current.selectedPortfolioId, isNull);
  });

  testWidgets('changing default portfolio updates Home and Statistics even after switching portfolios, '
      'and relaunch opens the Default portfolio', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'USD',
      'last_seen_version': AppReleaseNotes.currentVersion,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsRepository settings = SettingsRepository(prefs);
    final _InMemoryPortfolioRepository portfolios =
        _InMemoryPortfolioRepository(<PortfolioEntity>[
          const PortfolioEntity(
            id: 1,
            name: 'My Portfolio',
            isDefault: true,
            createdAt: 0,
            updatedAt: 0,
          ),
        ]);
    addTearDown(settings.dispose);
    addTearDown(portfolios.dispose);

    final _TestContainer container = _TestContainer(
      settingsRepository: settings,
      portfolioRepository: portfolios,
    );

    await tester.pumpWidget(_shellApp(container));
    await tester.pumpAndSettle();

    // 1. With one portfolio, Home shows the Default portfolio.
    expect(_homeTitle('My Portfolio'), findsOneWidget);

    // 2. Navigate to Portfolios tab and create a new portfolio "Retirement".
    await tester.tap(find.text('Portfolios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Retirement');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // 3. Return to Home, explicitly select "My Portfolio" from the switcher
    //    (setting selectedPortfolioId = 1 in the active session).
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch portfolio'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('My Portfolio  •  Default').last);
    await tester.pumpAndSettle();
    expect(settings.current.selectedPortfolioId, 1);
    expect(_homeTitle('My Portfolio'), findsOneWidget);

    // 4. Go to Portfolios and mark "Retirement" as the new Default portfolio.
    await tester.tap(find.text('Portfolios'));
    await tester.pumpAndSettle();
    final Finder retirementCard = find.ancestor(
      of: find.text('Retirement'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: retirementCard, matching: find.byTooltip('More')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as default'));
    await tester.pumpAndSettle();

    expect(settings.current.selectedPortfolioId, isNull);

    // 5. Home and Statistics must immediately show the new Default ("Retirement"),
    //    not the old default ("My Portfolio").
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(_homeTitle('Retirement'), findsOneWidget);
    expect(_homeTitle('My Portfolio'), findsNothing);

    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();
    expect(_statsTitle('Retirement'), findsOneWidget);

    // 6. Temporarily switch back to non-default "My Portfolio" during this session.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch portfolio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Portfolio').last);
    await tester.pumpAndSettle();
    expect(_homeTitle('My Portfolio'), findsOneWidget);

    // 7. Simulate closing and reopening the app: Home must open on Default ("Retirement").
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final SettingsRepository relaunchedSettings = SettingsRepository(prefs);
    addTearDown(relaunchedSettings.dispose);
    final _TestContainer relaunchedContainer = _TestContainer(
      settingsRepository: relaunchedSettings,
      portfolioRepository: portfolios,
    );
    await tester.pumpWidget(_shellApp(relaunchedContainer));
    await tester.pumpAndSettle();

    expect(_homeTitle('Retirement'), findsOneWidget);
    expect(_homeTitle('My Portfolio'), findsNothing);
  });

  testWidgets(
    'deleting the default portfolio promotes the remaining default and shows it on Home',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'base_currency': 'USD',
        'last_seen_version': AppReleaseNotes.currentVersion,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final SettingsRepository settings = SettingsRepository(prefs);
      final _InMemoryPortfolioRepository portfolios =
          _InMemoryPortfolioRepository(<PortfolioEntity>[
            const PortfolioEntity(
              id: 1,
              name: 'Alpha',
              isDefault: true,
              createdAt: 0,
              updatedAt: 0,
            ),
            const PortfolioEntity(
              id: 2,
              name: 'Beta',
              isDefault: false,
              createdAt: 0,
              updatedAt: 0,
            ),
            const PortfolioEntity(
              id: 3,
              name: 'Gamma',
              isDefault: false,
              createdAt: 0,
              updatedAt: 0,
            ),
          ]);
      addTearDown(settings.dispose);
      addTearDown(portfolios.dispose);

      final _TestContainer container = _TestContainer(
        settingsRepository: settings,
        portfolioRepository: portfolios,
      );

      await tester.pumpWidget(_shellApp(container));
      await tester.pumpAndSettle();
      expect(_homeTitle('Alpha'), findsOneWidget);

      // Select Gamma explicitly, then delete Alpha (the Default), which promotes Beta.
      await settings.setSelectedPortfolioId(3);
      await tester.pumpAndSettle();
      expect(_homeTitle('Gamma'), findsOneWidget);

      await tester.tap(find.text('Portfolios'));
      await tester.pumpAndSettle();
      final Finder alphaCard = find.ancestor(
        of: find.text('Alpha'),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(of: alphaCard, matching: find.byTooltip('More')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(PortfolioScreen), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(_homeTitle('Beta'), findsOneWidget);
    },
  );

  testWidgets(
    'Portfolios distinguishes Viewing from Default and switches active portfolio on tap',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'base_currency': 'USD',
        'last_seen_version': AppReleaseNotes.currentVersion,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final SettingsRepository settings = SettingsRepository(prefs);
      final _InMemoryPortfolioRepository portfolios =
          _InMemoryPortfolioRepository(<PortfolioEntity>[
            const PortfolioEntity(
              id: 1,
              name: 'Personal',
              isDefault: true,
              createdAt: 0,
              updatedAt: 0,
            ),
            const PortfolioEntity(
              id: 2,
              name: 'Family Household',
              isDefault: false,
              createdAt: 0,
              updatedAt: 0,
            ),
          ]);
      addTearDown(settings.dispose);
      addTearDown(portfolios.dispose);

      final _TestContainer container = _TestContainer(
        settingsRepository: settings,
        portfolioRepository: portfolios,
      );

      await tester.pumpWidget(_shellApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Portfolios'));
      await tester.pumpAndSettle();

      final Finder personalCard = find.ancestor(
        of: find.text('Personal'),
        matching: find.byType(Card),
      );
      final Finder familyCard = find.ancestor(
        of: find.text('Family Household'),
        matching: find.byType(Card),
      );

      // Initially Personal is both Viewing and Default
      expect(
        find.descendant(of: personalCard, matching: find.text('Viewing')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: personalCard, matching: find.text('Default')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: familyCard, matching: find.text('Viewing')),
        findsNothing,
      );

      // Tapping Family Household switches Viewing to Family Household while Default stays on Personal
      await tester.tap(familyCard);
      await tester.pumpAndSettle();
      expect(settings.current.selectedPortfolioId, 2);
      expect(
        find.descendant(of: familyCard, matching: find.text('Viewing')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: personalCard, matching: find.text('Viewing')),
        findsNothing,
      );
      expect(
        find.descendant(of: personalCard, matching: find.text('Default')),
        findsOneWidget,
      );

      // Home immediately reflects the newly selected portfolio
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(_homeTitle('Family Household'), findsOneWidget);
    },
  );
}
