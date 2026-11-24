import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/data/local/entity/portfolio_entity.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/asset/stock_exchange_field.dart';
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/components/holding_saved_summary_screen.dart';
import 'package:okanzo/ui/liability/liability_edit_screen.dart';
import 'package:okanzo/ui/portfolio/portfolio_screen.dart';
import 'package:okanzo/ui/statistics/statistics_screen.dart';
import 'package:okanzo/ui/theme/theme.dart';

import 'canvas_holding_test.dart' show tap;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('portfolio, market, amount and chart regressions on Android', (
    tester,
  ) async {
    final AppContainer container = await AppContainer.create();
    final settings = container.settingsRepository;
    final String tag = 'Regression ${DateTime.now().millisecondsSinceEpoch}';
    final int portfolioId = await container.portfolioRepository.create(tag);
    final int otherId = await container.portfolioRepository.create(
      '$tag other',
    );
    final previousExchanges = settings.current.preferredExchanges;
    final bool wasHidden = settings.current.hideBalances;
    final int? previousSelection = settings.current.selectedPortfolioId;
    final String currency = settings.current.baseCurrency;
    final int cashId = await container.assetRepository.save(
      AssetEntity(
        portfolioId: portfolioId,
        type: AssetType.cash,
        name: 'Cash fixture',
        manualValue: 1000000,
        currency: currency,
        createdAt: 0,
        updatedAt: 0,
      ),
    );
    final int loanId = await container.liabilityRepository.save(
      LiabilityEntity(
        portfolioId: portfolioId,
        type: LiabilityType.loan,
        name: 'Loan fixture',
        amount: 1,
        currency: currency,
        createdAt: 0,
        updatedAt: 0,
      ),
    );

    Future<void> open(Widget screen) async {
      await tester.pumpWidget(
        AppScope(
          container: container,
          child: MaterialApp(
            key: ValueKey<Type>(screen.runtimeType),
            theme: buildTheme(brightness: Brightness.light),
            home: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> editDialogName(String value, String action) async {
      final Finder dialog = find.byType(AlertDialog);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        value,
      );
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.descendant(of: dialog, matching: find.text(action)),
      );
    }

    Future<void> waitFor(Finder finder, {bool present = true}) async {
      for (int attempt = 0; attempt < 100; attempt++) {
        if (finder.evaluate().isNotEmpty == present) return;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, present ? findsWidgets : findsNothing);
    }

    Future<void> enter(String label, String value) async {
      final Finder field = find.byWidgetPredicate(
        (widget) => widget is LabeledTextField && widget.label == label,
      );
      final Finder input = find.descendant(
        of: field,
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(input);
      await tester.tap(input);
      await tester.pumpAndSettle();
      await tester.enterText(input, value);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller?.text, value);
    }

    try {
      await settings.setHideBalances(false);
      await settings.setSelectedPortfolioId(portfolioId);
      await open(const PortfolioScreen());
      await waitFor(find.text('$tag other'));
      await tap(tester, find.widgetWithText(FloatingActionButton, 'New'));
      await editDialogName('  ${tag.toUpperCase()}  ', 'Create');
      const String duplicateError = 'Name already in use. Try another';
      await waitFor(find.text(duplicateError));
      expect(find.text('New portfolio'), findsOneWidget);
      await tap(tester, find.text('Cancel'));

      // Use the row for the second portfolio, not another portfolio's menu.
      final Finder otherRow = find.ancestor(
        of: find.text('$tag other'),
        matching: find.byType(Card),
      );
      await tap(
        tester,
        find.descendant(of: otherRow, matching: find.byTooltip('More')),
      );
      await tap(tester, find.text('Rename'));
      await editDialogName(tag.toLowerCase(), 'Save');
      await waitFor(find.text(duplicateError));
      await editDialogName('$tag renamed', 'Save');
      await waitFor(find.byType(AlertDialog), present: false);
      final PortfolioEntity? renamed = await container.portfolioRepository
          .getById(otherId);
      expect(renamed?.name, '$tag renamed');

      final Finder precisionWarning = find.text(
        'This number can’t be saved exactly. Enter fewer digits.',
      );
      final Finder saved = find.byType(HoldingSavedSummaryScreen);
      await open(AssetEditScreen(portfolioId: portfolioId, assetId: cashId));
      final Finder assetSave = find.widgetWithText(FilledButton, 'Save asset');
      for (final value in ['9999999999999999', '1000000000000000100']) {
        await enter('Value', value);
        expect(precisionWarning, findsOneWidget);
        expect(tester.widget<FilledButton>(assetSave).enabled, isFalse);
      }
      expect(
        (await container.assetRepository.getById(cashId))?.manualValue,
        1000000,
      );
      await enter('Value', '4503599627370497');
      expect(precisionWarning, findsNothing);
      expect(tester.widget<FilledButton>(assetSave).enabled, isTrue);
      await tap(tester, assetSave);
      await waitFor(saved);
      expect(
        (await container.assetRepository.getById(cashId))?.manualValue,
        4503599627370497.0,
      );

      await open(
        LiabilityEditScreen(portfolioId: portfolioId, liabilityId: loanId),
      );
      await enter('Outstanding amount', '1000000000000000100.00');
      expect(precisionWarning, findsOneWidget);
      final Finder liabilitySave = find.widgetWithText(
        FilledButton,
        'Save liability',
      );
      expect(tester.widget<FilledButton>(liabilitySave).enabled, isFalse);
      expect((await container.liabilityRepository.getById(loanId))?.amount, 1);
      await enter('Outstanding amount', '0.01');
      expect(precisionWarning, findsNothing);
      expect(tester.widget<FilledButton>(liabilitySave).enabled, isTrue);
      await tap(tester, liabilitySave);
      await waitFor(saved);
      expect(
        (await container.liabilityRepository.getById(loanId))?.amount,
        0.01,
      );

      await open(const StatisticsScreen());
      await waitFor(find.text('Overview'));
      final Finder overview = find.byType(Card).first;
      await tap(
        tester,
        find.descendant(of: overview, matching: find.text('Liabilities')),
      );
      expect(find.text('<0.001%'), findsOneWidget);

      await open(AssetEditScreen(portfolioId: portfolioId, assetId: 0));
      final Finder exchange = find.byType(StockExchangeField);
      await waitFor(exchange);
      await tap(tester, exchange);
      await tap(tester, find.text(StockExchangeField.manageLabel));
      await waitFor(find.text('Preferred exchanges'));
      final Finder checkbox = find.byKey(
        const ValueKey<StockExchange>(StockExchange.nse),
      );
      await tester.scrollUntilVisible(
        checkbox,
        160,
        scrollable: find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      if (!previousExchanges.contains(StockExchange.nse)) {
        await tap(tester, checkbox);
      }
      await tap(tester, find.text('Save'));
      await waitFor(find.byType(AlertDialog), present: false);
      expect(settings.current.preferredExchanges, contains(StockExchange.nse));
      await tap(tester, exchange);
      final Finder exchangePicker = find.byType(AlertDialog);
      await tap(
        tester,
        find.descendant(of: exchangePicker, matching: find.text('NSE (India)')),
      );
      expect(
        find.text('Adds .NS automatically (e.g. RELIANCE.NS)'),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settings.setPreferredExchanges(previousExchanges);
      await settings.setHideBalances(wasHidden);
      await settings.setSelectedPortfolioId(previousSelection);
      await container.portfolioRepository.delete(otherId);
      await container.portfolioRepository.delete(portfolioId);
    }
  });
}
