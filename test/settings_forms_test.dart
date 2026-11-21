import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:okanzo/domain/model/precious_metal.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/asset/stock_exchange_field.dart';
import 'package:okanzo/ui/components/donut_chart.dart';
import 'package:okanzo/ui/asset/stock_search_field.dart';
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/components/holding_editor_chrome.dart';
import 'package:okanzo/ui/components/holding_create_screen.dart';
import 'package:okanzo/ui/components/holding_saved_summary_screen.dart';
import 'package:okanzo/ui/components/drag_reorder_column.dart';
import 'package:okanzo/ui/components/type_icons.dart';
import 'package:okanzo/ui/components/ui_components.dart';
import 'package:okanzo/ui/components/whats_new_dialog.dart';
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/home/category_groups.dart';
import 'package:okanzo/ui/home/holding_group_list.dart';
import 'package:okanzo/ui/home/add_holding_button.dart';
import 'package:okanzo/ui/home/net_worth_card.dart';
import 'package:okanzo/ui/liability/liability_edit_screen.dart';
import 'package:okanzo/ui/lock/lock_screen.dart';
import 'package:okanzo/ui/navigation/app_shell.dart';
import 'package:okanzo/ui/portfolio/portfolio_screen.dart';
import 'package:okanzo/ui/settings/settings_screen.dart';
import 'package:okanzo/ui/settings/settings_view_model.dart';
import 'package:okanzo/ui/statistics/statistics_screen.dart';
import 'package:okanzo/ui/theme/theme.dart';
import 'package:okanzo/ui/theme/app_style.dart';
import 'package:okanzo/util/result.dart';
import 'package:okanzo/util/currency_util.dart';
import 'package:okanzo/util/screenshot_protection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okanzo/util/app_lock_coordinator.dart';
import 'package:okanzo/util/biometric_authenticator.dart';

import 'helpers/fake_biometric_authenticator.dart';

class _Assets extends Fake implements AssetRepository {
  AssetEntity? existing;
  AssetEntity? saved;
  int? deleted;
  List<int>? lastOrder;
  List<AssetEntity> items = const <AssetEntity>[];
  int quoteFetches = 0;
  Future<Result<StockQuote>>? pendingQuote;
  Future<Result<double>>? pendingMetalPrice;

  @override
  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<AssetEntity>>.value(items);

  @override
  Future<List<AssetEntity>> getForPortfolio(int portfolioId) async => items;

  @override
  Future<AssetEntity?> getById(int id) async => existing;

  @override
  Future<int> save(AssetEntity asset) async {
    saved = asset;
    return asset.id == 0 ? 1 : asset.id;
  }

  @override
  Future<void> delete(int id) async => deleted = id;

  @override
  Future<void> updateOrder(List<int> ids) async =>
      lastOrder = List<int>.of(ids);

  @override
  Future<Result<StockQuote>> fetchQuote(
    String symbol, {
    required String currency,
    bool isCrypto = false,
  }) async {
    quoteFetches++;
    return pendingQuote == null
        ? Result<StockQuote>.offline()
        : await pendingQuote!;
  }

  @override
  Future<Result<double>> fetchMetalPrice(
    PreciousMetal metal,
    String purity, {
    required String currency,
  }) async =>
      await (pendingMetalPrice ?? Future.value(Result<double>.offline()));
}

class _Liabilities extends Fake implements LiabilityRepository {
  LiabilityEntity? existing;
  LiabilityEntity? saved;
  int? deleted;
  List<int>? lastOrder;
  List<LiabilityEntity> items = const <LiabilityEntity>[];

  @override
  Stream<List<LiabilityEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<LiabilityEntity>>.value(items);

  @override
  Future<List<LiabilityEntity>> getForPortfolio(int portfolioId) async => items;

  @override
  Future<LiabilityEntity?> getById(int id) async => existing;

  @override
  Future<int> save(LiabilityEntity liability) async {
    saved = liability;
    return liability.id == 0 ? 1 : liability.id;
  }

  @override
  Future<void> delete(int id) async => deleted = id;

  @override
  Future<void> updateOrder(List<int> ids) async =>
      lastOrder = List<int>.of(ids);
}

class _Portfolios extends Fake implements PortfolioRepository {
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

class _Rates extends Fake implements FxRepository {
  int refreshes = 0;
  CurrencyConverter rates = const CurrencyConverter.empty();

  @override
  Stream<CurrencyConverter> get converter =>
      Stream<CurrencyConverter>.value(rates);

  @override
  Future<Result<void>> ensureFreshRates([int maxAgeMillis = 0]) async =>
      Result<void>.success(null);

  @override
  Future<int?> latestTimestamp() async => null;

  @override
  Future<Result<void>> refreshRates() async {
    refreshes++;
    return Result<void>.success(null);
  }
}

class _Backups extends Fake implements BackupRepository {}

class _Search extends Fake implements StockSearchService {
  List<StockSearchResult> matches = <StockSearchResult>[];

  @override
  Future<Result<List<StockSearchResult>>> search(
    String query, {
    required StockSearchType type,
  }) async => Result<List<StockSearchResult>>.success(matches);
}

class _FailingAppearanceRepository extends SettingsRepository {
  _FailingAppearanceRepository(super.preferences);

  @override
  Future<void> setAppearanceMode(AppThemeMode mode) async {
    throw StateError('Storage unavailable');
  }
}

class _RejectingScreenshotPreferences extends Fake
    implements SharedPreferences {
  _RejectingScreenshotPreferences({required this.throwOnWrite});

  final bool throwOnWrite;
  bool? cachedValue;
  int reloads = 0;

  @override
  String? getString(String key) => key == 'base_currency' ? 'USD' : null;

  @override
  bool? getBool(String key) => key == 'block_screenshots' ? cachedValue : null;

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
    cachedValue = null;
  }
}

class _Container extends Fake implements AppContainer {
  _Container(this.settingsRepository);

  @override
  final SettingsRepository settingsRepository;
  final FakeBiometricAuthenticator authenticator = FakeBiometricAuthenticator();
  @override
  late final AppLockCoordinator appLock = AppLockCoordinator(
    authenticator: authenticator,
  );
  @override
  final _Assets assetRepository = _Assets();
  @override
  final _Search stockSearchService = _Search();
  @override
  final _Liabilities liabilityRepository = _Liabilities();
  @override
  final _Portfolios portfolioRepository = _Portfolios();
  @override
  final _Rates fxRepository = _Rates();
  @override
  final _Backups backupRepository = _Backups();
}

Widget _app(
  _Container container,
  Widget page, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  AppTheme appTheme = AppTheme.classic,
}) => AppScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(brightness: brightness, appTheme: appTheme),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => page)),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

Finder _field(String label) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is OptionalCustomNameField && widget.label == label ||
      (widget is LabeledTextField && widget.showLabel && widget.label == label),
);

Finder _marketTrigger() => find.byWidgetPredicate(
  (Widget widget) =>
      widget.key == const ValueKey<String>('market-search-trigger') ||
      widget.key == const ValueKey<String>('selected-market-holding'),
);

Finder get _dialogSearchInput => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

Future<void> _openMarketSearch(WidgetTester tester) async {
  await _tap(tester, _marketTrigger());
}

Future<void> _enterManualTicker(WidgetTester tester, String value) async {
  await _openMarketSearch(tester);
  await tester.enterText(_dialogSearchInput, value);
  await tester.pump();
  await _tap(tester, find.byKey(const ValueKey<String>('use-manual-ticker')));
}

Finder _textField(String label) =>
    find.descendant(of: _field(label), matching: find.byType(TextField));
Finder get _customNameToggle =>
    find.byKey(const ValueKey<String>('custom-name-toggle'));
Finder get _saveButton => find.descendant(
  of: find.byType(HoldingEditorFooter),
  matching: find.byType(FilledButton),
);

EditableText _editableField(WidgetTester tester, String label) =>
    tester.widget<EditableText>(
      find.descendant(of: _field(label), matching: find.byType(EditableText)),
    );

Future<void> _tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
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

