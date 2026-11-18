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
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/components/donut_chart.dart';
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/components/drag_reorder_column.dart';
import 'package:okanzo/ui/components/type_icons.dart';
import 'package:okanzo/ui/components/ui_components.dart';
import 'package:okanzo/ui/components/whats_new_dialog.dart';
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/home/category_groups.dart';
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

class _Assets extends Fake implements AssetRepository {
  AssetEntity? existing;
  AssetEntity? saved;
  int? deleted;
  List<int>? lastOrder;
  List<AssetEntity> items = const <AssetEntity>[];

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
  }) async => Result<StockQuote>.offline();
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

  @override
  Stream<CurrencyConverter> get converter =>
      Stream<CurrencyConverter>.value(const CurrencyConverter.empty());

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
  @override
  Future<Result<List<StockSearchResult>>> search(
    String query, {
    required StockSearchType type,
  }) async => Result<List<StockSearchResult>>.success(<StockSearchResult>[]);
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
  @override
  final _Assets assetRepository = _Assets();
  @override
  final StockSearchService stockSearchService = _Search();
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
  (Widget widget) => widget is LabeledTextField && widget.label == label,
);

Finder get _notesInput => find.descendant(
  of: find.byType(OptionalNotesField),
  matching: find.byType(TextField),
);

