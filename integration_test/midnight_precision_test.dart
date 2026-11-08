import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_language.dart';
import 'package:okanzo/domain/model/app_theme.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/components/ui_components.dart';
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/home/net_worth_card.dart';
import 'package:okanzo/ui/settings/settings_screen.dart';
import 'package:okanzo/util/currency_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final Stopwatch timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed > const Duration(seconds: 45)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: description);
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await _wait(
    tester,
    () => target.hitTestable().evaluate().isNotEmpty,
    'tap target',
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _back(WidgetTester tester) =>
    _tap(tester, find.byIcon(Icons.arrow_back));

Future<void> _dragBefore(
  WidgetTester tester,
  String moving,
  String target,
) async {
  await Scrollable.ensureVisible(
    tester.element(find.text(moving)),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
  final Rect targetBounds = tester.getRect(find.text(target));
  final Offset destination =
      targetBounds.center + Offset(0, targetBounds.height / 4);
  final gesture = await tester.startGesture(
    tester.getCenter(find.text(moving)),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(destination);
  await tester.pump(const Duration(milliseconds: 500));
  await gesture.up();
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (Widget widget) => widget is LabeledTextField && widget.label == label,
);

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final Finder target = _field(label);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.enterText(
    find.descendant(of: target, matching: find.byType(TextField)),
    value,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void _headingBelowNavigation(WidgetTester tester) {
  expect(find.byType(PageHeading), findsOneWidget);
  expect(
    tester.getRect(find.byType(PageHeading)).top,
    greaterThan(tester.getRect(find.byIcon(Icons.arrow_back)).bottom),
  );
  expect(tester.widget<AppBar>(find.byType(AppBar)).title, isNull);
}

Future<void> _saveBelowNotes(WidgetTester tester, String label) async {
  final Finder button = find.widgetWithText(FilledButton, label);
  await tester.scrollUntilVisible(
    button,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(
    tester.getRect(button).top,
    greaterThanOrEqualTo(
      tester.getRect(find.byType(OptionalNotesField)).bottom,
    ),
  );
  expect(button.hitTestable(), findsOneWidget);
}

Future<void> _restore(
  SharedPreferences preferences,
  Map<String, Object?> original,
) async {
  for (final MapEntry<String, Object?> entry in original.entries) {
    final bool saved = switch (entry.value) {
      null => await preferences.remove(entry.key),
      final bool value => await preferences.setBool(entry.key, value),
      final int value => await preferences.setInt(entry.key, value),
      final String value => await preferences.setString(entry.key, value),
      final List<String> value => await preferences.setStringList(
        entry.key,
        value,
      ),
      _ => throw StateError('Unexpected preference type: ${entry.key}'),
    };
    expect(saved, isTrue, reason: entry.key);
  }
  await preferences.reload();
  for (final MapEntry<String, Object?> entry in original.entries) {
    expect(preferences.get(entry.key), entry.value, reason: entry.key);
  }
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Midnight precision matches the selected layout on device', (
    tester,
  ) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final SettingsRepository selection = SettingsRepository(preferences);
    try {
      await selection.setAppTheme(AppTheme.midnight);
      expect(selection.current.appTheme, AppTheme.midnight);
    } finally {
      await selection.dispose();
    }

    final Map<String, Object?> original = <String, Object?>{
      for (final String key in <String>[
        'app_theme',
        'theme_mode',
        'app_language',
        'dynamic_color',
        'base_currency',
        'hide_balances',
        'simple_net_worth',
        'selected_portfolio_id',
        'last_seen_version',
        'preferred_stock_exchanges',
      ])
        key: preferences.get(key),
    };
    final List<String> checks = <String>[];
    final Map<String, Object?> report = <String, Object?>{
      'checks': checks,
      'preferencesRestored': false,
      'testDataRemoved': false,
      'selectedTheme': 'MIDNIGHT',
    };
    binding.reportData = report;
    void passed(String description) {
      checks.add(description);
      debugPrint('MIDNIGHT FIDELITY PASS: $description');
    }

    AppContainer? container;
    int? portfolioId;
    try {
      final SettingsRepository settings = SettingsRepository(preferences);
      try {
        await settings.setLanguage(AppLanguage.english);
        await settings.setDynamicColor(false);
        await settings.setBaseCurrency('USD');
        await settings.setHideBalances(true);
        await settings.setSimpleNetWorth(false);
        await settings.setLastSeenVersion(AppReleaseNotes.currentVersion);
        await settings.setPreferredExchanges(<StockExchange>[StockExchange.us]);
      } finally {
        await settings.dispose();
      }
      await app.main();
      await _wait(
        tester,
        () => find.byType(app.OkanzoApp).evaluate().isNotEmpty,
        'startup',
      );
      container = AppScope.of(tester.element(find.byType(app.OkanzoApp)));
      await _wait(
        tester,
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
        'unlocked home',
      );
      final theme = Theme.of(tester.element(find.byType(HomeScreen)));
      expect(theme.colorScheme.surface, const Color(0xFF172220));
      expect(theme.colorScheme.primary, const Color(0xFFC1E1BD));
      expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF88A196));
      expect(
        find.descendant(
          of: find.byType(NetWorthCard),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('net-worth-headline')),
            )
            .style
            ?.fontSize,
        42,
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
      passed('selected Midnight palette is active on the real device');

      await _tap(tester, find.byTooltip('Settings'));
      expect(find.byType(SettingsScreen), findsOneWidget);
      _headingBelowNavigation(tester);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(5));
      expect(find.text('Language, theme & colour'), findsOneWidget);
      expect(
        find.text('Private by design. Stored on your device.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Appearance'));
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Language, theme & colour'), findsNothing);
      expect(find.text('App theme'), findsNothing);
      expect(find.text('Light / dark'), findsNothing);
      await _tap(tester, find.text('Theme'));
      await _tap(
        tester,
        find.byKey(const ValueKey<AppThemeMode>(AppThemeMode.light)),
      );
      expect(
        Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
        Brightness.light,
      );
      await _tap(tester, find.text('Theme'));
      await _tap(
        tester,
        find.byKey(const ValueKey<AppThemeMode>(AppThemeMode.system)),
      );
      expect(
        container.settingsRepository.current.appearanceMode,
        AppThemeMode.system,
      );
      await _tap(tester, find.text('Theme'));
      await _tap(
        tester,
        find.byKey(const ValueKey<AppThemeMode>(AppThemeMode.dark)),
      );
      expect(
        Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
        Brightness.dark,
      );
      expect(container.settingsRepository.current.appTheme, AppTheme.midnight);
      passed('one Theme selector persists Light, System and Midnight Dark');
      await _back(tester);
      expect(find.text('Language, theme & colour'), findsOneWidget);
      await _back(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      passed(
        'descriptive category list drills in; Back returns to categories then home',
      );

      portfolioId = await container.portfolioRepository.create(
        'Midnight UI ${DateTime.now().millisecondsSinceEpoch}',
      );
      for (final String section in <String>['asset', 'liability']) {
        final key = 'cat_order_${section}_$portfolioId';
        original[key] = preferences.get(key);
      }
      await container.settingsRepository.setSelectedPortfolioId(portfolioId);
      await container.settingsRepository.setHideBalances(false);
      final int assetId = await container.assetRepository.save(
        AssetEntity(
          portfolioId: portfolioId,
          type: AssetType.stock,
          name: 'Midnight test shares',
          currency: 'USD',
          quantity: 12,
          symbol: 'AAPL',
          lastPrice: 322,
          createdAt: 0,
          updatedAt: 0,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Stock'));
      await _tap(tester, find.text('Midnight test shares'));
      _headingBelowNavigation(tester);
      expect(find.byType(PickerChip), findsNWidgets(3));
      expect(find.text('US exchange'), findsOneWidget);
      final List<Rect> chips = find
          .byType(PickerChip)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .toList();
      expect(chips[0].top, chips[1].top);
      expect(chips[1].top, chips[2].top);
      expect(find.byType(DropdownMenu<AssetType>), findsNothing);
      expect(
        tester.getRect(_field('Ticker symbol')).top,
        tester.getRect(_field('Quantity')).top,
      );
      final Text amount = tester.widget<Text>(
        find.text(CurrencyUtil.format(3864, 'USD')),
      );
      expect(amount.style?.fontSize, 38);
      expect(amount.style?.fontWeight, FontWeight.w500);
      final Scaffold editor = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(AssetEditScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(editor.bottomNavigationBar, isNull);
      await _saveBelowNotes(tester, 'Save asset');
      passed(
        'amount-led form has three inline chips, paired fields and Save beneath notes',
      );
      await _enter(tester, 'Quantity', '13');
      await _tap(tester, find.text('Save asset'));
      await _wait(
        tester,
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
        'asset saved',
      );
      expect((await container.assetRepository.getById(assetId))?.quantity, 13);
      passed(
        'the new compact form still persists asset edits in the encrypted database',
      );

      await _tap(tester, find.text('Add'));
      await _tap(tester, find.text('New liability'));
      _headingBelowNavigation(tester);
      expect(find.byType(PickerChip), findsNWidgets(2));
      await _enter(tester, 'Outstanding amount', '4200');
      await _enter(tester, 'Name', 'Midnight test loan');
      await _saveBelowNotes(tester, 'Save liability');
      await _tap(tester, find.text('Save liability'));
      await _wait(
        tester,
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
        'liability saved',
      );
      expect(
        (await container.liabilityRepository.getForPortfolio(portfolioId))
            .single
            .amount,
        4200,
      );
      passed(
        'liability page uses the same heading, chips and inline Save layout',
      );
      await container.assetRepository.save(
        AssetEntity(
          portfolioId: portfolioId,
          type: AssetType.cash,
          name: 'Midnight test cash',
          currency: 'USD',
          manualValue: 1234567,
          createdAt: 0,
          updatedAt: 0,
        ),
      );
      final int secondCashId = await container.assetRepository.save(
        AssetEntity(
          portfolioId: portfolioId,
          type: AssetType.cash,
          name: 'Midnight secondary cash',
          currency: 'USD',
          manualValue: 1000,
          createdAt: 0,
          updatedAt: 0,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey<String>('home-assets-tab')));
      expect(
        find.byKey(const ValueKey<String>('home-category-panel')),
        findsOneWidget,
      );
      await _tap(tester, find.text('Cash'));
      final Set<String> amountRowLabels = <String>{
        'Expand',
        'Collapse',
        'Drag to reorder',
      };
      double? rightEdge;
      for (final bool assets in <bool>[true, false]) {
        await _tap(
          tester,
          find.byKey(
            ValueKey<String>(
              assets ? 'home-assets-tab' : 'home-liabilities-tab',
            ),
          ),
        );
        final rows = tester.widgetList<Row>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Row &&
                widget.children.whereType<Icon>().any(
                  (icon) => amountRowLabels.contains(icon.semanticLabel),
                ),
          ),
        );
        for (final Row row in rows) {
          final Text amount = row.children
              .whereType<Flexible>()
              .map((child) => child.child)
              .whereType<Text>()
              .single;
          final double edge = tester.getRect(find.byWidget(amount)).right;
          rightEdge ??= edge;
          expect(edge, closeTo(rightEdge, 0.01));
        }
      }
      expect(rightEdge, isNotNull);
      passed(
        'short and long asset/liability totals and expanded holdings share a right edge',
      );
      await _tap(tester, find.byKey(const ValueKey<String>('home-assets-tab')));
      expect(find.text('Midnight test cash'), findsOneWidget);
      await _dragBefore(
        tester,
        'Midnight secondary cash',
        'Midnight test cash',
      );
      await _wait(
        tester,
        () =>
            tester.getRect(find.text('Midnight secondary cash')).top <
            tester.getRect(find.text('Midnight test cash')).top,
        'reordered cash rows',
      );
      final cashItems = (await container.assetRepository.getForPortfolio(
        portfolioId,
      )).where((item) => item.type == AssetType.cash).toList();
      cashItems.sort(
        (first, second) => first.position.compareTo(second.position),
      );
      expect(cashItems.first.id, secondCashId);
      await _dragBefore(tester, 'Cash', 'Stock');
      await _wait(
        tester,
        () =>
            tester.getRect(find.text('Cash')).top <
            tester.getRect(find.text('Stock')).top,
        'reordered categories',
      );
      expect(
        preferences.getString('cat_order_asset_$portfolioId'),
        'CASH,STOCK',
      );
      passed('Quiet overview retains category and holding drag ordering');

      await container.settingsRepository.setLanguage(AppLanguage.arabic);
      const AppLocalizations strings = AppLocalizations(Locale('ar'));
      await tester.pumpWidget(
        AppScope(
          container: container,
          child: MediaQuery(
            data: MediaQueryData.fromView(tester.view)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: const app.OkanzoApp(),
          ),
        ),
      );
      await _wait(
        tester,
        () => find.byType(HomeScreen).evaluate().isNotEmpty,
        'large RTL home',
      );
      await _tap(tester, find.byTooltip(strings.text('Settings')));
      await _tap(tester, find.text(strings.text('Appearance')));
      await _back(tester);
      expect(
        find.text(strings.text('Language, theme & colour')),
        findsOneWidget,
      );
      await _back(tester);
      await _tap(tester, find.text(strings.text('Stock')));
      await _tap(tester, find.text('Midnight test shares'));
      await tester.scrollUntilVisible(
        _field(strings.text('Quantity')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.getRect(_field(strings.text('Quantity'))).top,
        greaterThan(tester.getRect(_field(strings.text('Ticker symbol'))).top),
      );
      await _saveBelowNotes(tester, strings.text('Save asset'));
      expect(tester.takeException(), isNull);
      passed(
        '150% Arabic RTL keeps drill-in navigation and stacks paired fields safely',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      try {
        await _restore(preferences, original);
        report['preferencesRestored'] = true;
        if (portfolioId != null) {
          expect(container, isNotNull);
          expect(
            await container!.portfolioRepository.delete(portfolioId),
            isTrue,
          );
          expect(
            await container.assetRepository.getForPortfolio(portfolioId),
            isEmpty,
          );
          expect(
            await container.liabilityRepository.getForPortfolio(portfolioId),
            isEmpty,
          );
        }
        report['testDataRemoved'] = true;
      } finally {
        await container?.settingsRepository.dispose();
        await container?.database.close();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
