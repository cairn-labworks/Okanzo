import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/components/holding_editor_chrome.dart';
import 'package:okanzo/ui/components/holding_saved_summary_screen.dart';
import 'package:okanzo/util/currency_util.dart';
import 'package:okanzo/util/screenshot_protection.dart';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  if (label == 'Company or Ticker' || label == 'Coin or ticker') {
    final Finder trigger = find.byWidgetPredicate(
      (Widget widget) =>
          widget.key == const ValueKey<String>('market-search-trigger') ||
          widget.key == const ValueKey<String>('selected-market-holding'),
    );
    await tap(tester, trigger);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      value,
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    return;
  }
  final Finder field = find.byWidgetPredicate(
    (widget) => widget is LabeledTextField && widget.label == label,
  );
  await tester.ensureVisible(field);
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(TextField)),
    value,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final List<Map<String, Object>> screenshots = <Map<String, Object>>[];
  binding.reportData = <String, Object>{'screenshots': screenshots};

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final RenderRepaintBoundary boundary = tester.renderObject(
      find.byKey(const ValueKey<String>('canvas-evidence')),
    );
    final ui.Image image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Canvas screenshot encoding failed');
      screenshots.add(<String, Object>{
        'screenshotName': name,
        'bytes': bytes.buffer.asUint8List(),
      });
    } finally {
      image.dispose();
    }
  }

  testWidgets('approved Canvas holding journeys on Android', (tester) async {
    late AppContainer container;
    late int portfolioId;
    final List<int> assets = <int>[];
    final List<int> liabilities = <int>[];
    await tester.runAsync(() async {
      container = await AppContainer.create();
      await container.settingsRepository.setBaseCurrency('USD');
      await container.settingsRepository.setAppearanceMode(AppThemeMode.dark);
      await container.settingsRepository.setLastSeenVersion(
        AppReleaseNotes.currentVersion,
      );
      await ScreenshotProtection.setEnabled(false);
      portfolioId = await container.portfolioRepository.create('Canvas demo');
      await container.settingsRepository.setSelectedPortfolioId(portfolioId);
      for (final (String name, String ticker, double price) holding
          in <(String, String, double)>[
            ('Apple', 'AAPL', 125.75),
            ('Microsoft', 'MSFT', 250.25),
          ]) {
        assets.add(
          await container.assetRepository.save(
            AssetEntity(
              portfolioId: portfolioId,
              type: AssetType.stock,
              name: holding.$1,
              symbol: holding.$2,
              quantity: 2,
              lastPrice: holding.$3,
              currency: 'USD',
              createdAt: 0,
              updatedAt: 0,
            ),
          ),
        );
      }
      assets.add(
        await container.assetRepository.save(
          AssetEntity(
            portfolioId: portfolioId,
            type: AssetType.cash,
            name: 'Emergency fund',
            manualValue: 5000.25,
            currency: 'USD',
            createdAt: 0,
            updatedAt: 0,
          ),
        ),
      );
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey<String>('canvas-evidence'),
        child: AppScope(container: container, child: const app.OkanzoApp()),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'canvas-home');
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Portfolios'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    await tap(tester, find.text('Stock'));
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Microsoft'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    await tap(tester, find.byTooltip('Sort or arrange'));
    await tap(tester, find.text('Name / Z to A'));
    expect(
      tester.getTopLeft(find.text('Microsoft')).dy,
      lessThan(tester.getTopLeft(find.text('Apple')).dy),
    );
    await capture(tester, 'canvas-holdings');
    await tap(tester, find.text('Microsoft'));
    expect(find.text('ASSET / STOCK'), findsOneWidget);
    await capture(tester, 'canvas-details');
    await tap(tester, find.text('Edit asset'));
    expect(
      find.byKey(const ValueKey<String>('selected-market-holding')),
      findsOneWidget,
    );
    await capture(tester, 'canvas-selected-market-editor');
    await enter(tester, 'Quantity', '3');
    await tap(
      tester,
      find.descendant(
        of: find.byType(HoldingEditorFooter),
        matching: find.byType(FilledButton),
      ),
    );
    expect(find.byType(HoldingSavedSummaryScreen), findsOneWidget);
    expect(find.text('Asset updated.'), findsOneWidget);
    expect(find.byType(HoldingEditorFooter), findsNothing);
    expect(find.byKey(const ValueKey<String>('add-holding')), findsOneWidget);
    final Rect summaryBounds = tester.getRect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(summaryBounds.width, lessThan(screen.width));
    expect(summaryBounds.height, lessThan(screen.height));
    expect(summaryBounds.center.dx, closeTo(screen.width / 2, 1));
    expect(summaryBounds.center.dy, closeTo(screen.height / 2, 24));
    await capture(tester, 'canvas-saved-summary');
    await tap(tester, find.byKey(const ValueKey<String>('back-to-portfolio')));
    expect(
      (await tester.runAsync(
        () => container.assetRepository.getById(assets[1]),
      ))!.quantity,
      3,
    );

    final ScrollableState scroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final double offset = scroll.position.pixels;
    await tap(tester, find.byKey(const ValueKey<String>('add-holding')));
    expect(scroll.position.pixels, offset);
    expect(find.byType(BackdropFilter), findsOneWidget);
    await capture(tester, 'canvas-add-expanded');
    await tap(tester, find.text('An asset'));
    await enter(tester, 'Company or Ticker', 'AAPL');
    await enter(tester, 'Quantity', '2');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('custom-name-toggle')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byType(OptionalCustomNameField),
        matching: find.byIcon(Icons.edit_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(HoldingEditorFooter),
        matching: find.byType(HoldingPortfolioLabel),
      ),
      findsNothing,
    );
    await capture(tester, 'canvas-add-asset-market');
    await tap(tester, find.byType(DropdownSelector<AssetType>));
    await tap(tester, find.text('Cash').last);
    await enter(tester, 'Value', '10000.25');
    await enter(tester, 'Name', 'Travel fund');
    await capture(tester, 'canvas-add-asset');
    await tap(
      tester,
      find.descendant(
        of: find.byType(HoldingEditorFooter),
        matching: find.byType(FilledButton),
      ),
    );
    expect(find.text('Asset added.'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey<String>('back-to-portfolio')));
    final AssetEntity cash = (await tester.runAsync(
      () => container.assetRepository.getForPortfolio(portfolioId),
    ))!.singleWhere((asset) => asset.name == 'Travel fund');
    assets.add(cash.id);
    expect(cash.manualValue, 10000.25);
    await tap(tester, find.byKey(const ValueKey<String>('add-holding')));
    await tap(tester, find.text('A liability'));
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byType(HoldingEditorFooter),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await enter(tester, 'Outstanding amount', '250.75');
    await enter(tester, 'Name', 'Example loan');
    await capture(tester, 'canvas-liability-editor');
    await tap(tester, find.byTooltip('Back'));
    expect(find.text('Discard changes?'), findsOneWidget);
    await tap(tester, find.text('Keep editing'));
    await tap(
      tester,
      find.descendant(
        of: find.byType(HoldingEditorFooter),
        matching: find.byType(FilledButton),
      ),
    );
    expect(find.text('Liability added.'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey<String>('back-to-portfolio')));
    final LiabilityEntity added = (await tester.runAsync(
      () => container.liabilityRepository.getForPortfolio(portfolioId),
    ))!.singleWhere((liability) => liability.name == 'Example loan');
    liabilities.add(added.id);
    expect(added.amount, 250.75);
    await tap(tester, find.text('Loan'));
    expect(find.text(CurrencyUtil.format(250.75, 'USD')), findsWidgets);
    await tap(tester, find.text('Example loan'));
    expect(find.text('LIABILITY / LOAN'), findsOneWidget);
    await tap(tester, find.text('Delete liability'));
    await capture(tester, 'canvas-delete-confirmation');
    expect(
      await tester.runAsync(
        () => container.liabilityRepository.getById(added.id),
      ),
      isNotNull,
    );
    await tap(tester, find.text('Cancel'));
    expect(
      await tester.runAsync(
        () => container.liabilityRepository.getById(added.id),
      ),
      isNotNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final int id in assets) {
        await container.assetRepository.delete(id);
      }
      for (final int id in liabilities) {
        await container.liabilityRepository.delete(id);
      }
      await container.portfolioRepository.delete(portfolioId);
    });
  });
}