Future<void> _tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _toggleNotes(WidgetTester tester) => _tap(
  tester,
  find.descendant(
    of: find.byType(OptionalNotesField),
    matching: find.byType(ListTile),
  ),
);

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
      await _tap(tester, find.text('Add'));
      await _tap(tester, find.text('New asset'));
      expect(editors, <String>['asset']);
      expect(find.text('No assets yet'), findsOneWidget);
      await _tap(tester, find.text('Add'));
      await _tap(tester, find.text('New liability'));
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
      final items = tester.widget<DragReorderColumn<AssetLine>>(
        find.byType(DragReorderColumn<AssetLine>),
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
      final loans = tester.widget<DragReorderColumn<LiabilityLine>>(
        find.byType(DragReorderColumn<LiabilityLine>),
      );
      loans.onReordered(loans.items);
      await tester.pumpAndSettle();
      expect(container.liabilityRepository.lastOrder, <int>[1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long-pressing an expanded holding reorders that holding, not its category',
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
      final destination = tester.getCenter(find.text('First cash'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Second cash')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(destination);
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
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
    'Midnight asset layout uses compact chips, paired fields and inline Save',
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
        find.text(CurrencyUtil.format(3864, 'USD')),
      );
      expect(amount.style?.fontSize, 38);
      expect(amount.style?.fontWeight, FontWeight.w500);
      expect(
        tester.getRect(find.byType(PageHeading)).top,
        greaterThan(tester.getRect(find.byTooltip('Back')).bottom),
      );
      expect(
        tester.getRect(_field('Company or ticker')).top,
        tester.getRect(_field('Quantity')).top,
      );
      expect(
        tester.getRect(_field('Company or ticker')).left,
        lessThan(tester.getRect(_field('Quantity')).left),
      );
      final Scaffold scaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(AssetEditScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(scaffold.bottomNavigationBar, isNull);
      expect(find.text('Save asset'), findsNothing);
      final Finder save = find.widgetWithText(FilledButton, 'Save');
      final Finder cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      await tester.scrollUntilVisible(
        save,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(cancel, findsOneWidget);
      expect(tester.getRect(cancel).top, tester.getRect(save).top);
      expect(tester.getRect(cancel).right, lessThan(tester.getRect(save).left));
      expect(
        tester.getRect(save).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(OptionalNotesField)).bottom,
        ),
      );
      expect(tester.takeException(), isNull);
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
      expect(_notesInput, findsNothing);
      switch (type.valuationMode) {
        case ValuationMode.market:
          expect(_field('Name'), findsNothing);
          expect(find.text('Estimated value'), findsOneWidget);
          final String tickerLabel = type == AssetType.crypto
              ? 'Coin or ticker'
              : 'Company or ticker';
          await tester.scrollUntilVisible(
            _field('Quantity'),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          expect(_field(tickerLabel), findsOneWidget);
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
            greaterThan(tester.getRect(_field(tickerLabel)).bottom),
          );
          expect(
            tester.getRect(_field('Custom name (optional)')).top,
            greaterThan(tester.getRect(_field('Quantity')).bottom),
          );
        case ValuationMode.quantity:
          expect(_field('Name'), findsOneWidget);
          expect(_field('Custom name (optional)'), findsNothing);
          expect(_field('Quantity'), findsOneWidget);
          expect(_field('Price per g'), findsOneWidget);
          expect(find.text('Estimated value'), findsOneWidget);
        case ValuationMode.flat:
          expect(_field('Name'), findsOneWidget);
          expect(_field('Custom name (optional)'), findsNothing);
          expect(_field('Value'), findsOneWidget);
          expect(find.text('Estimated value'), findsNothing);
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
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(container.assetRepository.saved?.type, type);
      expect(container.assetRepository.saved?.currency, 'USD');
      expect(find.byType(AssetEditScreen), findsNothing);
    });
  }

  testWidgets('new flat assets focus the value with a blinking cursor', (
    WidgetTester tester,
  ) async {
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
    for (final AssetType type in AssetType.values.where(
      (AssetType type) => type.valuationMode == ValuationMode.flat,
    )) {
      await _tap(tester, find.byType(DropdownSelector<AssetType>));
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

  testWidgets('asset notes and inputs survive collapsing and type changes', (
    WidgetTester tester,
  ) async {
    await open(tester, const AssetEditScreen(portfolioId: 1, assetId: 0));
    await _toggleNotes(tester);
    await tester.enterText(_notesInput, 'Keep this note');
    await _toggleNotes(tester);
    await tester.scrollUntilVisible(
      find.byType(DropdownSelector<AssetType>),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    tester
        .widget<DropdownSelector<AssetType>>(
          find.byType(DropdownSelector<AssetType>),
        )
        .onSelected(AssetType.cash);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: _field('Name'), matching: find.byType(TextField)),
      'Savings',
    );
    await tester.enterText(
      find.descendant(of: _field('Value'), matching: find.byType(TextField)),
      '123',
    );
    await _toggleNotes(tester);
    expect(
      tester.widget<TextField>(_notesInput).controller?.text,
      'Keep this note',
    );
    await _toggleNotes(tester);
    await _tap(tester, find.byType(CurrencySelector));
    await tester.tap(find.text('EUR — Euro'));
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(container.assetRepository.saved?.name, 'Savings');
    expect(container.assetRepository.saved?.manualValue, 123);
    expect(container.assetRepository.saved?.notes, 'Keep this note');
    expect(container.assetRepository.saved?.currency, 'EUR');
  });

  testWidgets(
    'existing asset notes open automatically and estimates stay live',
    (WidgetTester tester) async {
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
      expect(_notesInput, findsOneWidget);
      expect(find.text('\$20'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: _field('Price per g'),
          matching: find.byType(TextField),
        ),
        '12',
      );
      await tester.pumpAndSettle();
      expect(find.text('\$24'), findsOneWidget);
      expect(
        tester.widget<TextField>(_notesInput).controller?.text,
        'Existing asset note',
      );
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(container.assetRepository.deleted, 1);
      expect(find.byType(AssetEditScreen), findsNothing);
    },
  );

  for (final LiabilityType type in LiabilityType.values) {
    testWidgets('${type.name} retains editable notes, amount and deletion', (
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
      expect(_notesInput, findsOneWidget);
      expect(
        tester.widget<TextField>(_notesInput).controller?.text,
        'Existing note',
      );
      await _toggleNotes(tester);
      expect(find.text('Save liability'), findsNothing);
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(container.liabilityRepository.saved?.type, type);
      expect(container.liabilityRepository.saved?.amount, 500);
      expect(container.liabilityRepository.saved?.notes, 'Existing note');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(container.liabilityRepository.deleted, 1);
      expect(find.byType(LiabilityEditScreen), findsNothing);
    });
  }

  testWidgets('new liability notes are optional and currency stays editable', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
    );
    expect(_notesInput, findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
    expect(find.byType(LiabilityEditScreen), findsNothing);
    expect(container.liabilityRepository.saved, isNull);

    await open(
      tester,
      const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Give this liability a name'), findsOneWidget);
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
    await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
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
        await _toggleNotes(tester);
        expect(_notesInput, findsOneWidget);
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

      final Finder assetTypeMenuFinder = find.byType(
        PopupMenuButton<AssetType>,
      );
      final PopupMenuButton<AssetType> assetTypeMenu = tester.widget(
        assetTypeMenuFinder,
      );
      final List<IconData> assetMenuIcons = assetTypeMenu
          .itemBuilder(tester.element(assetTypeMenuFinder))
          .whereType<PopupMenuItem<AssetType>>()
          .map(
            (PopupMenuItem<AssetType> item) =>
                (item.child! as Row).children.whereType<Icon>().single.icon!,
          )
          .toList();
      expect(assetMenuIcons, AssetType.values.map(assetTypeIcon).toList());
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

      final Finder liabilityTypeMenuFinder = find.byType(
        PopupMenuButton<LiabilityType>,
      );
      final PopupMenuButton<LiabilityType> liabilityTypeMenu = tester.widget(
        liabilityTypeMenuFinder,
      );
      final List<IconData> liabilityMenuIcons = liabilityTypeMenu
          .itemBuilder(tester.element(liabilityTypeMenuFinder))
          .whereType<PopupMenuItem<LiabilityType>>()
          .map(
            (PopupMenuItem<LiabilityType> item) =>
                (item.child! as Row).children.whereType<Icon>().single.icon!,
          )
          .toList();
      expect(
        liabilityMenuIcons,
        LiabilityType.values.map(liabilityTypeIcon).toList(),
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