void main() {
  late _Container container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsRepository settings = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    addTearDown(settings.dispose);
    container = _Container(settings);
  });

  Future<void> open(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(_app(container, page));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('choosing Metals opens the picker and saves fractional silver', (
    WidgetTester tester,
  ) async {
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
    await _tap(tester, find.text('Stock'));
    await _tap(tester, find.text('Metals'));
    expect(find.text('Choose a metal'), findsOneWidget);
    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('Silver'), findsOneWidget);
    expect(find.text('Platinum'), findsOneWidget);
    expect(find.text('Palladium'), findsOneWidget);
    container.assetRepository.pendingMetalPrice = Future.value(
      Result<double>.success(0.8),
    );
    await _tap(tester, find.text('Silver'));
    await _tap(tester, find.text('Choose grade'));
    expect(find.text('Choose fineness'), findsOneWidget);
    await _tap(tester, find.text('925'));
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Silver coins'),
      'Silver coins',
    );
    final weight = find.widgetWithText(TextField, 'e.g. 10.5');
    await tester.ensureVisible(weight);
    await tester.enterText(weight, '12.5');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Save asset'));
    final saved = container.assetRepository.saved!;
    expect(saved.metal, PreciousMetal.silver);
    expect(saved.purity, '925');
    expect(saved.value, 10.0);
  });

  testWidgets('an offline metal still saves as pending, not a zero quote', (
    WidgetTester tester,
  ) async {
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
    await _tap(tester, find.text('Stock'));
    await _tap(tester, find.text('Metals'));
    await _tap(tester, find.text('Platinum'));
    await _tap(tester, find.text('Choose grade'));
    await _tap(tester, find.text('950'));
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Platinum ring'),
      'Platinum ring',
    );
    final weight = _textField('Weight (grams)');
    await tester.ensureVisible(weight);
    await tester.enterText(weight, '3.2');
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Save asset'));
    final saved = container.assetRepository.saved!;
    expect(saved.quantity, 3.2);
    expect(saved.lastPrice, isNull);
    expect(saved.isPriced, isFalse);
    expect(find.text('Price pending'), findsWidgets);
  });

  testWidgets(
    'Metals groups existing Gold with Silver and keeps individual icons',
    (WidgetTester tester) async {
      container.assetRepository.items = const [
        AssetEntity(
          id: 21,
          portfolioId: 1,
          type: AssetType.gold,
          name: 'Family jewellery',
          currency: 'USD',
          quantity: 2,
          pricePerUnit: 75,
          createdAt: 0,
          updatedAt: 0,
        ),
        AssetEntity(
          id: 22,
          portfolioId: 1,
          type: AssetType.metals,
          metal: PreciousMetal.silver,
          purity: '925',
          name: 'Silver coins',
          currency: 'USD',
          quantity: 12.5,
          createdAt: 0,
          updatedAt: 0,
        ),
      ];
      await open(
        tester,
        HomeScreen(
          onOpenAssetEditor: (_, _) {},
          onOpenLiabilityEditor: (_, _) {},
          onManagePortfolios: () {},
          onOpenSettings: () {},
        ),
      );
      await _tap(tester, find.text('Metals'));
      expect(find.text('Family jewellery'), findsOneWidget);
      expect(find.text('Silver · 925'), findsOneWidget);
      expect(find.byIcon(metalIcon(PreciousMetal.gold)), findsOneWidget);
      expect(find.byIcon(metalIcon(PreciousMetal.silver)), findsOneWidget);
      expect(find.text('Price pending'), findsOneWidget);
    },
  );

  void seedHoldings() {
    container.assetRepository.items = const <AssetEntity>[
      AssetEntity(
        id: 1,
        portfolioId: 1,
        type: AssetType.cash,
        name: 'Savings',
        currency: 'USD',
        manualValue: 12345,
        createdAt: 0,
        updatedAt: 0,
      ),
      AssetEntity(
        id: 2,
        portfolioId: 1,
        type: AssetType.gold,
        name: 'Gold',
        currency: 'USD',
        quantity: 2,
        pricePerUnit: 100,
        createdAt: 0,
        updatedAt: 0,
      ),
    ];
    container.liabilityRepository.items = const <LiabilityEntity>[
      LiabilityEntity(
        id: 1,
        portfolioId: 1,
        type: LiabilityType.loan,
        name: 'Home loan',
        currency: 'USD',
        amount: 4200,
        createdAt: 0,
        updatedAt: 0,
      ),
    ];
  }

  testWidgets('a completed save closes an open discard prompt and its editor', (
    tester,
  ) async {
    final Completer<Result<StockQuote>> quote = Completer<Result<StockQuote>>();
    container.assetRepository.pendingQuote = quote.future;
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
    await _enterManualTicker(tester, 'AAPL');
    await tester.enterText(_textField('Quantity'), '2');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(_saveButton);
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Discard changes?'), findsOneWidget);
    quote.complete(Result<StockQuote>.offline());
    await tester.pumpAndSettle();
    expect(container.assetRepository.saved?.symbol, 'AAPL');
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(AssetEditScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Canvas add morph keeps the list still and navigation behind blur',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await container.settingsRepository.setLastSeenVersion(
        AppReleaseNotes.currentVersion,
      );
      seedHoldings();
      await open(tester, const AppShell());
      await _tap(tester, find.text('Cash'));
      final ScrollableState list = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      list.position.jumpTo(list.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final Rect before = tester.getRect(find.text('Savings'));
      final Rect button = tester.getRect(
        find.byKey(const ValueKey<String>('add-holding')),
      );
      expect(before.bottom, lessThan(button.top));
      final Color color = Theme.of(
        tester.element(find.byType(AddHoldingButton)),
      ).colorScheme.primary;
      await tester.tap(find.byKey(const ValueKey<String>('add-holding')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.getRect(find.text('Savings')), before);
      await tester.pumpAndSettle();
      final Material expanded = tester.widget<Material>(
        find.byKey(const ValueKey<String>('expanded-add-holding')),
      );
      expect(expanded.color, color);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('An asset').hitTestable(), findsOneWidget);
      expect(find.text('A liability').hitTestable(), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.getRect(find.text('Savings')), before);
      await tester.tap(find.byKey(const ValueKey<String>('add-holding')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      final Rect rotated = tester.getRect(
        find.byKey(const ValueKey<String>('expanded-add-holding')),
      );
      expect(rotated.top, greaterThanOrEqualTo(0));
      expect(rotated.bottom, lessThanOrEqualTo(390));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Canvas holding opens details before editing and confirms deletion',
    (tester) async {
      seedHoldings();
      int? editor;
      await open(
        tester,
        HomeScreen(
          onOpenAssetEditor: (_, id) => editor = id,
          onOpenLiabilityEditor: (_, _) {},
          onManagePortfolios: () {},
          onOpenSettings: () {},
        ),
      );
      await _tap(tester, find.text('Cash'));
      await _tap(tester, find.text('Savings'));
      expect(editor, isNull);
      expect(find.text('ASSET / CASH'), findsOneWidget);
      expect(find.text('Portfolio'), findsOneWidget);
      expect(find.text('Delete asset'), findsOneWidget);
      await _tap(tester, find.text('Edit asset'));
      expect(editor, 1);
      await _tap(tester, find.text('Savings'));
      await _tap(tester, find.text('Delete asset'));
      expect(container.assetRepository.deleted, isNull);
      expect(find.text('DELETE ASSET'), findsOneWidget);
      await _tap(tester, find.text('Cancel'));
      expect(container.assetRepository.deleted, isNull);
      await _tap(tester, find.text('Savings'));
      await _tap(tester, find.text('Delete asset'));
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Delete'));
      expect(container.assetRepository.deleted, 1);
    },
  );

  test(
    'Canvas sort compares converted values and never overwrites custom order',
    () {
      final List<int> original = <int>[1, 2, 3];
      HoldingGroupList<int> list(HoldingSort sort) => HoldingGroupList<int>(
        items: original,
        name: (id) => <String>['Zulu', 'Alpha', 'Pending'][id - 1],
        value: (id) => <double>[100, 200, 0][id - 1],
        priced: (id) => id != 3,
        sort: sort,
        onSort: (_) {},
        onReordered: (_) async {},
        itemBuilder: (_) => const SizedBox(),
      );
      expect(list(HoldingSort.nameAscending).sorted, <int>[2, 3, 1]);
      expect(list(HoldingSort.valueDescending).sorted, <int>[2, 1, 3]);
      expect(list(HoldingSort.valueAscending).sorted, <int>[1, 2, 3]);
      expect(list(HoldingSort.custom).sorted, <int>[1, 2, 3]);
      expect(original, <int>[1, 2, 3]);
    },
  );

  testWidgets('Canvas names count graphemes and Back protects a dirty draft', (
    tester,
  ) async {
    await open(
      tester,
      const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
    );
    final FilledButton emptySave = tester.widget(_saveButton);
    expect(emptySave.onPressed, isNull);
    final String family = '👨‍👩‍👧';
    await tester.enterText(_textField('Name'), family * 61);
    expect(_editableField(tester, 'Name').controller.text, family * 60);
    await tester.enterText(_textField('Outstanding amount'), '0');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);
    await _tap(tester, find.byTooltip('Back'));
    expect(find.text('Discard changes?'), findsOneWidget);
    await _tap(tester, find.text('Keep editing'));
    expect(_editableField(tester, 'Name').controller.text, family * 60);
    await _tap(tester, find.byTooltip('Back'));
    await _tap(tester, find.text('Discard'));
    expect(container.liabilityRepository.saved, isNull);
    expect(find.byType(LiabilityEditScreen), findsNothing);
  });

  testWidgets(
    'Canvas selection fetches once and can reopen search without losing quantity',
    (tester) async {
      container.stockSearchService.matches = const <StockSearchResult>[
        StockSearchResult(
          symbol: 'MSFT',
          name: 'Microsoft',
          exchange: 'NASDAQ',
        ),
      ];
      await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
      await _openMarketSearch(tester);
      await tester.enterText(_dialogSearchInput, 'MSFT');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Microsoft'));
      expect(container.assetRepository.quoteFetches, 1);
      expect(
        find.byKey(const ValueKey<String>('selected-market-holding')),
        findsOneWidget,
      );
      await tester.enterText(_textField('Quantity'), '2');
      await _openMarketSearch(tester);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_dialogSearchInput).controller?.text,
        'MSFT',
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ListTile, 'Microsoft'),
        ),
        findsOneWidget,
      );
      await _tap(tester, find.widgetWithText(TextButton, 'Close'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(_editableField(tester, 'Quantity').controller.text, '2');
      expect(_textField('Custom name (optional)'), findsNothing);
      await _tap(tester, _customNameToggle);
      expect(
        tester
            .widget<TextField>(_textField('Custom name (optional)'))
            .decoration
            ?.hintText,
        'Microsoft',
      );
      expect(
        _editableField(tester, 'Custom name (optional)').focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(_textField('Custom name (optional)'), 'x' * 61);
      expect(
        _editableField(tester, 'Custom name (optional)').controller.text,
        'x' * 60,
      );
      expect(
        find.descendant(
          of: find.byType(HoldingEditorFooter),
          matching: find.byType(HoldingPortfolioLabel),
        ),
        findsNothing,
      );
      await _tap(tester, _saveButton);
      expect(container.assetRepository.quoteFetches, 1);
      expect(container.assetRepository.saved?.quantity, 2);
      expect(container.assetRepository.saved?.customName, 'x' * 60);
    },
  );

  for (final (AssetType type, String symbol) in <(AssetType, String)>[
    (AssetType.stock, 'AAPL'),
    (AssetType.mutualFund, 'VOO'),
    (AssetType.crypto, 'BTC-USD'),
  ]) {
    testWidgets(
      '${type.name} suggestions follow search and selection immediately fetches price',
      (WidgetTester tester) async {
        final String company = 'Selected ${type.displayName}';
        final Completer<Result<StockQuote>> quote =
            Completer<Result<StockQuote>>();
        container.assetRepository.pendingQuote = quote.future;
        container.stockSearchService.matches = <StockSearchResult>[
          StockSearchResult(symbol: symbol, name: company, exchange: 'NASDAQ'),
        ];
        await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
        if (type != AssetType.stock) {
          await _tap(tester, find.byType(DropdownSelector<AssetType>));
          await _tap(tester, find.widgetWithText(ListTile, type.displayName));
        }
        await _openMarketSearch(tester);
        final Finder dialog = find.byType(AlertDialog);
        final String expectedTitle = switch (type) {
          AssetType.crypto => 'Choose coin or ticker',
          AssetType.mutualFund => 'Choose fund or ticker',
          _ => 'Choose company or ticker',
        };
        expect(
          find.descendant(of: dialog, matching: find.text(expectedTitle)),
          findsOneWidget,
        );
        await tester.enterText(_dialogSearchInput, symbol);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final Finder suggestion = find.descendant(
          of: dialog,
          matching: find.widgetWithText(ListTile, company),
        );
        expect(
          tester.getRect(suggestion).top,
          greaterThan(tester.getRect(_dialogSearchInput).bottom),
        );
        await tester.ensureVisible(suggestion);
        await tester.pumpAndSettle();
        await tester.tap(suggestion);
        await tester.pump();
        expect(container.assetRepository.quoteFetches, 1);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AlertDialog), findsNothing);
        expect(_editableField(tester, 'Quantity').controller.text, isEmpty);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Fetch latest price'),
              )
              .onPressed,
          isNull,
        );
        quote.complete(
          Result<StockQuote>.success(
            StockQuote(
              symbol: symbol,
              price: 125.75,
              currency: 'USD',
              name: company,
            ),
          ),
        );
        await tester.pumpAndSettle();
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        expect(
          find.text('0 × ${CurrencyUtil.format(125.75, 'USD')}'),
          findsOneWidget,
        );
        await _tap(tester, _textField('Quantity'));
        await tester.enterText(_textField('Quantity'), '2');
        await _tap(tester, _saveButton);
        expect(container.assetRepository.saved?.type, type);
        expect(container.assetRepository.saved?.symbol, symbol);
        expect(container.assetRepository.saved?.lastPrice, 125.75);
        expect(container.assetRepository.quoteFetches, 1);
      },
    );
  }

  for (final double textScale in <double>[1, 1.5]) {
    testWidgets(
      'selected stock leaves space above Quantity at $textScale text scale',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 792);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const String company = 'International Business Machines Corporation';
        container.stockSearchService.matches = const <StockSearchResult>[
          StockSearchResult(symbol: 'IBM', name: company, exchange: 'NYSE'),
        ];
        await tester.pumpWidget(
          _app(
            container,
            const AssetEditScreen(portfolioId: 1, assetId: 0),
            textScale: textScale,
            appTheme: AppTheme.midnight,
            brightness: Brightness.dark,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await _openMarketSearch(tester);
        await tester.enterText(_dialogSearchInput, 'IBM');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await _tap(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(company),
          ),
        );
        final Finder selection = find.byKey(
          const ValueKey<String>('selected-market-holding'),
        );
        await Scrollable.ensureVisible(
          tester.element(_field('Quantity')),
          alignment: 1,
        );
        await tester.pumpAndSettle();
        final Rect card = tester.getRect(selection);
        expect(
          tester
              .getRect(
                find.descendant(of: selection, matching: find.text(company)),
              )
              .bottom,
          lessThanOrEqualTo(card.bottom),
        );
        expect(
          tester.getRect(_field('Quantity')).top - card.bottom,
          greaterThanOrEqualTo(12),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final bool liability in <bool>[false, true]) {
    testWidgets(
      '${liability ? 'liability' : 'asset'} amount hint matches the cursor height',
      (WidgetTester tester) async {
        await open(
          tester,
          liability
              ? const LiabilityEditScreen(portfolioId: 1, liabilityId: 0)
              : const AssetEditScreen(portfolioId: 1, assetId: 0),
        );
        if (!liability) {
          await _tap(tester, find.byType(DropdownSelector<AssetType>));
          await _tap(tester, find.widgetWithText(ListTile, 'Cash'));
        }
        final Finder field = _field(liability ? 'Outstanding amount' : 'Value');
        await _tap(
          tester,
          find.descendant(of: field, matching: find.byType(TextField)),
        );
        final EditableTextState input = tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        final Rect hint = tester.getRect(
          find.descendant(of: field, matching: find.text('0.00')),
        );
        final Rect cursor = input.renderEditable.getLocalRectForCaret(
          const TextPosition(offset: 0),
        );
        expect(hint.height, closeTo(cursor.height, 2));
      },
    );
  }

  for (final AssetType selectedType in <AssetType>[
    AssetType.crypto,
    AssetType.mutualFund,
  ]) {
    testWidgets(
      'selected ${selectedType.displayName} stays on one line beside Currency',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 792);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
        await _tap(tester, find.byType(DropdownSelector<AssetType>));
        await _tap(
          tester,
          find.widgetWithText(ListTile, selectedType.displayName),
        );
        FocusManager.instance.primaryFocus?.unfocus();
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        final Rect type = tester.getRect(
          find.descendant(
            of: find.byType(DropdownSelector<AssetType>),
            matching: find.text(selectedType.displayName),
          ),
        );
        final Rect currency = tester.getRect(
          find.descendant(
            of: find.byType(CurrencySelector),
            matching: find.text('USD'),
          ),
        );
        expect(type.height, currency.height);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final bool liability in <bool>[false, true]) {
    testWidgets(
      '${liability ? 'liability' : 'asset'} Type uses a searchable currency-style picker',
      (WidgetTester tester) async {
        await open(
          tester,
          liability
              ? const LiabilityEditScreen(portfolioId: 1, liabilityId: 0)
              : const AssetEditScreen(portfolioId: 1, assetId: 0),
        );
        final Finder selector = liability
            ? find.byType(DropdownSelector<LiabilityType>)
            : find.byType(DropdownSelector<AssetType>);
        final String initial = liability ? 'Loan' : 'Stock';
        final String choice = liability ? 'Mortgage' : 'Cash';
        final String subtitleQuery = liability
            ? 'property borrowing'
            : 'money on hand';
        await _tap(tester, selector);
        final Finder dialog = find.byType(AlertDialog);
        final ColorScheme colors = Theme.of(tester.element(dialog)).colorScheme;
        expect(
          tester.widget<AlertDialog>(dialog).backgroundColor,
          colors.surface,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.text(liability ? 'WHAT YOU OWE' : 'WHAT YOU OWN'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('Choose a type')),
          findsOneWidget,
        );
        final Finder search = find.descendant(
          of: dialog,
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(search).decoration?.border,
          isA<OutlineInputBorder>(),
        );
        final Finder selectedTileFinder = find.descendant(
          of: dialog,
          matching: find.widgetWithText(ListTile, initial),
        );
        final ListTile selectedTile = tester.widget<ListTile>(
          selectedTileFinder,
        );
        expect(selectedTile.selected, isTrue);
        expect(selectedTile.selectedTileColor, colors.primaryContainer);
        expect(selectedTile.trailing, isNotNull);
        final Finder listView = find.descendant(
          of: dialog,
          matching: find.byType(ListView),
        );
        final Finder listMaterial = find
            .ancestor(of: listView, matching: find.byType(Material))
            .first;
        expect(
          tester.widget<Material>(listMaterial).clipBehavior,
          Clip.hardEdge,
        );
        final RenderBox inkCanvas =
            Material.of(tester.element(selectedTileFinder)) as RenderBox;
        final Rect inkRect =
            inkCanvas.localToGlobal(Offset.zero) & inkCanvas.size;
        expect(
          inkRect.top,
          greaterThanOrEqualTo(tester.getRect(search).bottom),
        );
        expect(
          inkRect.bottom,
          lessThanOrEqualTo(
            tester.getRect(find.widgetWithText(TextButton, 'Close')).top,
          ),
        );
        await tester.drag(listView, const Offset(0, -90));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(listMaterial).top,
          greaterThanOrEqualTo(tester.getRect(search).bottom),
        );
        await tester.enterText(search, 'zzz-no-match');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: dialog,
            matching: find.text('No matching options.'),
          ),
          findsOneWidget,
        );
        await tester.enterText(search, subtitleQuery);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: dialog,
            matching: find.widgetWithText(ListTile, choice),
          ),
          findsOneWidget,
        );
        await tester.enterText(search, ' ${choice.toUpperCase()} ');
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: dialog, matching: find.byType(ListTile)),
          findsOneWidget,
        );
        await _tap(tester, find.widgetWithText(TextButton, 'Close'));
        expect(
          liability
              ? tester
                    .widget<DropdownSelector<LiabilityType>>(selector)
                    .selected
                    .displayName
              : tester
                    .widget<DropdownSelector<AssetType>>(selector)
                    .selected
                    .displayName,
          initial,
        );
        await _tap(tester, selector);
        await tester.enterText(search, choice);
        await tester.pumpAndSettle();
        await _tap(
          tester,
          find.descendant(
            of: dialog,
            matching: find.widgetWithText(ListTile, choice),
          ),
        );
        expect(dialog, findsNothing);
        expect(
          liability
              ? tester
                    .widget<DropdownSelector<LiabilityType>>(selector)
                    .selected
                    .displayName
              : tester
                    .widget<DropdownSelector<AssetType>>(selector)
                    .selected
                    .displayName,
          choice,
        );
        await _tap(tester, find.byType(CurrencySelector));
        final Finder currencyDialog = find.byType(AlertDialog);
        expect(
          find.descendant(
            of: currencyDialog,
            matching: find.text('HOLDING CURRENCY'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: currencyDialog,
            matching: find.text('Choose currency'),
          ),
          findsOneWidget,
        );
        final Finder currencyList = find.descendant(
          of: currencyDialog,
          matching: find.byType(ListView),
        );
        final Finder currencyMaterial = find
            .ancestor(of: currencyList, matching: find.byType(Material))
            .first;
        final Finder currencySearch = find.descendant(
          of: currencyDialog,
          matching: find.byType(TextField),
        );
        await tester.drag(currencyList, const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Material>(currencyMaterial).clipBehavior,
          Clip.hardEdge,
        );
        expect(
          tester.getRect(currencyMaterial).top,
          greaterThanOrEqualTo(tester.getRect(currencySearch).bottom),
        );
        await _tap(tester, find.widgetWithText(TextButton, 'Close'));
      },
    );
  }

  for (final (AppTheme, Brightness) appearance in <(AppTheme, Brightness)>[
    (AppTheme.classic, Brightness.light),
    (AppTheme.classic, Brightness.dark),
    (AppTheme.midnight, Brightness.dark),
  ]) {
    testWidgets('all destinations use precision styling in $appearance', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      seedHoldings();
      await container.settingsRepository.setBaseCurrency('USD');
      await container.settingsRepository.setLastSeenVersion(
        AppReleaseNotes.currentVersion,
      );
      await tester.pumpWidget(
        _app(
          container,
          const AppShell(),
          appTheme: appearance.$1,
          brightness: appearance.$2,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(NetWorthCard), findsOneWidget);
      expect(find.text('\$8,345'), findsOneWidget);
      final ThemeData theme = Theme.of(tester.element(find.byType(AppShell)));
      expect(theme.brightness, appearance.$2);
      expect(theme.cardTheme.color, theme.colorScheme.surfaceContainerLow);
      await tester.tap(find.text('Statistics'));
      await tester.pumpAndSettle();
      expect(find.byType(StatisticsScreen), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);
      await tester.tap(find.text('Portfolios'));
      await tester.pumpAndSettle();
      expect(find.byType(PortfolioScreen), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hide balances'));
      await tester.pumpAndSettle();
      expect(find.text('\$8,345'), findsNothing);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(5));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the shell retains tablet navigation', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    seedHoldings();
    await container.settingsRepository.setBaseCurrency('USD');
    await container.settingsRepository.setLastSeenVersion(
      AppReleaseNotes.currentVersion,
    );
    await open(tester, const AppShell());
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Quiet overview has an unboxed headline, one panel and persistent category expansion',
    (WidgetTester tester) async {
      seedHoldings();
      await container.settingsRepository.setBaseCurrency('USD');
      await open(
        tester,
        HomeScreen(
          onOpenAssetEditor: (_, _) {},
          onOpenLiabilityEditor: (_, _) {},
          onManagePortfolios: () {},
          onOpenSettings: () {},
        ),
      );
      expect(
        find.descendant(
          of: find.byType(NetWorthCard),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('home-category-panel')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('home-assets-tab')),
          matching: find.text('Assets'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('home-liabilities-tab')),
          matching: find.text('Liabilities'),
        ),
        findsOneWidget,
      );
      expect(find.text('Loan'), findsNothing);
      final Text headline = tester.widget<Text>(
        find.byKey(const ValueKey<String>('net-worth-headline')),
      );
      expect(headline.style?.fontSize, 42);
      expect(headline.style?.fontWeight, FontWeight.w500);
      await _tap(tester, find.text('Cash'));
      expect(find.text('Savings'), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const ValueKey<String>('home-liabilities-tab')),
      );
      expect(find.text('Loan'), findsOneWidget);
      expect(find.text('Savings'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey<String>('home-assets-tab')));
      expect(find.text('Savings'), findsOneWidget);
      await _tap(tester, find.byTooltip('Hide balances'));
      expect(find.text('\$8,345'), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('net-worth-headline')),
            )
            .data,
        CurrencyUtil.masked('USD'),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('home-assets-tab')),
          matching: find.text('Assets'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home tab labels stay plural and count-free for empty, single and multiple categories',
    (WidgetTester tester) async {
      for (final int count in <int>[0, 1, 3]) {
        container.assetRepository.items = <AssetEntity>[
          for (int i = 0; i < count; i++)
            AssetEntity(
              id: i + 1,
              portfolioId: 1,
              type: AssetType.values[i],
              name: 'Asset $i',
              currency: 'USD',
              quantity: 1,
              lastPrice: 100,
              pricePerUnit: 100,
              manualValue: 100,
              createdAt: 0,
              updatedAt: 0,
            ),
        ];
        container.liabilityRepository.items = <LiabilityEntity>[
          for (int i = 0; i < count; i++)
            LiabilityEntity(
              id: i + 1,
              portfolioId: 1,
              type: LiabilityType.values[i],
              name: 'Liability $i',
              currency: 'USD',
              amount: 100,
              createdAt: 0,
              updatedAt: 0,
            ),
        ];
        await open(
          tester,
          HomeScreen(
            onOpenAssetEditor: (_, _) {},
            onOpenLiabilityEditor: (_, _) {},
            onManagePortfolios: () {},
            onOpenSettings: () {},
          ),
        );
        for (final (String key, String text) tab in <(String, String)>[
          ('home-assets-tab', 'Assets'),
          ('home-liabilities-tab', 'Liabilities'),
        ]) {
          final Finder label = find.descendant(
            of: find.byKey(ValueKey<String>(tab.$1)),
            matching: find.byType(Text),
          );
          expect(tester.widget<Text>(label).data, tab.$2);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'Quiet overview shows each empty state and selects the section when adding',
    (WidgetTester tester) async {
      final List<String> editors = <String>[];
      await open(
        tester,
        HomeScreen(
          onOpenAssetEditor: (_, _) => editors.add('asset'),
          onOpenLiabilityEditor: (_, _) => editors.add('liability'),
          onManagePortfolios: () {},
          onOpenSettings: () {},
        ),
      );
      expect(find.text('No assets yet'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('home-assets-tab')),
          matching: find.text('Assets'),
        ),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey<String>('home-liabilities-tab')),
      );
      expect(find.text('No liabilities'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey<String>('add-holding')));
      await _tap(tester, find.text('An asset'));
      expect(editors, <String>['asset']);
      expect(find.text('No assets yet'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey<String>('add-holding')));
      await _tap(tester, find.text('A liability'));
      expect(editors, <String>['asset', 'liability']);
      expect(find.text('No liabilities'), findsOneWidget);
    },
  );

  testWidgets(
    'Quiet overview retains category drag ordering and per-category holding reorder callbacks',
    (WidgetTester tester) async {
      seedHoldings();
      await open(
        tester,
        HomeScreen(
          onOpenAssetEditor: (_, _) {},
          onOpenLiabilityEditor: (_, _) {},
          onManagePortfolios: () {},
          onOpenSettings: () {},
        ),
      );

      final Finder assetReorder = find.byType(
        DragReorderColumn<AssetCategoryGroup>,
      );
      final categories = tester.widget<DragReorderColumn<AssetCategoryGroup>>(
        assetReorder,
      );
      final reorderedCategories = categories.items.reversed.toList();
      categories.onReordered(reorderedCategories);
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('cat_order_asset_1'),
        reorderedCategories
            .map((category) => category.type.storageName)
            .join(','),
      );
      await _tap(tester, find.text('Cash'));
      final items = tester.widget<HoldingGroupList<AssetLine>>(
        find.byType(HoldingGroupList<AssetLine>),
      );
      items.onReordered(items.items);
      await tester.pumpAndSettle();
      expect(container.assetRepository.lastOrder, <int>[1]);
      await _tap(
        tester,
        find.byKey(const ValueKey<String>('home-liabilities-tab')),
      );
      final liabilities = tester
          .widget<DragReorderColumn<LiabilityCategoryGroup>>(
            find.byType(DragReorderColumn<LiabilityCategoryGroup>),
          );
      liabilities.onReordered(liabilities.items);
      await tester.pumpAndSettle();
      expect(prefs.getString('cat_order_liability_1'), 'LOAN');
      await _tap(tester, find.text('Loan'));
      final loans = tester.widget<HoldingGroupList<LiabilityLine>>(
        find.byType(HoldingGroupList<LiabilityLine>),
      );
      loans.onReordered(loans.items);
      await tester.pumpAndSettle();
      expect(container.liabilityRepository.lastOrder, <int>[1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'holding rows stay clean and explicit arrangement persists item order',
    (WidgetTester tester) async {
      container.assetRepository.items = const <AssetEntity>[
        AssetEntity(
          id: 1,
          portfolioId: 1,
          type: AssetType.cash,
          name: 'First cash',
          currency: 'USD',
          manualValue: 100,
          createdAt: 0,
          updatedAt: 0,
        ),
        AssetEntity(
          id: 2,
          portfolioId: 1,
          type: AssetType.cash,
          name: 'Second cash',
          currency: 'USD',
          manualValue: 200,
          createdAt: 0,
          updatedAt: 0,
        ),
      ];
      await open(
        tester,
        HomeScreen(
          onOpenAssetEditor: (_, _) {},
          onOpenLiabilityEditor: (_, _) {},
          onManagePortfolios: () {},
          onOpenSettings: () {},
        ),
      );
      await _tap(tester, find.text('Cash'));
      expect(find.byTooltip('Move up'), findsNothing);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      await _tap(tester, find.byTooltip('Sort or arrange'));
      await _tap(tester, find.text('Arrange manually'));
      await _tap(tester, find.byTooltip('Move up').last);
      expect(container.assetRepository.lastOrder, <int>[2, 1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded categories can be reordered by long-pressing their header',
    (WidgetTester tester) async {
      container.assetRepository.items = const <AssetEntity>[
        AssetEntity(
          id: 1,
          portfolioId: 1,
          type: AssetType.stock,
          name: 'Shares',
          currency: 'USD',
          quantity: 1,
          lastPrice: 100,
          symbol: 'AAPL',
          createdAt: 0,
          updatedAt: 0,
        ),
        AssetEntity(
          id: 2,
          portfolioId: 1,
          type: AssetType.cash,
          name: 'First cash',
          currency: 'USD',
          manualValue: 100,
          createdAt: 0,
          updatedAt: 0,
        ),
        AssetEntity(
          id: 3,
          portfolioId: 1,
          type: AssetType.cash,
          name: 'Second cash',
          currency: 'USD',
          manualValue: 200,
          createdAt: 0,
          updatedAt: 0,
        ),
      ];
      await open(
        tester,
        HomeScreen(
          onOpenAssetEditor: (_, _) {},
          onOpenLiabilityEditor: (_, _) {},
          onManagePortfolios: () {},
          onOpenSettings: () {},
        ),
      );
      await _tap(tester, find.text('Cash'));
      final bounds = tester.getRect(find.text('Stock'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Cash')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(bounds.center + Offset(0, bounds.height / 4));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cat_order_asset_1'), 'CASH,STOCK');
      expect(
        tester.getRect(find.text('Cash')).top,
        lessThan(tester.getRect(find.text('Stock')).top),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard, charts, portfolios, lock and release notes support large RTL text',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      seedHoldings();
      await container.settingsRepository.setBaseCurrency('USD');
      for (final Widget page in <Widget>[
        HomeScreen(
          onOpenAssetEditor: (_, _) {},
          onOpenLiabilityEditor: (_, _) {},
          onManagePortfolios: () {},
          onOpenSettings: () {},
        ),
        const StatisticsScreen(),
        const PortfolioScreen(),
        LockScreen(onUnlock: () async {}),
        WhatsNewDialog(releaseNotes: AppReleaseNotes.current),
      ]) {
        await tester.pumpWidget(
          _app(
            container,
            page,
            locale: const Locale('ar'),
            textScale: 2,
            appTheme: AppTheme.midnight,
            brightness: Brightness.dark,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('settings start with five categories and keep every control', (
    WidgetTester tester,
  ) async {
    await open(tester, SettingsScreen(onClose: () {}));
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(5));
    expect(find.byType(Switch), findsNothing);
    expect(find.text('App language'), findsNothing);
    final Map<String, List<String>> categories = <String, List<String>>{
      'Appearance': <String>['App language', 'Theme', 'Dynamic color'],
      'Currency': <String>['Base currency', 'Simple net worth'],
      'Security': <String>['App lock', 'Block screenshots'],
      'Data': <String>[
        'Exchange rates',
        'Export portfolios',
        'Import portfolios',
      ],
      'About': <String>['Okanzo', "What's new", 'Privacy policy'],
    };
    for (final MapEntry<String, List<String>> category in categories.entries) {
      await _tap(tester, find.text(category.key));
      for (final String title in category.value) {
        expect(find.text(title), findsOneWidget);
      }
      await _tap(tester, find.byTooltip('Back'));
      for (final String title in category.value) {
        expect(find.text(title), findsNothing);
      }
    }
    expect(tester.takeException(), isNull);
  });

  for (final Locale locale in <Locale>[
    const Locale('en'),
    const Locale('es'),
  ]) {
    testWidgets(
      'Okanzo app information is separate from release highlights in $locale',
      (WidgetTester tester) async {
        await container.settingsRepository.setLastSeenVersion('1.2.5');
        final strings = AppLocalizations(locale);
        await tester.pumpWidget(
          _app(container, SettingsScreen(onClose: () {}), locale: locale),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await _tap(tester, find.text(strings.text('About')));
        await _tap(tester, find.text('Okanzo'));
        expect(find.byType(AboutDialog), findsOneWidget);
        expect(find.byType(WhatsNewDialog), findsNothing);
        final AboutDialog information = tester.widget<AboutDialog>(
          find.byType(AboutDialog),
        );
        expect(information.applicationName, 'Okanzo');
        expect(information.applicationVersion, AppReleaseNotes.currentVersion);
        expect(information.applicationLegalese, contains('MIT'));
        expect(
          find.text(strings.text('Private by design. Stored on your device.')),
          findsOneWidget,
        );
        expect(container.settingsRepository.current.lastSeenVersion, '1.2.5');
        await tester.tap(
          find.text(
            MaterialLocalizations.of(tester.element(find.byType(AboutDialog)))
                .closeButtonLabel,
          ),
        );
        await tester.pumpAndSettle();
        await _tap(tester, find.text(strings.text("What's new")));
        expect(find.byType(WhatsNewDialog), findsOneWidget);
        expect(find.byType(AboutDialog), findsNothing);
        await _tap(tester, find.text(strings.text('Got it')));
        expect(
          container.settingsRepository.current.lastSeenVersion,
          AppReleaseNotes.currentVersion,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Midnight settings match the descriptive drill-in layout', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      _app(
        container,
        SettingsScreen(onClose: () {}),
        appTheme: AppTheme.midnight,
        brightness: Brightness.dark,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Language, theme & colour'), findsOneWidget);
    expect(
      find.text('Private by design. Stored on your device.'),
      findsOneWidget,
    );
    expect(tester.widget<AppBar>(find.byType(AppBar)).title, isNull);
    expect(
      tester.getRect(find.byType(PageHeading)).top,
      greaterThan(tester.getRect(find.byTooltip('Back')).bottom),
    );
    await _tap(tester, find.text('Currency'));
    expect(find.text('Base currency'), findsOneWidget);
    expect(find.text('Language, theme & colour'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Language, theme & colour'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets(
    'Canvas asset layout keeps selected market holding editable and Save pinned',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      container.assetRepository.existing = const AssetEntity(
        id: 1,
        portfolioId: 1,
        type: AssetType.stock,
        name: 'Apple shares',
        currency: 'USD',
        quantity: 12,
        symbol: 'AAPL',
        lastPrice: 322,
        createdAt: 0,
        updatedAt: 0,
      );

      await tester.pumpWidget(
        _app(
          container,
          const AssetEditScreen(portfolioId: 1, assetId: 1),
          appTheme: AppTheme.midnight,
          brightness: Brightness.dark,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(PickerChip), findsNWidgets(3));
      expect(find.text('US exchange'), findsOneWidget);
      expect(find.byType(DropdownMenu<Object>), findsNothing);
      expect(find.byType(DropdownMenu<AssetType>), findsNothing);
      final Text amount = tester.widget<Text>(
        find.descendant(
          of: find.byType(HoldingEditorFooter),
          matching: find.text(CurrencyUtil.format(3864, 'USD')),
        ),
      );
      expect(amount.style?.fontSize, 26);
      expect(
        tester.getRect(find.byType(PageHeading)).top,
        greaterThan(tester.getRect(find.byTooltip('Back')).bottom),
      );
      expect(
        find.byKey(const ValueKey<String>('selected-market-holding')),
        findsOneWidget,
      );
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey<String>('selected-market-holding')),
            )
            .top,
        lessThan(tester.getRect(_field('Quantity')).top),
      );
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey<String>('selected-market-holding')),
            )
            .left,
        tester.getRect(_field('Quantity')).left,
      );
      await _openMarketSearch(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await _tap(tester, find.widgetWithText(TextButton, 'Close'));
      final Scaffold scaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(AssetEditScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(scaffold.bottomNavigationBar, isNotNull);
      expect(find.text('Save asset'), findsOneWidget);
      final Finder save = _saveButton;
      final Finder cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      await tester.scrollUntilVisible(
        save,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(cancel, findsNothing);
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('holding kind tabs preserve both drafts and guard Back', (
    tester,
  ) async {
    Future<void> switchKind(String label) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await _tap(tester, find.text(label));
    }

    await open(tester, const HoldingCreateScreen(portfolioId: 1, asset: true));
    await _enterManualTicker(tester, 'AAPL');
    await _tap(tester, _textField('Quantity'));
    await tester.enterText(_textField('Quantity'), '2');
    await switchKind('Liability / I owe');
    await tester.enterText(_textField('Outstanding amount'), '250.75');
    await _tap(tester, _textField('Name'));
    await tester.enterText(_textField('Name'), 'Example loan');
    await switchKind('Asset / I own');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('selected-market-holding')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AAPL'), findsOneWidget);
    expect(_editableField(tester, 'Quantity').controller.text, '2');
    await switchKind('Liability / I owe');
    expect(
      _editableField(tester, 'Outstanding amount').controller.text,
      '250.75',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(HoldingCreateScreen), findsOneWidget);
    expect(container.assetRepository.saved, isNull);
    expect(container.liabilityRepository.saved, isNull);
  });

  testWidgets(
    'asset footer shows 0-initialized aligned estimate, contextual hints, validation, and omits net worth preview',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await container.settingsRepository.setPreferredExchanges(<StockExchange>[
        StockExchange.us,
        StockExchange.bse,
      ]);
      seedHoldings();

      await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));

      // Removed Current net worth / After this holding section & top Price pending
      expect(find.text('Current net worth'), findsNothing);
      expect(find.text('After this holding'), findsNothing);
      expect(find.text('Price pending'), findsNothing);

      // Pinned footer starts at $0 with aligned left stack and right amount
      final Finder footer = find.byType(HoldingEditorFooter);
      final Finder footerAmount = find.byKey(
        const ValueKey<String>('asset-estimated-value'),
      );
      final Finder pendingCaption = find.byKey(
        const ValueKey<String>('asset-valuation-pending-caption'),
      );
      expect(
        find.descendant(of: footer, matching: find.text('Estimated value')),
        findsOneWidget,
      );
      expect(tester.widget<Text>(footerAmount).data, '\$0');
      expect(
        tester.widget<Text>(pendingCaption).data,
        '0 × \$0 · price not fetched yet',
      );
      final Rect saveRect = tester.getRect(_saveButton);
      final Rect labelRect = tester.getRect(
        find.descendant(of: footer, matching: find.text('Estimated value')),
      );
      final Rect captionRect = tester.getRect(pendingCaption);
      final Rect amountRect = tester.getRect(footerAmount);
      expect(labelRect.left, closeTo(saveRect.left, 1));
      expect(amountRect.right, closeTo(saveRect.right, 1));
      final double copyCenterY = (labelRect.top + captionRect.bottom) / 2;
      expect(amountRect.center.dy, closeTo(copyCenterY, 2));

      // Contextual helper examples change with Exchange and Type
      expect(
        find.text('e.g. Stock, Cash, Metals, Real estate'),
        findsOneWidget,
      );
      expect(find.text('e.g. INR, USD, EUR, GBP'), findsOneWidget);
      expect(find.text('e.g. Apple (AAPL) · NYSE / Nasdaq'), findsOneWidget);
      expect(find.text('Search Apple, or enter AAPL'), findsOneWidget);

      await _tap(tester, find.byType(StockExchangeField));
      await _tap(tester, find.text('BSE (India)').last);
      expect(
        find.text('Adds .BO automatically (e.g. RELIANCE.BO)'),
        findsOneWidget,
      );
      expect(
        find.text('Search Reliance, or enter RELIANCE.BO'),
        findsOneWidget,
      );

      // Market search sanitizes invalid chars & blocks invalid manual tickers
      await _openMarketSearch(tester);
      await tester.enterText(_dialogSearchInput, 'NoSuch Co!@#');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_dialogSearchInput).controller?.text,
        'NoSuch Co',
      );
      expect(
        find.byKey(const ValueKey<String>('use-manual-ticker')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('invalid-ticker-notice')),
        findsOneWidget,
      );
      await tester.enterText(_dialogSearchInput, '7203.T');
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('use-manual-ticker')),
        findsOneWidget,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey<String>('use-manual-ticker')),
      );

      // Quantity strips negatives/letters/extra dots, rejects 0, accepts 0.25
      await tester.enterText(_textField('Quantity'), '-12..34abc');
      await tester.pump();
      expect(_editableField(tester, 'Quantity').controller.text, '12.34');
      await tester.enterText(_textField('Quantity'), '0');
      await tester.pump();
      expect(
        find.text('Enter a positive number (decimals allowed, e.g. 0.25).'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);
      await tester.enterText(_textField('Quantity'), '0.25');
      await tester.pump();
      expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);

      // Liability editor also omits Current net worth / After this holding
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await open(
        tester,
        const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
      );
      expect(find.text('Current net worth'), findsNothing);
      expect(find.text('After this holding'), findsNothing);
      expect(find.text('e.g. Loan, Mortgage, Credit card'), findsOneWidget);
    },
  );

  testWidgets(
    'post-save glance is centered over the previous screen and supports Undo and Add another',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      seedHoldings();

      // 1. Add a Cash asset -> shows Asset added. + Undo addition deletes newly saved id
      await open(
        tester,
        const HoldingCreateScreen(portfolioId: 1, asset: true),
      );
      await _tap(tester, find.byType(DropdownSelector<AssetType>));
      await _tap(tester, find.text('Cash').last);
      await tester.enterText(_textField('Value'), '500');
      await tester.enterText(_textField('Name'), 'Emergency buffer');
      await _tap(tester, _saveButton);

      expect(find.byType(HoldingSavedSummaryScreen), findsOneWidget);
      expect(find.text('Asset added.'), findsOneWidget);
      expect(find.text('Emergency buffer'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('\$500'), findsOneWidget);
      expect(find.text('Undo this addition'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.byType(HoldingEditorFooter), findsNothing);
      final Rect glance = tester.getRect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(glance.center, const Offset(195, 422));
      expect(glance.width, lessThan(390));
      expect(glance.height, lessThan(844 * 0.85));

      await _tap(
        tester,
        find.byKey(const ValueKey<String>('undo-saved-holding')),
      );
      expect(find.byType(HoldingSavedSummaryScreen), findsNothing);
      expect(container.assetRepository.deleted, 1);

      // 2. Edit an existing asset -> shows Asset updated. + Undo update restores previousAsset, or Add another holding opens HoldingCreateScreen
      container.assetRepository.existing = const AssetEntity(
        id: 9,
        portfolioId: 1,
        type: AssetType.cash,
        name: 'Vault cash',
        currency: 'USD',
        manualValue: 300,
        createdAt: 0,
        updatedAt: 0,
      );
      await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 9));
      await tester.enterText(_textField('Value'), '750');
      await _tap(tester, _saveButton);

      expect(find.byType(HoldingSavedSummaryScreen), findsOneWidget);
      expect(find.text('Asset updated.'), findsOneWidget);
      expect(find.text('\$750'), findsOneWidget);
      expect(find.text('Undo this update'), findsOneWidget);

      await _tap(
        tester,
        find.byKey(const ValueKey<String>('undo-saved-holding')),
      );
      expect(container.assetRepository.saved?.manualValue, 300);
      expect(find.byType(HoldingSavedSummaryScreen), findsNothing);

      await _tap(tester, find.text('Open'));
      await tester.enterText(_textField('Value'), '750');
      await _tap(tester, _saveButton);
      await _tap(
        tester,
        find.byKey(const ValueKey<String>('add-another-holding')),
      );
      expect(find.text('What would you like to add?'), findsOneWidget);
      await _tap(tester, find.text('A liability'));
      expect(find.byType(HoldingCreateScreen), findsOneWidget);
      expect(find.text('Add liability'), findsOneWidget);
      await _tap(tester, find.byTooltip('Back'));
      expect(find.text('Open'), findsOneWidget);
      expect(find.byType(HoldingSavedSummaryScreen), findsNothing);
    },
  );

  testWidgets(
    'liability save glance keeps balances private at large text sizes',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await container.settingsRepository.setHideBalances(true);
      await tester.pumpWidget(
        _app(
          container,
          const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
          textScale: 1.5,
        ),
      );
      await _tap(tester, find.text('Open'));
      await _tap(tester, _textField('Outstanding amount'));
      await tester.enterText(_textField('Outstanding amount'), '271');
      await _tap(tester, _textField('Name'));
      await tester.enterText(_textField('Name'), 'Private loan');
      await _tap(tester, _saveButton);
      expect(find.text('Liability added.'), findsOneWidget);
      expect(find.text('Private loan'), findsOneWidget);
      expect(find.text(CurrencyUtil.masked('USD')), findsOneWidget);
      expect(find.text('\$271'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(HoldingSavedSummaryScreen), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    },
  );

  testWidgets(
    'one theme choice maps Dark to Midnight and keeps dynamic color available in Light',
    (WidgetTester tester) async {
      await open(tester, SettingsScreen(onClose: () {}));
      await _tap(tester, find.text('Appearance'));
      await _tap(tester, find.text('Dynamic color'));
      expect(container.settingsRepository.current.dynamicColor, isFalse);
      expect(find.text('App theme'), findsNothing);
      expect(find.text('Light / dark'), findsNothing);
      await _tap(tester, find.text('Theme'));
      await tester.tap(
        find.byKey(const ValueKey<AppThemeMode>(AppThemeMode.dark)),
      );
      await tester.pumpAndSettle();
      expect(container.settingsRepository.current.appTheme, AppTheme.midnight);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Dynamic color'),
            )
            .onChanged,
        isNull,
      );
      expect(
        container.settingsRepository.current.appearanceMode,
        AppThemeMode.dark,
      );
      await _tap(tester, find.byTooltip('Back'));
      await _tap(tester, find.text('Appearance'));
      expect(find.text('Not used in dark mode'), findsOneWidget);
      await _tap(tester, find.text('Theme'));
      await tester.tap(
        find.byKey(const ValueKey<AppThemeMode>(AppThemeMode.light)),
      );
      await tester.pumpAndSettle();
      expect(
        container.settingsRepository.current.appearanceMode,
        AppThemeMode.light,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Dynamic color'),
            )
            .onChanged,
        isNotNull,
      );
    },
  );

  testWidgets(
    'the actual app follows System with light and Midnight dark variants',
    (WidgetTester tester) async {
      await container.settingsRepository.setLastSeenVersion(
        AppReleaseNotes.currentVersion,
      );
      await container.settingsRepository.setAppearanceMode(AppThemeMode.system);
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      await tester.pumpWidget(
        AppScope(container: container, child: const app.OkanzoApp()),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(HomeScreen))).brightness,
        Brightness.light,
      );
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      final ThemeData dark = Theme.of(tester.element(find.byType(HomeScreen)));
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.surface, const Color(0xFF172220));
      expect(dark.extension<AppStyle>(), AppStyle.midnight);
      await container.settingsRepository.setAppearanceMode(AppThemeMode.light);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(HomeScreen))).brightness,
        Brightness.light,
      );
      await container.settingsRepository.setAppearanceMode(AppThemeMode.dark);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(HomeScreen))).extension<AppStyle>(),
        AppStyle.midnight,
      );
    },
  );

  testWidgets('theme save failures remain visible in the chooser', (
    WidgetTester tester,
  ) async {
    final failing = _FailingAppearanceRepository(
      await SharedPreferences.getInstance(),
    );
    addTearDown(failing.dispose);
    await tester.pumpWidget(
      _app(_Container(failing), SettingsScreen(onClose: () {})),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Appearance'));
    await _tap(tester, find.text('Theme'));
    await tester.tap(
      find.byKey(const ValueKey<AppThemeMode>(AppThemeMode.dark)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining("Couldn't save theme:"), findsOneWidget);
    expect(failing.current.appearanceMode, AppThemeMode.system);
  });

  for (final Locale locale in <Locale>[
    const Locale('en'),
    const Locale('ar'),
  ]) {
    testWidgets(
      'home amount columns align for short, long and hidden values in $locale',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await container.settingsRepository.setBaseCurrency('USD');
        container.assetRepository.items = const <AssetEntity>[
          AssetEntity(
            id: 1,
            portfolioId: 1,
            type: AssetType.stock,
            name: 'Shares',
            currency: 'USD',
            quantity: 12,
            lastPrice: 322,
            symbol: 'AAPL',
            createdAt: 0,
            updatedAt: 0,
          ),
          AssetEntity(
            id: 2,
            portfolioId: 1,
            type: AssetType.cash,
            name: 'Savings',
            currency: 'USD',
            manualValue: 1234567,
            createdAt: 0,
            updatedAt: 0,
          ),
          AssetEntity(
            id: 3,
            portfolioId: 1,
            type: AssetType.gold,
            name: 'Gold',
            currency: 'USD',
            quantity: 2,
            pricePerUnit: 100,
            createdAt: 0,
            updatedAt: 0,
          ),
        ];
        container.liabilityRepository.items = const <LiabilityEntity>[
          LiabilityEntity(
            id: 1,
            portfolioId: 1,
            type: LiabilityType.loan,
            name: 'Loan',
            currency: 'USD',
            amount: 4200,
            createdAt: 0,
            updatedAt: 0,
          ),
          LiabilityEntity(
            id: 2,
            portfolioId: 1,
            type: LiabilityType.creditCard,
            name: 'Card',
            currency: 'USD',
            amount: 50,
            createdAt: 0,
            updatedAt: 0,
          ),
        ];
        final strings = AppLocalizations(locale);
        await tester.pumpWidget(
          _app(
            container,
            HomeScreen(
              onOpenAssetEditor: (_, _) {},
              onOpenLiabilityEditor: (_, _) {},
              onManagePortfolios: () {},
              onOpenSettings: () {},
            ),
            locale: locale,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        List<Text> amountWidgets() {
          final Set<String> labels = <String>{
            strings.text('Expand'),
            strings.text('Collapse'),
            strings.text('Drag to reorder'),
          };
          return tester
              .widgetList<Row>(
                find.byWidgetPredicate(
                  (Widget widget) =>
                      widget is Row &&
                      widget.children.whereType<Icon>().any(
                        (icon) => labels.contains(icon.semanticLabel),
                      ),
                ),
              )
              .map(
                (row) => row.children
                    .whereType<Flexible>()
                    .map((child) => child.child)
                    .whereType<Text>()
                    .single,
              )
              .toList();
        }

        double? alignedEdge;
        void checkColumns() {
          final amounts = amountWidgets();
          expect(amounts.length, greaterThanOrEqualTo(2));
          final Rect first = tester.getRect(find.byWidget(amounts.first));
          alignedEdge ??= locale.languageCode == 'ar'
              ? first.left
              : first.right;
          for (final Text amount in amounts) {
            final Rect bounds = tester.getRect(find.byWidget(amount));
            expect(amount.textAlign, TextAlign.end);
            expect(
              locale.languageCode == 'ar' ? bounds.left : bounds.right,
              closeTo(alignedEdge!, 0.01),
            );
          }
        }

        checkColumns();
        await _tap(tester, find.text(strings.text('Cash')));
        checkColumns();
        await _tap(
          tester,
          find.byKey(const ValueKey<String>('home-liabilities-tab')),
        );
        await _tap(tester, find.text(strings.text('Loan')));
        checkColumns();
        await _tap(
          tester,
          find.byKey(const ValueKey<String>('home-assets-tab')),
        );
        checkColumns();
        await _tap(tester, find.byTooltip(strings.text('Hide balances')));
        await tester.pumpAndSettle();
        checkColumns();
        await _tap(
          tester,
          find.byKey(const ValueKey<String>('home-liabilities-tab')),
        );
        checkColumns();
        await _tap(
          tester,
          find.byKey(const ValueKey<String>('home-liabilities-tab')),
        );
        checkColumns();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('data actions remain accessible inside their category', (
    WidgetTester tester,
  ) async {
    await open(tester, SettingsScreen(onClose: () {}));
    await _tap(tester, find.text('Data'));
    await _tap(tester, find.byTooltip('Refresh rates'));
    expect(container.fxRepository.refreshes, 1);
    expect(find.text('Exchange rates updated'), findsOneWidget);
    await _tap(tester, find.text('Export portfolios'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Import portfolios'))
          .onTap,
      isNotNull,
    );
  });

  testWidgets('base currency and app lock remain persistent settings', (
    WidgetTester tester,
  ) async {
    container.authenticator.result = BiometricResult.success;
    await container.settingsRepository.setAppLockEnabled(true);
    await open(tester, SettingsScreen(onClose: () {}));
    await _tap(tester, find.text('Currency'));
    await _tap(tester, find.text('Base currency'));
    await tester.tap(find.text('EUR — Euro'));
    await tester.pumpAndSettle();
    expect(container.settingsRepository.current.baseCurrency, 'EUR');
    await _tap(tester, find.byTooltip('Back'));
    await _tap(tester, find.text('Security'));
    await _tap(tester, find.text('App lock'));
    expect(container.settingsRepository.current.appLockEnabled, isFalse);
    final SettingsRepository reopened = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    addTearDown(reopened.dispose);
    expect(reopened.current.baseCurrency, 'EUR');
    expect(reopened.current.appLockEnabled, isFalse);
  });

  for (final AssetType type in AssetType.values.where(
    (type) => type.isMarketLinked,
  )) {
    testWidgets(
      '${type.name} shows fetch without automatic-price helper text',
      (WidgetTester tester) async {
        await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
        tester
            .widget<DropdownSelector<AssetType>>(
              find.byType(DropdownSelector<AssetType>),
            )
            .onSelected(type);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          _field('Custom name (optional)'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Fetch latest price'), findsOneWidget);
        expect(
          find.text('Price is fetched automatically on save when online.'),
          findsNothing,
        );
        expect(find.text('Search Yahoo Finance'), findsNothing);
        expect(find.text('Uses fetched name if left blank'), findsNothing);
        expect(_textField('Custom name (optional)'), findsNothing);
        expect(
          find.descendant(
            of: _field('Custom name (optional)'),
            matching: find.byIcon(Icons.edit_outlined),
          ),
          findsOneWidget,
        );
        await _tap(tester, _customNameToggle);
        expect(
          find.descendant(
            of: _field('Custom name (optional)'),
            matching: find.byIcon(Icons.remove),
          ),
          findsOneWidget,
        );
        final TextField customNameField = tester.widget<TextField>(
          find.descendant(
            of: _field('Custom name (optional)'),
            matching: find.byType(TextField),
          ),
        );
        expect(customNameField.decoration?.hintText, type.nameExample);
        expect(customNameField.decoration?.helperText, isNull);
        expect(customNameField.style?.fontSize, 16);
      },
    );
  }

  testWidgets('asset and liability fields use readable label and input sizes', (
    WidgetTester tester,
  ) async {
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
    final ColorScheme assetColors = Theme.of(
      tester.element(find.byType(AssetEditScreen)),
    ).colorScheme;
    final Material triggerBox = tester.widget<Material>(
      find.byKey(const ValueKey<String>('market-search-trigger')),
    );
    expect(
      (triggerBox.shape! as RoundedRectangleBorder).side.color,
      canvasBoxBorderColor(assetColors),
    );
    final TextField quantityInput = tester.widget<TextField>(
      find.descendant(of: _field('Quantity'), matching: find.byType(TextField)),
    );
    expect(
      (quantityInput.decoration?.enabledBorder as OutlineInputBorder?)
          ?.borderSide
          .color,
      canvasBoxBorderColor(assetColors),
    );
    expect(quantityInput.style?.fontSize, 16);
    await _openMarketSearch(tester);
    final TextField dialogInput = tester.widget<TextField>(_dialogSearchInput);
    expect(dialogInput.decoration?.hintText, 'e.g. Apple or AAPL');
    expect(dialogInput.style?.fontSize, 16);
    await _tap(tester, find.widgetWithText(TextButton, 'Close'));
    final ThemeData assetTheme = Theme.of(
      tester.element(find.byType(AssetEditScreen)),
    );
    final TextStyle? floatingLabel = WidgetStateProperty.resolveAs(
      assetTheme.inputDecorationTheme.floatingLabelStyle,
      const <WidgetState>{},
    );
    expect(floatingLabel!.fontSize! * 0.75, 14);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await open(
      tester,
      const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
    );
    final TextField liabilityName = tester.widget<TextField>(
      find.descendant(of: _field('Name'), matching: find.byType(TextField)),
    );
    expect(liabilityName.style?.fontSize, 16);
  });

  testWidgets('asset selectors and Next skip filled required fields', (
    WidgetTester tester,
  ) async {
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
    await _tap(tester, find.byType(DropdownSelector<AssetType>));
    await _tap(tester, find.text('Cash').last);
    expect(_editableField(tester, 'Value').focusNode.hasFocus, isTrue);
    await tester.enterText(_textField('Value'), '100');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(_editableField(tester, 'Name').focusNode.hasFocus, isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tap(tester, find.byType(CurrencySelector));
    await _tap(tester, find.text('EUR — Euro'));
    expect(_editableField(tester, 'Name').focusNode.hasFocus, isTrue);
    await tester.enterText(_textField('Name'), 'Savings');
    expect(
      tester.widget<TextField>(_textField('Name')).textInputAction,
      TextInputAction.done,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(container.assetRepository.saved, isNull);

    await _tap(tester, find.byType(DropdownSelector<AssetType>));
    await _tap(tester, find.text('Metals').last);
    await _tap(tester, find.text('Gold'));
    await _tap(tester, find.text('Choose karat'));
    await _tap(tester, find.text('22K'));
    expect(_editableField(tester, 'Name').controller.text, 'Savings');
    final weight = _textField('Weight (grams)');
    await tester.ensureVisible(weight);
    await tester.enterText(weight, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(container.assetRepository.saved, isNull);
  });

  for (final bool selectListing in <bool>[false, true]) {
    testWidgets(
      '${selectListing ? 'selecting a listing' : 'submitting a ticker'} focuses quantity then dismisses without saving',
      (WidgetTester tester) async {
        container.stockSearchService.matches = const <StockSearchResult>[
          StockSearchResult(
            symbol: 'AAPL',
            name: 'Apple Inc.',
            exchange: 'NASDAQ',
          ),
        ];
        await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
        await _openMarketSearch(tester);
        await tester.enterText(_dialogSearchInput, 'AAPL');
        if (selectListing) {
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          await _tap(
            tester,
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Apple Inc.'),
            ),
          );
        } else {
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
        }
        expect(_editableField(tester, 'Quantity').focusNode.hasFocus, isTrue);
        await tester.enterText(_textField('Quantity'), '5');
        expect(
          tester.widget<TextField>(_textField('Quantity')).textInputAction,
          TextInputAction.done,
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);
        expect(container.assetRepository.saved, isNull);
        await tester.scrollUntilVisible(
          _field('Custom name (optional)'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(_textField('Custom name (optional)'), findsNothing);
        await _tap(tester, _customNameToggle);
        expect(
          _editableField(tester, 'Custom name (optional)').controller.text,
          isEmpty,
        );
      },
    );
  }

  for (final AssetType type in AssetType.values.where(
    (AssetType type) => type.isMarketLinked,
  )) {
    testWidgets('${type.displayName} focuses the picker before quantity', (
      WidgetTester tester,
    ) async {
      await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
      await _tap(tester, find.byType(DropdownSelector<AssetType>));
      await _tap(tester, find.widgetWithText(ListTile, type.displayName));
      final Finder market = find.byType(StockSearchField);
      final FocusNode pickerFocus = tester
          .widget<StockSearchField>(market)
          .focusNode!;
      expect(pickerFocus.hasPrimaryFocus, isTrue);
      expect(_editableField(tester, 'Quantity').focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: _dialogSearchInput,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await _tap(tester, find.widgetWithText(TextButton, 'Close'));
      expect(pickerFocus.hasPrimaryFocus, isTrue);

      await _tap(tester, find.byType(CurrencySelector));
      await _tap(tester, find.text('EUR — Euro'));
      expect(pickerFocus.hasPrimaryFocus, isTrue);
      await _openMarketSearch(tester);
      await tester.enterText(
        _dialogSearchInput,
        type == AssetType.crypto ? 'BTC-USD' : 'AAPL',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(_editableField(tester, 'Quantity').focusNode.hasFocus, isTrue);
      expect(container.assetRepository.saved, isNull);
    });
  }

  testWidgets('metals focus purity, then Name before weight', (
    WidgetTester tester,
  ) async {
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
    await _tap(tester, find.byType(DropdownSelector<AssetType>));
    await _tap(tester, find.widgetWithText(ListTile, 'Metals'));
    expect(find.text('Choose a metal'), findsOneWidget);
    await _tap(tester, find.widgetWithText(ListTile, 'Gold'));
    final PickerChip purity = tester.widget<PickerChip>(
      find.widgetWithText(PickerChip, 'Choose karat'),
    );
    expect(purity.focusNode!.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(ListTile, '22K'));
    expect(_editableField(tester, 'Name').focusNode.hasFocus, isTrue);
    await tester.enterText(_textField('Name'), 'Family gold');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(_editableField(tester, 'Weight (grams)').focusNode.hasFocus, isTrue);
  });

  for (final LiabilityType type in LiabilityType.values) {
    testWidgets('${type.displayName} focuses amount, then Name', (
      WidgetTester tester,
    ) async {
      Future<void> selectType() async {
        await _tap(tester, find.byType(DropdownSelector<LiabilityType>));
        await tester.enterText(_dialogSearchInput, type.displayName);
        await tester.pumpAndSettle();
        await _tap(tester, find.widgetWithText(ListTile, type.displayName));
      }

      await open(
        tester,
        const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
      );
      await selectType();
      expect(
        _editableField(tester, 'Outstanding amount').focusNode.hasFocus,
        isTrue,
      );
      final Finder preview = find.byKey(
        const ValueKey<String>('liability-outstanding-amount'),
      );
      expect(
        find.descendant(
          of: find.byType(HoldingEditorFooter),
          matching: find.text('Outstanding amount'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(preview).data, CurrencyUtil.format(0, 'USD'));
      expect(
        tester.getBottomRight(preview).dy,
        lessThan(tester.getTopRight(_saveButton).dy),
      );
      await tester.enterText(_textField('Outstanding amount'), '1200');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(_editableField(tester, 'Name').focusNode.hasFocus, isTrue);
      expect(
        tester.widget<Text>(preview).data,
        CurrencyUtil.format(1200, 'USD'),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await selectType();
      expect(_editableField(tester, 'Name').focusNode.hasFocus, isTrue);
      await tester.enterText(_textField('Name'), 'Home loan');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(container.liabilityRepository.saved, isNull);
    });
  }

  for (final bool dark in <bool>[false, true]) {
    testWidgets(
      '${dark ? 'Midnight' : 'Light'} field labels stand out from name previews',
      (WidgetTester tester) async {
        container.assetRepository.existing = const AssetEntity(
          id: 1,
          portfolioId: 1,
          type: AssetType.stock,
          name: 'Example company',
          currency: 'USD',
          quantity: 2,
          symbol: 'AAPL',
          lastPrice: 100,
          createdAt: 0,
          updatedAt: 0,
        );
        await tester.pumpWidget(
          _app(
            container,
            const AssetEditScreen(portfolioId: 1, assetId: 1),
            brightness: dark ? Brightness.dark : Brightness.light,
            appTheme: dark ? AppTheme.midnight : AppTheme.classic,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          _field('Custom name (optional)'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(_textField('Custom name (optional)'), findsNothing);
        await _tap(tester, _customNameToggle);

        TextStyle renderedStyle(String text) => tester
            .widget<RichText>(
              find.descendant(
                of: find.descendant(
                  of: _field('Custom name (optional)'),
                  matching: find.text(text),
                ),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style!;

        final ColorScheme colors = Theme.of(
          tester.element(_field('Custom name (optional)')),
        ).colorScheme;
        final TextStyle label = renderedStyle('Custom name (optional)');
        final TextStyle preview = renderedStyle('Example company');
        expect(label.color, colors.onSurface);
        expect(label.fontWeight, FontWeight.w500);
        expect(preview.color, colors.onSurfaceVariant);
        expect(preview.fontWeight, FontWeight.w400);
        expect(label.color, isNot(preview.color));

        final Finder input = find.descendant(
          of: _field('Custom name (optional)'),
          matching: find.byType(TextField),
        );
        await _tap(tester, input);
        expect(renderedStyle('Custom name (optional)').color, colors.onSurface);
        expect(renderedStyle('Example company').color, colors.onSurfaceVariant);
        await tester.enterText(input, 'My shares');
        await tester.pumpAndSettle();
        final EditableText entered = tester.widget<EditableText>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        );
        expect(entered.style.color, colors.onSurface);
        expect(entered.controller.text, 'My shares');
        expect(find.text('Notes (optional)'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'editing a market asset with customName opens Custom name automatically and omits footer portfolio summary',
    (WidgetTester tester) async {
      container.assetRepository.existing = const AssetEntity(
        id: 7,
        portfolioId: 1,
        type: AssetType.stock,
        name: 'Apple Inc.',
        customName: 'Retirement shares',
        currency: 'USD',
        quantity: 4,
        symbol: 'AAPL',
        lastPrice: 200,
        createdAt: 0,
        updatedAt: 0,
      );
      await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 7));
      expect(
        find.descendant(
          of: find.byType(HoldingEditorFooter),
          matching: find.byType(HoldingPortfolioLabel),
        ),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        _field('Custom name (optional)'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(_textField('Custom name (optional)'), findsOneWidget);
      expect(
        _editableField(tester, 'Custom name (optional)').controller.text,
        'Retirement shares',
      );
    },
  );

  for (final (bool prominent, double textScale) layout in <(bool, double)>[
    (false, 1),
    (true, 1),
    (false, 1.5),
  ]) {
    testWidgets('field label and input offsets are independent at $layout', (
      WidgetTester tester,
    ) async {
      final (bool prominent, double textScale) = layout;
      final Locale locale = Locale(textScale > 1 ? 'ar' : 'en');
      final String label = AppLocalizations(locale).text('Name');
      final TextEditingController reference = TextEditingController();
      final TextEditingController current = TextEditingController();
      addTearDown(reference.dispose);
      addTearDown(current.dispose);

      await tester.pumpWidget(
        _app(
          container,
          Scaffold(
            body: Builder(
              builder: (BuildContext context) => Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>('reference-offset-field'),
                        controller: reference,
                        style: prominent
                            ? Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  )
                            : Theme.of(context).textTheme.bodyLarge,
                        decoration: InputDecoration(
                          labelText: label,
                          hintText: 'Example',
                          contentPadding: prominent
                              ? EdgeInsets.zero
                              : const EdgeInsets.only(top: 22, bottom: 6),
                          border: prominent ? InputBorder.none : null,
                          enabledBorder: prominent ? InputBorder.none : null,
                          focusedBorder: prominent ? InputBorder.none : null,
                        ),
                      ),
                    ),
                    Expanded(
                      child: LabeledTextField(
                        key: const ValueKey<String>('current-offset-field'),
                        controller: current,
                        label: label,
                        placeholder: 'Example',
                        prominent: prominent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          locale: locale,
          textScale: textScale,
          brightness: textScale > 1 ? Brightness.dark : Brightness.light,
          appTheme: textScale > 1 ? AppTheme.midnight : AppTheme.classic,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final Finder oldField = find.byKey(
        const ValueKey<String>('reference-offset-field'),
      );
      final Finder newField = find.byKey(
        const ValueKey<String>('current-offset-field'),
      );
      Rect bounds(Finder field, Finder child) =>
          tester.getRect(find.descendant(of: field, matching: child));
      void expectOffsets() {
        expect(
          bounds(newField, find.text(label)).top,
          closeTo(bounds(oldField, find.text(label)).top - 4, 0.01),
        );
        expect(
          bounds(newField, find.byType(EditableText)).top,
          closeTo(bounds(oldField, find.byType(EditableText)).top + 2, 0.01),
        );
        expect(
          bounds(newField, find.text(label)).size,
          bounds(oldField, find.text(label)).size,
        );
        expect(tester.getSize(newField), tester.getSize(oldField));
        if (!prominent) {
          expect(
            bounds(newField, find.byType(InputDecorator)).bottom,
            closeTo(bounds(oldField, find.byType(InputDecorator)).bottom, 0.01),
          );
        }
      }

      expectOffsets();
      expect(
        bounds(newField, find.text('Example')).top,
        closeTo(bounds(oldField, find.text('Example')).top + 2, 0.01),
      );
      reference.text = '123';
      await tester.enterText(
        find.descendant(of: newField, matching: find.byType(TextField)),
        '123',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expectOffsets();
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(label), findsNWidgets(2));
      } finally {
        semantics.dispose();
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final bool liability in <bool>[false, true]) {
    testWidgets(
      '${liability ? 'liability' : 'asset'} Canvas fields keep labels above outlined inputs',
      (WidgetTester tester) async {
        final Locale locale = Locale(liability ? 'ar' : 'en');
        final AppLocalizations strings = AppLocalizations(locale);
        await tester.pumpWidget(
          _app(
            container,
            liability
                ? const LiabilityEditScreen(portfolioId: 1, liabilityId: 0)
                : const AssetEditScreen(portfolioId: 1, assetId: 0),
            locale: locale,
            textScale: liability ? 1.5 : 1,
            brightness: liability ? Brightness.dark : Brightness.light,
            appTheme: liability ? AppTheme.midnight : AppTheme.classic,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        void expectFieldLayout(Finder field) {
          final Rect input = tester.getRect(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          final Rect decoration = tester.getRect(
            find.descendant(of: field, matching: find.byType(InputDecorator)),
          );
          final LabeledTextField? labeled =
              tester.widget(field) is LabeledTextField
              ? tester.widget<LabeledTextField>(field)
              : null;
          if (labeled?.canvas ?? false) {
            final TextField textField = tester.widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            );
            expect(
              textField.decoration?.enabledBorder,
              isA<OutlineInputBorder>(),
            );
            expect(decoration.bottom, greaterThan(input.bottom));
            expect(
              tester.getRect(find.text(labeled!.label)).bottom,
              lessThan(input.top),
            );
          } else if (labeled?.maxLength == null) {
            expect(decoration.bottom - input.bottom, inInclusiveRange(4, 8));
          } else {
            expect(decoration.bottom, greaterThan(input.bottom));
            expect(
              find.text('${labeled!.controller.text.characters.length}/60'),
              findsOneWidget,
            );
          }
          expect(decoration.height, greaterThanOrEqualTo(48));
        }

        final String label = strings.text(liability ? 'Name' : 'Quantity');
        final Finder field = _field(label);
        await _tap(tester, _textField(label));
        expectFieldLayout(field);
        await tester.enterText(
          find.descendant(of: field, matching: find.byType(TextField)),
          liability ? 'Home loan' : '12',
        );
        await tester.pumpAndSettle();
        expectFieldLayout(field);
        final Rect floatingLabel = tester.getRect(find.text(label));
        final Rect input = tester.getRect(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        expect(floatingLabel.bottom, lessThanOrEqualTo(input.top));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expectFieldLayout(field);

        expect(find.text('Notes (optional)'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final AssetType type in AssetType.values) {
    testWidgets('${type.name} keeps its valuation fields and currency', (
      WidgetTester tester,
    ) async {
      container.assetRepository.existing = AssetEntity(
        id: 1,
        portfolioId: 1,
        type: type,
        name: 'Holding',
        currency: 'USD',
        quantity: 2,
        pricePerUnit: 10,
        metal: type == AssetType.metals ? PreciousMetal.gold : null,
        purity: type == AssetType.metals ? '22K' : null,
        lastPrice: 10,
        symbol: 'AAPL',
        manualValue: 20,
        createdAt: 0,
        updatedAt: 0,
      );
      await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 1));
      expect(find.byType(CurrencySelector), findsOneWidget);
      expect(
        tester.widget<CurrencySelector>(find.byType(CurrencySelector)).currency,
        'USD',
      );
      expect(find.text('Notes (optional)'), findsNothing);
      switch (type.valuationMode) {
        case ValuationMode.market:
          expect(_field('Name'), findsNothing);
          expect(find.text('Estimated value'), findsOneWidget);
          final String tickerLabel = type == AssetType.crypto
              ? 'Coin or ticker'
              : 'Company or Ticker';
          final Finder marketField = find.byType(StockSearchField);
          expect(
            find.descendant(of: marketField, matching: find.text(tickerLabel)),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('selected-market-holding')),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            _field('Quantity'),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          expect(_field('Quantity'), findsOneWidget);
          await tester.scrollUntilVisible(
            _field('Custom name (optional)'),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Fetch latest price'), findsOneWidget);
          expect(_field('Custom name (optional)'), findsOneWidget);
          expect(
            tester.getRect(_field('Custom name (optional)')).top,
            greaterThan(
              tester
                  .getRect(
                    find.byKey(
                      const ValueKey<String>('selected-market-holding'),
                    ),
                  )
                  .bottom,
            ),
          );
          expect(
            tester.getRect(_field('Custom name (optional)')).top,
            greaterThan(tester.getRect(_field('Quantity')).bottom),
          );
        case ValuationMode.quantity:
          expect(_field('Name'), findsOneWidget);
          expect(_field('Custom name (optional)'), findsNothing);
          await tester.scrollUntilVisible(
            _field('Quantity'),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          expect(_field('Quantity'), findsOneWidget);
          expect(_field('Price per g'), findsOneWidget);
          expect(find.text('Estimated value'), findsOneWidget);
        case ValuationMode.metal:
          expect(find.text('Gold'), findsOneWidget);
          expect(find.text('22K'), findsOneWidget);
          await tester.scrollUntilVisible(
            _field('Weight (grams)'),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Price per gram'), findsOneWidget);
          expect(_field('Price per gram'), findsNothing);
        case ValuationMode.flat:
          expect(_field('Name'), findsOneWidget);
          expect(_field('Custom name (optional)'), findsNothing);
          expect(_field('Value'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(ListView),
              matching: find.text('Estimated value'),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: find.byType(HoldingEditorFooter),
              matching: find.text('Estimated value'),
            ),
            findsOneWidget,
          );
          expect(_field('Quantity'), findsNothing);
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: _field('Value'),
                    matching: find.byType(EditableText),
                  ),
                )
                .focusNode
                .hasFocus,
            isFalse,
          );
      }
      await _tap(tester, _saveButton);
      expect(container.assetRepository.saved?.type, type);
      expect(container.assetRepository.saved?.currency, 'USD');
      expect(find.byType(AssetEditScreen), findsNothing);
    });
  }

  testWidgets('new flat assets focus the value with a blinking cursor', (
    WidgetTester tester,
  ) async {
    for (final AssetType type in AssetType.values.where(
      (AssetType type) => type.valuationMode == ValuationMode.flat,
    )) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
      await _tap(tester, find.byType(DropdownSelector<AssetType>));
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        type.displayName,
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text(type.displayName).last);
      final EditableTextState value = tester.state<EditableTextState>(
        find.descendant(
          of: _field('Value'),
          matching: find.byType(EditableText),
        ),
      );
      expect(value.widget.focusNode.hasFocus, isTrue, reason: type.name);
      expect(value.widget.controller.selection.isCollapsed, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      final bool cursorVisible = value.cursorCurrentlyVisible;
      await tester.pump(const Duration(milliseconds: 500));
      expect(value.cursorCurrentlyVisible, !cursorVisible);
      await tester.enterText(_textField('Value'), '100');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(_editableField(tester, 'Name').focusNode.hasFocus, isTrue);
    }
  });

  testWidgets('new liabilities focus the amount without stealing later focus', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
    );
    final EditableTextState amount = tester.state<EditableTextState>(
      find.descendant(
        of: _field('Outstanding amount'),
        matching: find.byType(EditableText),
      ),
    );
    expect(amount.widget.focusNode.hasFocus, isTrue);
    expect(amount.widget.controller.selection.isCollapsed, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    final bool cursorVisible = amount.cursorCurrentlyVisible;
    await tester.pump(const Duration(milliseconds: 500));
    expect(amount.cursorCurrentlyVisible, !cursorVisible);
    await tester.enterText(
      find.descendant(of: _field('Name'), matching: find.byType(TextField)),
      'Synthetic loan',
    );
    await tester.pump();
    expect(amount.widget.focusNode.hasFocus, isFalse);
  });

  testWidgets('new asset value does not steal focus while entering a name', (
    WidgetTester tester,
  ) async {
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((EditableText input) => input.focusNode.hasFocus),
      isFalse,
    );
    await _tap(tester, find.byType(DropdownSelector<AssetType>));
    await _tap(tester, find.text('Cash').last);
    final Finder name = find.descendant(
      of: _field('Name'),
      matching: find.byType(TextField),
    );
    await tester.enterText(name, 'Synthetic cash');
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: _field('Name'),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('asset type and currency changes preserve hidden stored notes', (
    WidgetTester tester,
  ) async {
    container.assetRepository.existing = const AssetEntity(
      id: 1,
      portfolioId: 1,
      type: AssetType.gold,
      name: 'Gold',
      currency: 'USD',
      quantity: 2,
      pricePerUnit: 10,
      notes: 'Keep this note',
      createdAt: 0,
      updatedAt: 0,
    );
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 1));
    expect(find.text('Notes (optional)'), findsNothing);
    await _tap(tester, find.byType(DropdownSelector<AssetType>));
    await _tap(tester, find.text('Cash').last);
    await tester.enterText(
      find.descendant(of: _field('Name'), matching: find.byType(TextField)),
      'Savings',
    );
    await tester.enterText(
      find.descendant(of: _field('Value'), matching: find.byType(TextField)),
      '123',
    );
    await _tap(tester, find.byType(CurrencySelector));
    await tester.tap(find.text('EUR — Euro'));
    await tester.pumpAndSettle();
    await _tap(tester, _saveButton);
    expect(container.assetRepository.saved?.name, 'Savings');
    expect(container.assetRepository.saved?.manualValue, 123);
    expect(container.assetRepository.saved?.notes, 'Keep this note');
    expect(container.assetRepository.saved?.currency, 'EUR');
  });

  testWidgets('existing asset notes stay hidden and estimates stay live', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    container.assetRepository.existing = const AssetEntity(
      id: 1,
      portfolioId: 1,
      type: AssetType.gold,
      name: 'Gold',
      currency: 'USD',
      quantity: 2,
      pricePerUnit: 10,
      notes: 'Existing asset note',
      createdAt: 0,
      updatedAt: 0,
    );
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 1));
    expect(find.text('Notes (optional)'), findsNothing);
    expect(find.text('\$20'), findsWidgets);
    await _tap(tester, _textField('Price per g'));
    await tester.enterText(
      find.descendant(
        of: _field('Price per g'),
        matching: find.byType(TextField),
      ),
      '12',
    );
    await tester.pumpAndSettle();
    expect(find.text('\$24'), findsWidgets);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(container.assetRepository.deleted, isNull);
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Delete'));
    expect(container.assetRepository.deleted, 1);
    expect(find.byType(AssetEditScreen), findsNothing);
  });

  for (final LiabilityType type in LiabilityType.values) {
    testWidgets('${type.name} preserves hidden notes, amount and deletion', (
      WidgetTester tester,
    ) async {
      container.liabilityRepository.existing = LiabilityEntity(
        id: 1,
        portfolioId: 1,
        type: type,
        name: 'Debt',
        currency: 'EUR',
        amount: 500,
        notes: 'Existing note',
        createdAt: 0,
        updatedAt: 0,
      );
      await open(
        tester,
        const LiabilityEditScreen(portfolioId: 1, liabilityId: 1),
      );
      expect(_field('Outstanding amount'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(HoldingEditorFooter),
          matching: find.text(CurrencyUtil.format(500, 'EUR')),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: _field('Outstanding amount'),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isFalse,
      );
      expect(find.text('Notes (optional)'), findsNothing);
      expect(find.text('Save liability'), findsOneWidget);
      await _tap(tester, _saveButton);
      expect(container.liabilityRepository.saved?.type, type);
      expect(container.liabilityRepository.saved?.amount, 500);
      expect(container.liabilityRepository.saved?.notes, 'Existing note');
      expect(find.byType(HoldingSavedSummaryScreen), findsOneWidget);
      expect(find.text('Liability updated.'), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const ValueKey<String>('back-to-portfolio')),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(container.liabilityRepository.deleted, isNull);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Delete'));
      expect(container.liabilityRepository.deleted, 1);
      expect(find.byType(LiabilityEditScreen), findsNothing);
    });
  }

  testWidgets('new liability omits Notes and currency stays editable', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
    );
    expect(find.text('Notes (optional)'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);
    await _tap(tester, find.byTooltip('Back'));
    expect(find.byType(LiabilityEditScreen), findsNothing);
    expect(container.liabilityRepository.saved, isNull);

    await open(
      tester,
      const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
    );
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);
    expect(container.liabilityRepository.saved, isNull);
    await tester.enterText(
      find.descendant(of: _field('Name'), matching: find.byType(TextField)),
      'Loan',
    );
    await tester.enterText(
      find.descendant(
        of: _field('Outstanding amount'),
        matching: find.byType(TextField),
      ),
      '42',
    );
    await _tap(tester, find.byType(CurrencySelector));
    await tester.tap(find.text('EUR — Euro'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(HoldingEditorFooter),
        matching: find.text(CurrencyUtil.format(42, 'EUR')),
      ),
      findsOneWidget,
    );
    await _tap(tester, _saveButton);
    expect(container.liabilityRepository.saved?.amount, 42);
    expect(container.liabilityRepository.saved?.currency, 'EUR');
    expect(container.liabilityRepository.saved?.notes, isNull);
  });

  testWidgets('settings and forms fit a narrow screen with large Arabic text', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    for (final Widget page in <Widget>[
      SettingsScreen(onClose: () {}),
      const AssetEditScreen(portfolioId: 1, assetId: 0),
      const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
    ]) {
      await tester.pumpWidget(
        _app(container, page, locale: const Locale('ar'), textScale: 2),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      if (page is SettingsScreen) {
        const AppLocalizations strings = AppLocalizations(Locale('ar'));
        for (final String category in <String>[
          'Appearance',
          'Currency',
          'Security',
          'Data',
          'About',
        ]) {
          await _tap(tester, find.text(strings.text(category)));
          expect(tester.takeException(), isNull);
          await _tap(tester, find.byTooltip(strings.text('Back')));
        }
      } else {
        expect(find.text('Notes (optional)'), findsNothing);
        if (page is LiabilityEditScreen) {
          const double keyboardHeight = 250;
          tester.view.viewInsets = const FakeViewPadding(
            bottom: keyboardHeight,
          );
          await tester.pumpAndSettle();
          final Finder preview = find.byKey(
            const ValueKey<String>('liability-outstanding-amount'),
          );
          expect(
            tester.getBottomRight(preview).dy,
            lessThan(tester.getTopRight(_saveButton).dy),
          );
          expect(
            tester.getBottomRight(_saveButton).dy,
            lessThan(640 - keyboardHeight),
          );
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'Block screenshots is enabled by default, updates FLAG_SECURE channel and persists',
    (WidgetTester tester) async {
      final List<bool> channelCalls = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScreenshotProtection.channel, (
            MethodCall call,
          ) async {
            expect(call.method, 'setScreenshotProtection');
            channelCalls.add(call.arguments as bool);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotProtection.channel, null),
      );

      expect(container.settingsRepository.current.blockScreenshots, isTrue);
      await container.settingsRepository.setHideBalances(true);

      await open(tester, SettingsScreen(onClose: () {}));
      await _tap(tester, find.text('Security'));

      SwitchListTile tile() => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Block screenshots'),
      );
      expect(tile().value, isTrue);

      await _tap(tester, find.text('Block screenshots'));
      expect(tile().value, isFalse);
      expect(container.settingsRepository.current.blockScreenshots, isFalse);
      expect(channelCalls, <bool>[false]);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final SettingsRepository reopened = SettingsRepository(prefs);
      addTearDown(reopened.dispose);
      expect(reopened.current.blockScreenshots, isFalse);
      expect(reopened.current.hideBalances, isTrue);

      await _tap(tester, find.text('Block screenshots'));
      expect(tile().value, isTrue);
      expect(container.settingsRepository.current.blockScreenshots, isTrue);
      expect(channelCalls, <bool>[false, true]);
    },
  );

  for (final bool throwOnWrite in <bool>[false, true]) {
    testWidgets(
      'failed screenshot-protection writes restore default and localize error (throws: $throwOnWrite)',
      (WidgetTester tester) async {
        final List<bool> channelCalls = <bool>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotProtection.channel, (
              MethodCall call,
            ) async {
              channelCalls.add(call.arguments as bool);
              return true;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(ScreenshotProtection.channel, null),
        );

        final _RejectingScreenshotPreferences rejected =
            _RejectingScreenshotPreferences(throwOnWrite: throwOnWrite);
        final SettingsRepository failing = SettingsRepository(rejected);
        addTearDown(failing.dispose);
        expect(failing.current.blockScreenshots, isTrue);

        const AppLocalizations es = AppLocalizations(Locale('es'));
        await tester.pumpWidget(
          _app(
            _Container(failing),
            SettingsScreen(onClose: () {}),
            locale: const Locale('es'),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await _tap(tester, find.text(es.text('Security')));
        await _tap(tester, find.text(es.text('Block screenshots')));

        expect(failing.current.blockScreenshots, isTrue);
        expect(rejected.reloads, 1);
        expect(channelCalls, isEmpty);
        expect(
          tester
              .widget<SwitchListTile>(
                find.widgetWithText(
                  SwitchListTile,
                  es.text('Block screenshots'),
                ),
              )
              .value,
          isTrue,
        );
        expect(
          find.textContaining(
            'No se pudo guardar la protección contra capturas:',
          ),
          findsOneWidget,
        );
      },
    );
  }

  test(
    'native screenshot-protection failure rolls back stored preference',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScreenshotProtection.channel, (
            MethodCall call,
          ) async {
            throw PlatformException(code: 'WINDOW_ERROR', message: 'Failed');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ScreenshotProtection.channel, null),
      );

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('block_screenshots'), isNull);

      final SettingsViewModel viewModel = SettingsViewModel(
        settingsRepository: container.settingsRepository,
        portfolioRepository: container.portfolioRepository,
        fxRepository: container.fxRepository,
        backupRepository: container.backupRepository,
      );
      addTearDown(viewModel.dispose);

      await viewModel.setBlockScreenshots(false);
      expect(
        viewModel.message,
        startsWith("Couldn't save screenshot protection:"),
      );
      expect(viewModel.settings.blockScreenshots, isTrue);
      expect(container.settingsRepository.current.blockScreenshots, isTrue);
      expect(prefs.getBool('block_screenshots'), isNull);
    },
  );

  for (final (AppTheme, Brightness) appearance in <(AppTheme, Brightness)>[
    (AppTheme.midnight, Brightness.dark),
    (AppTheme.classic, Brightness.light),
  ]) {
    testWidgets(
      'statistics keeps large amounts readable and strictly inside the donut hole in $appearance',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        await container.settingsRepository.setBaseCurrency('INR');
        container.assetRepository.items = const <AssetEntity>[
          AssetEntity(
            id: 1,
            portfolioId: 1,
            type: AssetType.cash,
            name: 'Treasury reserve',
            currency: 'INR',
            manualValue: 68731729181,
            createdAt: 0,
            updatedAt: 0,
          ),
        ];
        container.liabilityRepository.items = const <LiabilityEntity>[
          LiabilityEntity(
            id: 1,
            portfolioId: 1,
            type: LiabilityType.loan,
            name: 'Short loan',
            currency: 'INR',
            amount: 2000,
            createdAt: 0,
            updatedAt: 0,
          ),
        ];

        await tester.pumpWidget(
          _app(
            container,
            const StatisticsScreen(),
            appTheme: appearance.$1,
            brightness: appearance.$2,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        void expectInsideFirstDonutHole(Finder textFinder) {
          final Finder donutFinder = find.byType(DonutChart).first;
          final DonutChart donut = tester.widget<DonutChart>(donutFinder);
          final Offset center = tester.getCenter(donutFinder);
          final Rect rect = tester.getRect(textFinder);
          for (final Offset corner in <Offset>[
            rect.topLeft,
            rect.topRight,
            rect.bottomLeft,
            rect.bottomRight,
          ]) {
            expect(
              (corner - center).distance,
              lessThan(donut.innerRadius),
              reason:
                  '$corner must stay inside hole radius ${donut.innerRadius}',
            );
          }
        }

        final Finder overviewDonut = find.byType(DonutChart).first;
        final Finder centerNetWorth = find.descendant(
          of: overviewDonut,
          matching: find.text('₹6,873.17 Cr'),
        );
        expect(centerNetWorth, findsOneWidget);
        expect(
          tester.widget<Text>(centerNetWorth).semanticsLabel,
          CurrencyUtil.format(68731727181, 'INR'),
        );
        expect(
          find.descendant(
            of: overviewDonut,
            matching: find.byTooltip(CurrencyUtil.format(68731727181, 'INR')),
          ),
          findsOneWidget,
        );
        expectInsideFirstDonutHole(
          find.descendant(of: overviewDonut, matching: find.text('Net worth')),
        );
        expectInsideFirstDonutHole(centerNetWorth);

        // Exact unrounded values remain visible in the Overview legend rows.
        final Finder overviewCard = find.byType(Card).first;
        expect(
          find.descendant(
            of: overviewCard,
            matching: find.text(CurrencyUtil.format(68731729181, 'INR')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: overviewCard,
            matching: find.text(CurrencyUtil.format(2000, 'INR')),
          ),
          findsOneWidget,
        );

        // Selecting the small Liabilities row displays exact digits inside the hole.
        await tester.tap(find.text('Liabilities').first);
        await tester.pumpAndSettle();
        final Finder selectedSmallAmount = find.descendant(
          of: overviewDonut,
          matching: find.text(CurrencyUtil.format(2000, 'INR')),
        );
        expect(selectedSmallAmount, findsOneWidget);
        expectInsideFirstDonutHole(selectedSmallAmount);
        expectInsideFirstDonutHole(
          find.descendant(of: overviewDonut, matching: find.text('0.0%')),
        );

        // Tapping the donut hole clears the slice selection back to Net worth.
        await tester.tapAt(tester.getCenter(overviewDonut));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: overviewDonut, matching: find.text('Net worth')),
          findsOneWidget,
        );
        expect(centerNetWorth, findsOneWidget);

        // Masked mode hides both compact center and exact legend balances.
        await container.settingsRepository.setHideBalances(true);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: overviewDonut,
            matching: find.text(CurrencyUtil.masked('INR')),
          ),
          findsOneWidget,
        );
        expect(find.text('₹6,873.17 Cr'), findsNothing);
        expect(
          find.text(CurrencyUtil.format(68731729181, 'INR')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'statistics keeps large RTL amounts inside donut holes and legend rows at 180% text scale',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await container.settingsRepository.setBaseCurrency('USD');
      container.assetRepository.items = const <AssetEntity>[
        AssetEntity(
          id: 1,
          portfolioId: 1,
          type: AssetType.realEstate,
          name: 'Global index',
          currency: 'USD',
          manualValue: 987654321098,
          createdAt: 0,
          updatedAt: 0,
        ),
      ];
      container.liabilityRepository.items = const <LiabilityEntity>[
        LiabilityEntity(
          id: 1,
          portfolioId: 1,
          type: LiabilityType.creditCard,
          name: 'Corporate line',
          currency: 'USD',
          amount: 123456789,
          createdAt: 0,
          updatedAt: 0,
        ),
      ];

      await tester.pumpWidget(
        _app(
          container,
          const StatisticsScreen(),
          locale: const Locale('ar'),
          textScale: 1.8,
          appTheme: AppTheme.midnight,
          brightness: Brightness.dark,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final Finder overviewDonut = find.byType(DonutChart).first;
      final DonutChart donut = tester.widget<DonutChart>(overviewDonut);
      final Offset center = tester.getCenter(overviewDonut);
      final Finder centerAmount = find.descendant(
        of: overviewDonut,
        matching: find.text(
          CurrencyUtil.formatCompact(987654321098 - 123456789, 'USD'),
        ),
      );
      expect(centerAmount, findsOneWidget);
      expect(
        tester.widget<Text>(centerAmount).textDirection,
        TextDirection.ltr,
      );
      for (final Element textElement
          in find
              .descendant(of: overviewDonut, matching: find.byType(Text))
              .evaluate()) {
        final Rect rect = tester.getRect(find.byWidget(textElement.widget));
        for (final Offset corner in <Offset>[
          rect.topLeft,
          rect.topRight,
          rect.bottomLeft,
          rect.bottomRight,
        ]) {
          expect((corner - center).distance, lessThan(donut.innerRadius));
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home displays customName override when set and fetched name otherwise',
    (WidgetTester tester) async {
      await container.settingsRepository.setHideBalances(false);
      container.assetRepository.items = const <AssetEntity>[
        AssetEntity(
          id: 1,
          portfolioId: 1,
          type: AssetType.stock,
          name: 'Apple Inc.',
          currency: 'USD',
          symbol: 'AAPL',
          quantity: 10,
          lastPrice: 220,
          createdAt: 0,
          updatedAt: 0,
        ),
        AssetEntity(
          id: 2,
          portfolioId: 1,
          type: AssetType.mutualFund,
          name: 'Vanguard S&P 500 ETF',
          customName: 'Retirement S&P 500',
          currency: 'USD',
          symbol: 'VOO',
          quantity: 5,
          lastPrice: 540,
          createdAt: 0,
          updatedAt: 0,
        ),
      ];

      await open(
        tester,
        HomeScreen(
          onOpenAssetEditor: (_, _) {},
          onOpenLiabilityEditor: (_, _) {},
          onManagePortfolios: () {},
          onOpenSettings: () {},
        ),
      );

      await _tap(tester, find.text('Stock'));
      await _tap(tester, find.text('Mutual fund / ETF'));
      expect(find.text('Apple Inc.'), findsOneWidget);
      expect(find.text('Retirement S&P 500'), findsOneWidget);
      expect(find.text('Vanguard S&P 500 ETF'), findsNothing);
    },
  );

  testWidgets(
    'asset, liability and settings property dropdowns and currency picker display intuitive icons',
    (WidgetTester tester) async {
      await container.settingsRepository.setBaseCurrency('USD');

      // 1. Asset editor property chips & Type dropdown items
      await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
      final List<IconData?> assetChipIcons = tester
          .widgetList<PickerChip>(find.byType(PickerChip))
          .map((PickerChip chip) => chip.icon)
          .toList();
      expect(assetChipIcons, <IconData?>[
        assetTypeIcon(AssetType.stock),
        currencyIcon('USD'),
        stockExchangeIcon(StockExchange.us),
      ]);

      Future<void> expectTypeIcons<T>(
        List<T> options,
        String Function(T) label,
        IconData Function(T) icon,
      ) async {
        await _tap(tester, find.byType(DropdownSelector<T>));
        for (final T option in options) {
          final Finder tile = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(ListTile, label(option)),
          );
          await tester.scrollUntilVisible(
            tile,
            100,
            scrollable: find.descendant(
              of: find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(ListView),
              ),
              matching: find.byType(Scrollable),
            ),
          );
          expect(
            (tester.widget<ListTile>(tile).leading! as Icon).icon,
            icon(option),
          );
        }
        await _tap(tester, find.widgetWithText(TextButton, 'Close'));
      }

      await expectTypeIcons<AssetType>(
        AssetType.values.where((type) => type != AssetType.gold).toList(),
        (AssetType type) => type.displayName,
        assetTypeIcon,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // 2. Liability editor property chips & Type dropdown items
      await open(
        tester,
        const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
      );
      final List<IconData?> liabilityChipIcons = tester
          .widgetList<PickerChip>(find.byType(PickerChip))
          .map((PickerChip chip) => chip.icon)
          .toList();
      expect(liabilityChipIcons, <IconData?>[
        liabilityTypeIcon(LiabilityType.loan),
        currencyIcon('USD'),
      ]);

      await expectTypeIcons<LiabilityType>(
        LiabilityType.values,
        (LiabilityType type) => type.displayName,
        liabilityTypeIcon,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // 3. Settings -> Currency -> Base currency chip & Choose currency picker
      await open(tester, SettingsScreen(onClose: () {}));
      await _tap(tester, find.text('Currency'));
      expect(
        tester.widget<PickerChip>(find.byType(PickerChip)).icon,
        Icons.attach_money,
      );

      await _tap(tester, find.text('Base currency'));
      expect(find.text('Choose currency'), findsOneWidget);
      for (final (String code, IconData expected) in <(String, IconData)>[
        ('USD', Icons.attach_money),
        ('EUR', Icons.euro),
        ('GBP', Icons.currency_pound),
        ('INR', Icons.currency_rupee),
        ('JPY', Icons.currency_yen),
        ('CNY', Icons.currency_yuan),
      ]) {
        final ListTile tile = tester.widget<ListTile>(
          find.widgetWithText(
            ListTile,
            '$code — ${CurrencyUtil.displayName(code)}',
          ),
        );
        expect((tile.leading! as Icon).icon, expected, reason: code);
      }

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'AED',
      );
      await tester.pumpAndSettle();
      final ListTile aedTile = tester.widget<ListTile>(
        find.widgetWithText(
          ListTile,
          'AED — ${CurrencyUtil.displayName('AED')}',
        ),
      );
      expect((aedTile.leading! as Icon).icon, Icons.payments_outlined);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'EUR',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR — Euro'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PickerChip>(find.byType(PickerChip)).icon,
        Icons.euro,
      );
    },
  );
}
