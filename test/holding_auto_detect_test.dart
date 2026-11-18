import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:okanzo/ui/components/holding_editor_chrome.dart';
import 'package:okanzo/ui/components/holding_saved_summary_screen.dart';
import 'package:okanzo/ui/holding/holding_create_form_state.dart';
import 'package:okanzo/ui/holding/holding_create_screen.dart';
import 'package:okanzo/ui/holding/holding_create_view_model.dart';
import 'package:okanzo/ui/navigation/app_shell.dart';
import 'package:okanzo/ui/theme/theme.dart';
import 'package:okanzo/util/app_lock_coordinator.dart';
import 'package:okanzo/util/backup_file_picker.dart';
import 'package:okanzo/util/biometric_authenticator.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBiometrics extends Fake implements BiometricAuthenticator {}

class _FakeAssets extends Fake implements AssetRepository {
  final StreamController<List<AssetEntity>> _controller =
      StreamController<List<AssetEntity>>.broadcast();
  final List<AssetEntity> items = <AssetEntity>[];
  AssetEntity? lastSaved;
  Completer<int>? pendingSave;
  final List<Completer<Result<StockQuote>>> pendingQuotes =
      <Completer<Result<StockQuote>>>[];
  bool delayQuotes = false;

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
    if (pendingSave != null) {
      final int customId = await pendingSave!.future;
      final AssetEntity persisted = asset.copyWith(
        id: customId,
        position: items.length,
      );
      lastSaved = persisted;
      items.add(persisted);
      _controller.add(List<AssetEntity>.unmodifiable(items));
      return persisted.id;
    }
    final AssetEntity persisted = asset.copyWith(
      id: items.length + 1,
      position: items.length,
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
  }) {
    if (delayQuotes) {
      final Completer<Result<StockQuote>> completer =
          Completer<Result<StockQuote>>();
      pendingQuotes.add(completer);
      return completer.future;
    }
    return Future<Result<StockQuote>>.value(Result<StockQuote>.offline());
  }

  @override
  Future<Result<double>> convertPrice(
    double price,
    String from,
    String to,
  ) async => Result<double>.success(price);

  Future<void> dispose() => _controller.close();
}

class _FakeLiabilities extends Fake implements LiabilityRepository {
  final StreamController<List<LiabilityEntity>> _controller =
      StreamController<List<LiabilityEntity>>.broadcast();
  final List<LiabilityEntity> items = <LiabilityEntity>[];
  LiabilityEntity? lastSaved;
  Completer<int>? pendingSave;

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
    if (pendingSave != null) {
      final int customId = await pendingSave!.future;
      final LiabilityEntity persisted = liability.copyWith(
        id: customId,
        position: items.length,
      );
      lastSaved = persisted;
      items.add(persisted);
      _controller.add(List<LiabilityEntity>.unmodifiable(items));
      return persisted.id;
    }
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
  }) : biometricAuthenticator = _FakeBiometrics(),
       appLock = AppLockCoordinator(authenticator: _FakeBiometrics());

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
  final BiometricAuthenticator biometricAuthenticator;
  @override
  final BackupFilePicker backupFilePicker = const SystemBackupFilePicker();
  @override
  final DateTime Function() clock = DateTime.now;
  @override
  final AppLockCoordinator appLock;

  @override
  AppDatabase get database => throw UnimplementedError();
  @override
  BackupRepository get backupRepository => throw UnimplementedError();
}

Finder _field(String label) => find.byWidgetPredicate(
  (Widget widget) => widget is LabeledTextField && widget.label == label,
);

Finder get _saveButton => find.descendant(
  of: find.byType(HoldingEditorFooter),
  matching: find.byType(FilledButton),
);

