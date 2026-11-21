import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_language.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/components/holding_editor_chrome.dart';

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is LabeledTextField && widget.label == label,
);

Future<void> visible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await visible(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  await visible(tester, field(label));
  final input = find.descendant(
    of: field(label),
    matching: find.byType(TextField),
  );
  // Reattach the native input client when editing the same field after unfocus.
  await tester.tap(input);
  await tester.pumpAndSettle();
  await tester.enterText(input, value);
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(input).controller!.text, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(input).controller!.text, value);
}

Finder get saveButton => find.descendant(
  of: find.byType(HoldingEditorFooter),
  matching: find.byType(FilledButton),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final screenshots = <Map<String, Object>>[];
  binding.reportData = {'screenshots': screenshots};

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final RenderRepaintBoundary boundary = tester.renderObject(
      find.byKey(const ValueKey('valuables-evidence')),
    );
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('Valuables screenshot encoding failed');
      }
      screenshots.add({
        'screenshotName': name,
        'bytes': bytes.buffer.asUint8List(),
      });
    } finally {
      image.dispose();
    }
  }

  testWidgets('Valuables save and reopen manual rates and totals on Android', (
    tester,
  ) async {
    late AppContainer container;
    late AppSettings originalSettings;
    late int portfolioId;
    late List<Map<String, Object?>> originalAssets;
    await tester.runAsync(() async {
      container = await AppContainer.create();
      originalSettings = container.settingsRepository.current;
      originalAssets = await container.database.db.query(
        'assets',
        orderBy: 'id',
      );
      expect(
        (await container.database.db.rawQuery('PRAGMA user_version'))
            .single
            .values
            .single,
        5,
      );
      await container.settingsRepository.setBaseCurrency('USD');
      await container.settingsRepository.setLanguage(AppLanguage.english);
      await container.settingsRepository.setHideBalances(false);
      await container.settingsRepository.setAppearanceMode(AppThemeMode.dark);
      portfolioId = await container.portfolioRepository.create(
        'Valuables verification',
      );
      await container.settingsRepository.setSelectedPortfolioId(portfolioId);
    });
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('valuables-evidence'),
          child: AppScope(container: container, child: const app.OkanzoApp()),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> addItem(String item, {String? purity}) async {
        await tap(tester, find.text('Add holding'));
        await tap(tester, find.text('An asset'));
        await tap(tester, find.byType(DropdownSelector<AssetType>));
        await tap(tester, find.widgetWithText(ListTile, 'Valuables'));
        expect(
          find.widgetWithText(AlertDialog, 'Choose a precious item'),
          findsOneWidget,
        );
        await tap(tester, find.widgetWithText(ListTile, item));
        if (purity != null) {
          expect(
            find.text(item == 'Gold' ? 'Choose karat' : 'Choose fineness'),
            findsWidgets,
          );
          await tap(tester, find.widgetWithText(ListTile, purity));
        } else {
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('Purity'), findsNothing);
        }
      }

      Future<AssetEntity> stored(String name) async => (await tester.runAsync(
        () => container.assetRepository.getForPortfolio(portfolioId),
      ))!.singleWhere((asset) => asset.name == name);

      Future<void> saveAndReturn() async {
        await tap(tester, saveButton);
        final back = find.byKey(const ValueKey('back-to-portfolio'));
        for (
          var attempt = 0;
          attempt < 100 && back.evaluate().isEmpty;
          attempt++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (back.evaluate().isEmpty) {
          await capture(tester, 'valuables-save-transition-failure');
        }
        expect(
          back,
          findsOneWidget,
          reason: 'Save confirmation did not appear',
        );
        await tap(tester, back);
      }

      await addItem('Gold', purity: '22K');
      await enter(tester, 'Name', 'Emulator gold');
      await enter(tester, 'Weight (grams)', '2.5');
      await enter(tester, 'Price per gram', '80.25');
      await capture(tester, 'valuables-by-weight');
      await tap(tester, find.text('Total value'));
      expect(field('Weight (grams)'), findsNothing);
      expect(field('Price per gram'), findsNothing);
      await enter(tester, 'Total value', '600.5');
      await capture(tester, 'valuables-total-value');
      await saveAndReturn();
      final totalGold = await stored('Emulator gold');
      expect(totalGold.value, 600.5);
      expect(totalGold.useTotalValue, isTrue);
      expect(totalGold.pricePerUnit, 80.25);
      expect(totalGold.quantity, 2.5);

      await tap(tester, find.text('Valuables'));
      await tap(tester, find.text('Emulator gold'));
      await tap(tester, find.text('Edit asset'));
      await tap(tester, find.text('By weight'));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('Price per gram'),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '80.25',
      );
      await enter(tester, 'Price per gram', '1e3');
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      await enter(tester, 'Price per gram', '81.75');
      await saveAndReturn();
      final customGold = await stored('Emulator gold');
      expect(customGold.customPrice, isTrue);
      expect(customGold.useTotalValue, isFalse);
      expect(customGold.value, 204.375);
      final refresh = await tester.runAsync(
        () => container.assetRepository.refreshAllPrices(portfolioId),
      );
      expect(refresh!.total, 0);
      expect((await stored('Emulator gold')).value, 204.375);

      await addItem('Jewellery');
      expect(field('Weight (grams)'), findsNothing);
      await enter(tester, 'Name', 'Emulator ring');
      await enter(tester, 'Total value', '500.75');
      await saveAndReturn();
      expect((await stored('Emulator ring')).value, 500.75);

      await addItem('Diamond');
      await enter(tester, 'Name', 'Emulator diamond');
      await enter(tester, 'Total value', '1250.25');
      await saveAndReturn();
      expect((await stored('Emulator diamond')).value, 1250.25);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect(await container.portfolioRepository.delete(portfolioId), isTrue);
        expect(
          await container.database.db.query('assets', orderBy: 'id'),
          originalAssets,
        );
        await container.settingsRepository.setBaseCurrency(
          originalSettings.baseCurrency,
        );
        await container.settingsRepository.setLanguage(
          originalSettings.language,
        );
        await container.settingsRepository.setHideBalances(
          originalSettings.hideBalances,
        );
        await container.settingsRepository.setAppearanceMode(
          originalSettings.appearanceMode,
        );
        await container.settingsRepository.setSelectedPortfolioId(
          originalSettings.selectedPortfolioId,
        );
        await container.database.close();
        container.settingsRepository.dispose();
      });
    }
  });
}
