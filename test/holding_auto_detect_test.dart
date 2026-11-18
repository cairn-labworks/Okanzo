import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okanzo/data/backup/backup_repository.dart';
import 'package:okanzo/data/local/app_database.dart';
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
import 'package:okanzo/domain/model/holding_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/holding/holding_create_form_state.dart';
import 'package:okanzo/ui/holding/holding_create_screen.dart';
import 'package:okanzo/ui/navigation/app_shell.dart';
import 'package:okanzo/ui/theme/theme.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAssets extends Fake implements AssetRepository {
  final StreamController<List<AssetEntity>> _controller =
      StreamController<List<AssetEntity>>.broadcast();
  final List<AssetEntity> items = <AssetEntity>[];
  AssetEntity? lastSaved;

  @override
  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) async* {
    yield List<AssetEntity>.unmodifiable(items);
    yield* _controller.stream;
  }

  @override
  Future<List<AssetEntity>> getForPortfolio(int portfolioId) async =>
      List<AssetEntity>.unmodifiable(items);

  @override
  Future<int> save(AssetEntity asset) async {
    final AssetEntity persisted = AssetEntity(
      id: items.length + 1,
      portfolioId: asset.portfolioId,
      type: asset.type,
      name: asset.name,
      currency: asset.currency,
      quantity: asset.quantity,
      pricePerUnit: asset.pricePerUnit,
      symbol: asset.symbol,
      lastPrice: asset.lastPrice,
      lastPriceTimestamp: asset.lastPriceTimestamp,
      manualValue: asset.manualValue,
      notes: asset.notes,
      position: items.length,
      createdAt: asset.createdAt,
      updatedAt: asset.updatedAt,
    );
    lastSaved = persisted;
    items.add(persisted);
    _controller.add(List<AssetEntity>.unmodifiable(items));
    return persisted.id;
  }

  @override
  Future<Result<StockQuote>> fetchQuote(
    String symbol, {
    required String currency,
    bool isCrypto = false,
  }) async => Result<StockQuote>.offline();

  Future<void> dispose() => _controller.close();
}

class _FakeLiabilities extends Fake implements LiabilityRepository {
  final StreamController<List<LiabilityEntity>> _controller =
      StreamController<List<LiabilityEntity>>.broadcast();
  final List<LiabilityEntity> items = <LiabilityEntity>[];
  LiabilityEntity? lastSaved;

  @override
  Stream<List<LiabilityEntity>> observeForPortfolio(int portfolioId) async* {
    yield List<LiabilityEntity>.unmodifiable(items);
    yield* _controller.stream;
  }

  @override
  Future<List<LiabilityEntity>> getForPortfolio(int portfolioId) async =>
      List<LiabilityEntity>.unmodifiable(items);

  @override
  Future<int> save(LiabilityEntity liability) async {
    final LiabilityEntity persisted = LiabilityEntity(
      id: items.length + 1,
      portfolioId: liability.portfolioId,
      type: liability.type,
      name: liability.name,
      currency: liability.currency,
      amount: liability.amount,
      notes: liability.notes,
      position: items.length,
      createdAt: liability.createdAt,
      updatedAt: liability.updatedAt,
    );
    lastSaved = persisted;
    items.add(persisted);
    _controller.add(List<LiabilityEntity>.unmodifiable(items));
    return persisted.id;
  }

  Future<void> dispose() => _controller.close();
}

class _FakePortfolios extends Fake implements PortfolioRepository {
  @override
  Future<int> ensureDefaultPortfolio([
    String defaultName = 'My Portfolio',
  ]) async => 1;

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
}

class _FakeFx extends Fake implements FxRepository {
  @override
  Stream<CurrencyConverter> get converter =>
      Stream<CurrencyConverter>.value(const CurrencyConverter.empty());

  @override
  Future<int?> latestTimestamp() async => null;

  @override
  Future<Result<void>> ensureFreshRates([int maxAgeMillis = 0]) async =>
      Result<void>.success(null);
}

class _FakeSearch extends Fake implements StockSearchService {
  @override
  Future<Result<List<StockSearchResult>>> search(
    String query, {
    StockSearchType type = StockSearchType.stock,
  }) async => Result<List<StockSearchResult>>.offline();
}

class _TestContainer implements AppContainer {
  _TestContainer({
    required this.settingsRepository,
    required this.assetRepository,
    required this.liabilityRepository,
  });