Finder get _cancelButton => find.descendant(
  of: find.byType(HoldingEditorFooter),
  matching: find.byType(OutlinedButton),
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

Finder _editorScrollable() {
  final Finder scoped = find.descendant(
    of: find.byType(HoldingCreateScreen),
    matching: find.byType(Scrollable),
  );
  return scoped.evaluate().isNotEmpty
      ? scoped.first
      : find.byType(Scrollable).first;
}

Future<void> _tapVisible(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
}) async {
  final Finder list = scrollable ?? _editorScrollable();
  if (target.evaluate().isEmpty && list.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(target, 120, scrollable: list);
  }
  if (find
      .ancestor(of: target, matching: find.byType(Scrollable))
      .evaluate()
      .isNotEmpty) {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.3);
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enterField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final Finder field = _field(label);
  if (field.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      field,
      120,
      scrollable: _editorScrollable(),
    );
  }
  await Scrollable.ensureVisible(tester.element(field), alignment: 0.3);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(TextField)),
    value,
  );
  await tester.pumpAndSettle();
}

Future<void> _selectType(WidgetTester tester, HoldingType target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final Finder editorScroll = _editorScrollable();
  if (editorScroll.evaluate().isNotEmpty) {
    tester.state<ScrollableState>(editorScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
  }
  await _tapVisible(
    tester,
    find.byKey(const ValueKey<String>('holding-type-chip')),
  );
  final Finder option = find.byKey(ValueKey<HoldingType>(target));
  await _tapVisible(
    tester,
    option,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey<String>('holding-type-list')),
      matching: find.byType(Scrollable),
    ),
  );
}

