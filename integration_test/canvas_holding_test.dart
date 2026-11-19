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
    await capture(tester, 'canvas-details');
    await tap(tester, find.text('Edit asset'));
    expect(
      find.byKey(const ValueKey<String>('selected-market-holding')),
      findsOneWidget,
    );
    await enter(tester, 'Quantity', '3');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
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
    await tap(tester, find.text('New liability'));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    await enter(tester, 'Outstanding amount', '250.75');
    await enter(tester, 'Name', 'Example loan');
    await capture(tester, 'canvas-liability-editor');
    await tap(tester, find.byTooltip('Back'));
    expect(find.text('Discard changes?'), findsOneWidget);
    await tap(tester, find.text('Keep editing'));
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    final LiabilityEntity added = (await tester.runAsync(
      () => container.liabilityRepository.getForPortfolio(portfolioId),
    ))!.singleWhere((liability) => liability.name == 'Example loan');
    liabilities.add(added.id);
    expect(added.amount, 250.75);
    await tap(tester, find.text('Loan'));
    expect(find.text(CurrencyUtil.format(250.75, 'USD')), findsWidgets);
    await tap(tester, find.text('Example loan'));
    await tap(tester, find.text('Delete'));
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