  @override
  final SettingsRepository settingsRepository;
  @override
  final _FakeAssets assetRepository;
  @override
  final _FakeLiabilities liabilityRepository;
  @override
  final PortfolioRepository portfolioRepository = _FakePortfolios();
  @override
  final FxRepository fxRepository = _FakeFx();
  @override
  final StockSearchService stockSearchService = _FakeSearch();

  @override
  AppDatabase get database => throw UnimplementedError();
  @override
  BackupRepository get backupRepository => throw UnimplementedError();
}

Finder _field(String label) => find.byWidgetPredicate(
  (Widget widget) => widget is LabeledTextField && widget.label == label,
);

Widget _wrap(
  AppContainer container,
  Widget home, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) {
  return AppScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(
        brightness: Brightness.dark,
        appTheme: AppTheme.midnight,
      ),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

Future<void> _selectType(WidgetTester tester, HoldingType target) async {
  await tester.tap(find.byKey(const ValueKey<String>('holding-type-chip')));
  await tester.pumpAndSettle();
  final Finder option = find.byKey(ValueKey<HoldingType>(target));
  await tester.scrollUntilVisible(
    option,
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

void main() {
  group('HoldingType and HoldingCreateFormState automatic detection', () {
    test(
      'classifies all 10 asset types and 6 liability types automatically',
      () {
        expect(HoldingType.assetTypes, hasLength(AssetType.values.length));
        expect(
          HoldingType.liabilityTypes,
          hasLength(LiabilityType.values.length),
        );
        expect(
          HoldingType.values,
          hasLength(AssetType.values.length + LiabilityType.values.length),
        );

        for (final AssetType assetType in AssetType.values) {
          final HoldingType holding = HoldingType.asset(assetType);
          expect(holding.kind, HoldingKind.asset);
          expect(holding.isAsset, isTrue);
          expect(holding.isLiability, isFalse);
        }

        for (final LiabilityType liabilityType in LiabilityType.values) {
          final HoldingType holding = HoldingType.liability(liabilityType);
          expect(holding.kind, HoldingKind.liability);
          expect(holding.isLiability, isTrue);
          expect(holding.isAsset, isFalse);
        }
      },
    );

    test('distinguishes Other asset and Other liability in picker while preserving OTHER storage name', () {
      const HoldingType otherAsset = HoldingType.asset(AssetType.other);
      const HoldingType otherLiability = HoldingType.liability(
        LiabilityType.other,
      );
      expect(otherAsset.pickerLabel, 'Other asset');
      expect(otherLiability.pickerLabel, 'Other liability');

      final AssetEntity asset = const HoldingCreateFormState(
        portfolioId: 3,
        holdingType: otherAsset,
        name: 'Collectibles',
        currency: 'USD',
        flatAmount: '1500',
      ).toAssetEntity(now: 100);
      expect(asset.type, AssetType.other);
      expect(asset.type.storageName, 'OTHER');
      expect(asset.manualValue, 1500);

      final LiabilityEntity liability = const HoldingCreateFormState(
        portfolioId: 3,
        holdingType: otherLiability,
        name: 'Security deposit owed',
        currency: 'USD',
        flatAmount: '1500',
      ).toLiabilityEntity(now: 100);
      expect(liability.type, LiabilityType.other);
      expect(liability.type.storageName, 'OTHER');
      expect(liability.amount, 1500);
    });

    test(
      'validates according to automatically detected asset or liability mode',
      () {
        const HoldingCreateFormState unnamedStock = HoldingCreateFormState(
          holdingType: HoldingType.asset(AssetType.stock),
        );
        expect(unnamedStock.validate(), 'Give this asset a name');

        const HoldingCreateFormState unnamedLoan = HoldingCreateFormState(
          holdingType: HoldingType.liability(LiabilityType.loan),
        );
        expect(unnamedLoan.validate(), 'Give this liability a name');

        const HoldingCreateFormState missingLoanAmount = HoldingCreateFormState(
          holdingType: HoldingType.liability(LiabilityType.creditCard),
          name: 'Travel card',
        );
        expect(missingLoanAmount.validate(), 'Enter an amount');

        const HoldingCreateFormState validCard = HoldingCreateFormState(
          holdingType: HoldingType.liability(LiabilityType.creditCard),
          name: 'Travel card',
          flatAmount: '850',
        );
        expect(validCard.validate(), isNull);
      },
    );
  });

  group('Unified HoldingCreateScreen and AppShell flow', () {
    late _TestContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'last_seen_version': AppReleaseNotes.currentVersion,
      });
      final SettingsRepository settings = SettingsRepository(
        await SharedPreferences.getInstance(),
      );
      container = _TestContainer(
        settingsRepository: settings,
        assetRepository: _FakeAssets(),
        liabilityRepository: _FakeLiabilities(),
      );
    });

    tearDown(() async {
      await container.assetRepository.dispose();
      await container.liabilityRepository.dispose();
      await container.settingsRepository.dispose();
    });

    testWidgets(
      'starting from Assets tab auto-detects Liability when selecting Credit card and switches Home to Liabilities on save',
      (WidgetTester tester) async {
        await tester.pumpWidget(_wrap(container, const AppShell()));
        await tester.pumpAndSettle();

        expect(find.text('No assets yet'), findsOneWidget);
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        expect(find.byType(HoldingCreateScreen), findsOneWidget);
        expect(find.text('New asset'), findsNothing);
        expect(find.text('New liability'), findsNothing);
        expect(find.text('New entry'), findsOneWidget);
        expect(find.text('Asset'), findsOneWidget);
        expect(find.text('Added to net worth'), findsOneWidget);

        // Switch to Cash (flat asset), enter a value/name/note, then switch to Credit card:
        // flat amount, name, currency, and notes all carry over seamlessly.
        await _selectType(tester, const HoldingType.asset(AssetType.cash));
        expect(find.text('Asset'), findsOneWidget);
        expect(find.text('Added to net worth'), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: _field('Value'),
            matching: find.byType(TextField),
          ),
          '1450',
        );
        await tester.enterText(
          find.descendant(of: _field('Name'), matching: find.byType(TextField)),
          'Sapphire card',
        );
        await tester.pumpAndSettle();

        await _selectType(
          tester,
          const HoldingType.liability(LiabilityType.creditCard),
        );
        expect(find.text('Liability'), findsOneWidget);
        expect(find.text('Subtracted from net worth'), findsOneWidget);
        expect(_field('Outstanding amount'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: _field('Outstanding amount'),
                  matching: find.byType(TextField),
                ),
              )
              .controller
              ?.text,
          '1450',
        );

        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, 'Save'),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(find.byType(HoldingCreateScreen), findsNothing);
        expect(container.assetRepository.items, isEmpty);
        expect(container.liabilityRepository.items, hasLength(1));
        expect(
          container.liabilityRepository.lastSaved?.type,
          LiabilityType.creditCard,
        );
        expect(container.liabilityRepository.lastSaved?.amount, 1450);
        // Home automatically switched to Liabilities so the new card is visible.
        expect(find.text('Credit card'), findsOneWidget);
      },
    );

    testWidgets(
      'starting from Liabilities tab defaults to Loan and auto-detects Asset when switched to Bank / deposit',
      (WidgetTester tester) async {
        await tester.pumpWidget(_wrap(container, const AppShell()));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('home-liabilities-tab')),
        );
        await tester.pumpAndSettle();
        expect(find.text('No liabilities'), findsOneWidget);

        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        expect(find.text('Liability'), findsOneWidget);
        expect(find.text('Subtracted from net worth'), findsOneWidget);
        expect(find.text('Loan'), findsOneWidget);

        await _selectType(
          tester,
          const HoldingType.asset(AssetType.bankDeposit),
        );
        expect(find.text('Asset'), findsOneWidget);
        expect(find.text('Added to net worth'), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: _field('Value'),
            matching: find.byType(TextField),
          ),
          '9500',
        );
        await tester.enterText(
          find.descendant(of: _field('Name'), matching: find.byType(TextField)),
          'High-yield savings',
        );
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, 'Save'),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(container.liabilityRepository.items, isEmpty);
        expect(container.assetRepository.items, hasLength(1));
        expect(
          container.assetRepository.lastSaved?.type,
          AssetType.bankDeposit,
        );
        expect(find.text('Bank / deposit'), findsOneWidget);
      },
    );

    testWidgets(
      'unified creation screen and grouped type sheet fit narrow 200% Arabic RTL layout',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _wrap(
            container,
            const HoldingCreateScreen(portfolioId: 1),
            locale: const Locale('ar'),
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(const ValueKey<String>('holding-type-chip')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final Finder otherLiability = find.byKey(
          const ValueKey<HoldingType>(
            HoldingType.liability(LiabilityType.other),
          ),
        );
        await tester.scrollUntilVisible(
          otherLiability,
          120,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(otherLiability);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
