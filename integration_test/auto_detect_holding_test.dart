import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_language.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/holding_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/components/holding_editor_chrome.dart';
import 'package:okanzo/ui/components/holding_saved_summary_screen.dart';
import 'package:okanzo/ui/holding/holding_create_screen.dart';
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/util/screenshot_protection.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bool _captureScreenshots = bool.fromEnvironment('CAPTURE_SCREENSHOTS');

Finder _field(String label) => find.byWidgetPredicate(
  (Widget widget) => widget is LabeledTextField && widget.label == label,
);

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

Future<void> _enterVisible(
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

Finder get _saveButton => find.descendant(
  of: find.byType(HoldingEditorFooter),
  matching: find.byType(FilledButton),
);

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

Future<void> _restore(
  SharedPreferences preferences,
  Map<String, Object?> original,
) async {
  for (final MapEntry<String, Object?> entry in original.entries) {
    switch (entry.value) {
      case null:
        await preferences.remove(entry.key);
      case final bool value:
        await preferences.setBool(entry.key, value);
      case final int value:
        await preferences.setInt(entry.key, value);
      case final String value:
        await preferences.setString(entry.key, value);
      case final List<String> value:
        await preferences.setStringList(entry.key, value);
      default:
        throw StateError('Unexpected preference type: ${entry.key}');
    }
  }
  await preferences.reload();
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'unified entry creation automatically detects Assets and Liabilities by type',
    (WidgetTester tester) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, Object?> original = <String, Object?>{
        for (final String key in <String>[
          'app_theme',
          'theme_mode',
          'app_language',
          'dynamic_color',
          'base_currency',
          'hide_balances',
          'simple_net_worth',
          'block_screenshots',
          'last_seen_version',
          'preferred_stock_exchanges',
        ])
          key: prefs.get(key),
      };

      AppContainer? container;
      int? portfolioId;
      try {
        final SettingsRepository setup = SettingsRepository(prefs);
        try {
          await setup.setAppearanceMode(AppThemeMode.dark);
          await setup.setLanguage(AppLanguage.english);
          await setup.setDynamicColor(false);
          await setup.setBaseCurrency('USD');
          await setup.setHideBalances(false);
          await setup.setSimpleNetWorth(false);
          if (_captureScreenshots) {
            await setup.setBlockScreenshots(false);
          }
          await setup.setLastSeenVersion(AppReleaseNotes.currentVersion);
          await setup.setPreferredExchanges(<StockExchange>[StockExchange.us]);
        } finally {
          await setup.dispose();
        }
        if (_captureScreenshots) {
          await ScreenshotProtection.setEnabled(false);
        }

        await app.main();
        await _wait(
          tester,
          () => find.byType(HomeScreen).evaluate().isNotEmpty,
          'HomeScreen startup',
        );
        if (_captureScreenshots) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pumpAndSettle();
        }

        container = AppScope.of(tester.element(find.byType(app.OkanzoApp)));
        portfolioId = await container.portfolioRepository.create(
          _captureScreenshots
              ? 'Sample portfolio'
              : 'Auto-detect ${DateTime.now().millisecondsSinceEpoch}',
        );
        await container.settingsRepository.setSelectedPortfolioId(portfolioId);
        await container.assetRepository.save(
          AssetEntity(
            portfolioId: portfolioId,
            type: AssetType.cash,
            name: 'Emergency reserve',
            currency: 'USD',
            manualValue: 12400,
            createdAt: 0,
            updatedAt: 0,
          ),
        );
        await container.liabilityRepository.save(
          LiabilityEntity(
            portfolioId: portfolioId,
            type: LiabilityType.loan,
            name: 'Auto loan',
            currency: 'USD',
            amount: 3200,
            createdAt: 0,
            updatedAt: 0,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Tap "Add holding" directly from the Assets tab -> opens unified
        // New entry with Asset automatically detected.
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
        if (_captureScreenshots) {
          await binding.takeScreenshot('after-01-unified-new-entry-asset');
        }

        // 2. Open the unified type picker -> shows grouped Assets and Liabilities.
        await _tapVisible(
          tester,
          find.byKey(const ValueKey<String>('holding-type-chip')),
        );
        expect(find.text('Choose type'), findsOneWidget);
        expect(
          find.text('Asset or liability is detected automatically'),
          findsOneWidget,
        );
        final Finder creditCardRow = find.byKey(
          const ValueKey<HoldingType>(
            HoldingType.liability(LiabilityType.creditCard),
          ),
        );
        if (creditCardRow.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            creditCardRow,
            120,
            scrollable: find.descendant(
              of: find.byKey(const ValueKey<String>('holding-type-list')),
              matching: find.byType(Scrollable),
            ),
          );
        }
        await tester.pumpAndSettle();
        if (_captureScreenshots) {
          await binding.takeScreenshot('after-02-grouped-choose-type-sheet');
        }

        // 3. Select Credit card -> automatically switches to Liability.
        await tester.tap(creditCardRow);
        await tester.pumpAndSettle();
        expect(find.text('Liability'), findsOneWidget);
        expect(find.text('Subtracted from net worth'), findsOneWidget);
        expect(_field('Outstanding amount'), findsOneWidget);

        await _enterVisible(tester, 'Outstanding amount', '1450');
        await _enterVisible(tester, 'Name', 'Sapphire card');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        if (_captureScreenshots) {
          await binding.takeScreenshot('after-03-auto-detected-liability');
        }

        // 4. Save -> persists liability, opens summary, and switches Home to
        // the Liabilities tab automatically.
        await tester.tap(_saveButton);
        await _wait(
          tester,
          () => find.byType(HoldingSavedSummaryScreen).evaluate().isNotEmpty,
          'credit card saved summary',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('back-to-portfolio')),
        );
        await _wait(
          tester,
          () => find.byType(HomeScreen).evaluate().isNotEmpty,
          'saved credit card liability on Home',
        );
        expect(find.text('Credit card'), findsOneWidget);
        expect(find.text(r'$7,750'), findsOneWidget);
        if (_captureScreenshots) {
          await binding.takeScreenshot('after-04-saved-on-home-liabilities');
        }

        // 5. From the Liabilities tab, tap "Add holding" -> starts at Loan
        // (Liability), then switch to Other asset -> auto-detects Asset and
        // switches Home to Assets!
        await tester.tap(find.byKey(const ValueKey<String>('add-holding')));
        await tester.pumpAndSettle();
        expect(find.text('Liability'), findsOneWidget);
        expect(find.text('Subtracted from net worth'), findsOneWidget);

        await _tapVisible(
          tester,
          find.byKey(const ValueKey<String>('holding-type-chip')),
        );
        final Finder otherAssetRow = find.byKey(
          const ValueKey<HoldingType>(HoldingType.asset(AssetType.other)),
        );
        await _tapVisible(
          tester,
          otherAssetRow,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey<String>('holding-type-list')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Asset'), findsOneWidget);
        expect(find.text('Added to net worth'), findsOneWidget);
        expect(find.text('Other asset'), findsOneWidget);

        await _enterVisible(tester, 'Value', '800');
        await _enterVisible(tester, 'Name', 'Vintage watch');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(_saveButton);
        await _wait(
          tester,
          () => find.byType(HoldingSavedSummaryScreen).evaluate().isNotEmpty,
          'other asset saved summary',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('back-to-portfolio')),
        );
        await _wait(
          tester,
          () => find.byType(HomeScreen).evaluate().isNotEmpty,
          'saved other asset on Home',
        );
        expect(find.text('Other'), findsOneWidget);
        expect(find.text(r'$8,550'), findsOneWidget);
      } finally {
        if (portfolioId != null && container != null) {
          await container.portfolioRepository.delete(portfolioId);
        }
        await _restore(prefs, original);
        await ScreenshotProtection.setEnabled(
          (original['block_screenshots'] as bool?) ?? true,
        );
      }
    },
  );
}