void main() {
  group('HoldingType and HoldingCreateFormState automatic detection', () {
    test('classifies all 10 selectable asset types (including Valuables) and 6 liability types automatically', () {
      expect(HoldingType.assetTypes, hasLength(AssetType.values.length - 1));
      expect(
        HoldingType.assetTypes,
        isNot(contains(const HoldingType.asset(AssetType.gold))),
      );
      expect(
        HoldingType.assetTypes,
        contains(const HoldingType.asset(AssetType.metals)),
      );
      expect(
        HoldingType.liabilityTypes,
        hasLength(LiabilityType.values.length),
      );
      expect(
        HoldingType.values,
        hasLength(HoldingType.assetTypes.length + LiabilityType.values.length),
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
    });

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
        const HoldingCreateFormState missingTickerStock =
            HoldingCreateFormState(
              holdingType: HoldingType.asset(AssetType.stock),
            );
        expect(missingTickerStock.validate(), 'Enter a ticker symbol');

        const HoldingCreateFormState unnamedCash = HoldingCreateFormState(
          holdingType: HoldingType.asset(AssetType.cash),
        );
        expect(unnamedCash.validate(), 'Give this asset a name');

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
        await tester.tap(find.byKey(const ValueKey<String>('add-holding')));
        await tester.pumpAndSettle();

        expect(find.byType(HoldingCreateScreen), findsOneWidget);
        expect(find.text('New asset'), findsNothing);
        expect(find.text('New liability'), findsNothing);
        expect(find.text('An asset'), findsNothing);
        expect(find.text('A liability'), findsNothing);
        expect(find.text('New entry'), findsOneWidget);
        expect(find.text('Asset'), findsOneWidget);
        expect(find.text('Added to net worth'), findsOneWidget);

        // Switch to Cash (flat asset), enter a value/name, then switch to Credit card:
        // flat amount, name, and currency all carry over seamlessly.
        await _selectType(tester, const HoldingType.asset(AssetType.cash));
        expect(find.text('Asset'), findsOneWidget);
        expect(find.text('Added to net worth'), findsOneWidget);
        await _enterField(tester, 'Value', '1450');
        await _enterField(tester, 'Name', 'Sapphire card');

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

        await tester.tap(_saveButton);
        await tester.pumpAndSettle();
        expect(find.byType(HoldingSavedSummaryScreen), findsOneWidget);
        expect(find.text('Liability added.'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey<String>('back-to-portfolio')),
        );
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

        await tester.tap(find.byKey(const ValueKey<String>('add-holding')));
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
        await _enterField(tester, 'Value', '9500');
        await _enterField(tester, 'Name', 'High-yield savings');
        await tester.tap(_saveButton);
        await tester.pumpAndSettle();
        expect(find.byType(HoldingSavedSummaryScreen), findsOneWidget);
        expect(find.text('Asset added.'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey<String>('back-to-portfolio')),
        );
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

    test('persistence lock blocks input/type/currency resets and superseded quotes from clearing active saves', () async {
      container.assetRepository.delayQuotes = true;
      final Completer<int> assetInsert = Completer<int>();
      container.assetRepository.pendingSave = assetInsert;

      final HoldingCreateViewModel vm = HoldingCreateViewModel(
        assetRepository: container.assetRepository,
        liabilityRepository: container.liabilityRepository,
        settingsRepository: container.settingsRepository,
        portfolioId: 1,
      );
      addTearDown(vm.dispose);

      // 1. Start Save #1 on an unpriced Stock -> enters pre-save quote lookup.
      vm.onSymbolChange('AAPL');
      vm.onQuantityChange('2');
      final Future<void> firstSave = vm.save();
      expect(vm.form.isPreparingSave, isTrue);
      expect(vm.form.isPersisting, isFalse);
      expect(vm.form.isSaving, isTrue);
      expect(container.assetRepository.pendingQuotes, hasLength(1));

      // 2. User changes type to Cash and starts Save #2 before Save #1's quote
      // resolves. Save #2 immediately enters repository persistence.
      vm.onTypeChange(const HoldingType.asset(AssetType.cash));
      expect(vm.form.isPreparingSave, isFalse);
      vm.onNameChange('Reserve');
      vm.onFlatAmountChange('500');
      final Future<void> secondSave = vm.save();
      expect(vm.form.isPersisting, isTrue);
      expect(vm.form.isSaving, isTrue);

      // 3. Save #1's superseded quote resolves while Save #2 is persisting ->
      // must NOT clear Save #2's persistence lock or save AAPL.
      container.assetRepository.pendingQuotes.first.complete(
        Result<StockQuote>.success(
          const StockQuote(
            symbol: 'AAPL',
            price: 210,
            currency: 'USD',
            name: 'Apple Inc.',
          ),
        ),
      );
      await firstSave;
      expect(vm.form.isPersisting, isTrue);
      expect(vm.form.isSaving, isTrue);

      // 4. Attempting to switch type to Credit card, change currency, cancel,
      // or trigger another save during repository insert must be ignored.
      vm.onTypeChange(const HoldingType.liability(LiabilityType.creditCard));
      await vm.onCurrencyChange('EUR');
      vm.cancel();
      final Future<void> duplicateSave = vm.save();
      await duplicateSave;

      expect(vm.form.isPersisting, isTrue);
      expect(vm.form.holdingType, const HoldingType.asset(AssetType.cash));
      expect(vm.form.currency, 'USD');
      expect(container.liabilityRepository.items, isEmpty);

      // 5. Complete repository insert -> saves exactly once to assets.
      assetInsert.complete(7);
      await secondSave;
      expect(vm.form.isPersisting, isFalse);
      expect(vm.form.isSaving, isFalse);
      expect(container.assetRepository.items, hasLength(1));
      expect(container.assetRepository.items.single.type, AssetType.cash);
      expect(container.liabilityRepository.items, isEmpty);
    });

    testWidgets(
      'inline Cancel remains enabled during pre-save quote lookup, cancels without persisting, and disables during repository write',
      (WidgetTester tester) async {
        container.assetRepository.delayQuotes = true;

        await tester.pumpWidget(_wrap(container, const AppShell()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('add-holding')));
        await tester.pumpAndSettle();

        // Enter a manual ticker via the Canvas market search modal + quantity.
        await _tapVisible(
          tester,
          find.byKey(const ValueKey<String>('market-search-trigger')),
        );
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'AAPL',
        );
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();

        await _enterField(tester, 'Quantity', '3');

        // Tap Save asset -> enters automatic pre-save quote lookup.
        await tester.tap(_saveButton);
        await tester.pump();

        expect(container.assetRepository.pendingQuotes, hasLength(1));
        expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);
        // Inline Cancel must remain enabled throughout the pre-save network wait!
        expect(
          tester.widget<OutlinedButton>(_cancelButton).onPressed,
          isNotNull,
        );

        await tester.tap(_cancelButton);
        await tester.pumpAndSettle();
        expect(find.byType(HoldingCreateScreen), findsNothing);
        expect(container.assetRepository.items, isEmpty);

        // Resolving the pending quote afterward must not persist anything.
        container.assetRepository.pendingQuotes.single.complete(
          Result<StockQuote>.success(
            const StockQuote(
              symbol: 'AAPL',
              price: 225,
              currency: 'USD',
              name: 'Apple Inc.',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(container.assetRepository.items, isEmpty);

        // Now verify that once an actual repository write is in progress,
        // inline Cancel IS disabled until persistence completes.
        final Completer<int> pendingWrite = Completer<int>();
        container.assetRepository.pendingSave = pendingWrite;

        await tester.tap(find.byKey(const ValueKey<String>('add-holding')));
        await tester.pumpAndSettle();
        await _selectType(tester, const HoldingType.asset(AssetType.cash));
        await _enterField(tester, 'Value', '400');
        await _enterField(tester, 'Name', 'Wallet cash');

        await tester.tap(_saveButton);
        await tester.pump();

        expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);
        expect(tester.widget<OutlinedButton>(_cancelButton).onPressed, isNull);

        pendingWrite.complete(1);
        await tester.pumpAndSettle();
        expect(find.byType(HoldingSavedSummaryScreen), findsOneWidget);
        expect(container.assetRepository.items, hasLength(1));
      },
    );

    testWidgets(
      'type picker exposes selected accessibility state through Semantics',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _wrap(
              container,
              const HoldingCreateScreen(
                portfolioId: 1,
                initialType: HoldingType.asset(AssetType.cash),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await _tapVisible(
            tester,
            find.byKey(const ValueKey<String>('holding-type-chip')),
          );

          final Finder cashRow = find.byKey(
            const ValueKey<HoldingType>(HoldingType.asset(AssetType.cash)),
          );
          final Finder bankDepositRow = find.byKey(
            const ValueKey<HoldingType>(
              HoldingType.asset(AssetType.bankDeposit),
            ),
          );

          final Finder sheetScrollable = find.descendant(
            of: find.byKey(const ValueKey<String>('holding-type-list')),
            matching: find.byType(Scrollable),
          );
          if (bankDepositRow.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              bankDepositRow,
              80,
              scrollable: sheetScrollable,
            );
          }
          await tester.pumpAndSettle();

          final SemanticsNode cashNode = tester.getSemantics(cashRow);
          expect(
            cashNode.getSemanticsData().flagsCollection.isSelected,
            Tristate.isTrue,
          );
          expect(cashNode.getSemanticsData().flagsCollection.isButton, isTrue);

          final SemanticsNode bankNode = tester.getSemantics(bankDepositRow);
          expect(
            bankNode.getSemanticsData().flagsCollection.isSelected,
            Tristate.isFalse,
          );
          expect(bankNode.getSemanticsData().flagsCollection.isButton, isTrue);
        } finally {
          semantics.dispose();
        }
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

        await _tapVisible(
          tester,
          find.byKey(const ValueKey<String>('holding-type-chip')),
        );
        expect(tester.takeException(), isNull);

        final Finder otherLiability = find.byKey(
          const ValueKey<HoldingType>(
            HoldingType.liability(LiabilityType.other),
          ),
        );
        await _tapVisible(
          tester,
          otherLiability,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey<String>('holding-type-list')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
