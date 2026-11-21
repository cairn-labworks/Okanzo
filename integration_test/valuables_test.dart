import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/app_database.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/data/repository/asset_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_language.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/precious_metal.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/components/holding_editor_chrome.dart';
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/asset/asset_edit_view_model.dart';
import 'package:okanzo/util/result.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sql;

class _DelayedMetalQuote extends Fake implements AssetRepository {
  _DelayedMetalQuote(this.delegate);

  final AssetRepository delegate;
  final quote = Completer<Result<double>>();

  @override
  Future<AssetEntity?> getById(int id) => delegate.getById(id);

  @override
  Future<int> save(AssetEntity asset) => delegate.save(asset);

  @override
  Future<Result<double>> fetchMetalPrice(
    PreciousMetal metal,
    String purity, {
    required String currency,
  }) {
    expectSync(metal, PreciousMetal.gold);
    expectSync(purity, '22K');
    expectSync(currency, 'USD');
    return quote.future;
  }
}

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

  testWidgets('schema-3 migration resumes after the schema-5 step fails', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final path = p.join(
        await sql.getDatabasesPath(),
        'migration-regression-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      const password = 'isolated-migration-test';
      try {
        final seed = await sql.openDatabase(path, password: password);
        await seed.execute(
          'CREATE TABLE assets ('
          'id INTEGER PRIMARY KEY, portfolioId INTEGER, type TEXT, name TEXT, '
          'customName TEXT, currency TEXT, quantity REAL, pricePerUnit REAL, '
          'symbol TEXT, lastPrice REAL, lastPriceTimestamp INTEGER, '
          'manualValue REAL, notes TEXT, position INTEGER, '
          'createdAt INTEGER, updatedAt INTEGER, customPrice INTEGER DEFAULT 0)',
        );
        await seed.execute(
          'CREATE TABLE liabilities ('
          'id INTEGER PRIMARY KEY, portfolioId INTEGER, type TEXT, name TEXT, '
          'currency TEXT, amount REAL, notes TEXT, position INTEGER, '
          'createdAt INTEGER, updatedAt INTEGER)',
        );
        await seed.insert('assets', {
          'id': 1,
          'portfolioId': 1,
          'type': 'GOLD',
          'name': 'Legacy gold',
          'currency': 'USD',
          'quantity': 2.5,
          'pricePerUnit': 80.0,
          'position': 0,
          'createdAt': 0,
          'updatedAt': 0,
        });
        await seed.execute('PRAGMA user_version = 3');
        await seed.close();

        // A conflicting future column forces the schema-5 transaction to fail.
        await expectLater(
          AppDatabase.open(path: path, password: password),
          throwsA(isA<sql.DatabaseException>()),
        );
        final recovery = await sql.openDatabase(path, password: password);
        expect(
          (await recovery.rawQuery('PRAGMA user_version')).single.values.single,
          4,
        );
        await recovery.execute('ALTER TABLE assets DROP COLUMN customPrice');
        await recovery.close();
        final upgraded = await AppDatabase.open(path: path, password: password);
        expect(
          (await upgraded.db.rawQuery('PRAGMA user_version'))
              .single
              .values
              .single,
          5,
        );
        expect(
          AssetEntity.fromMap((await upgraded.db.query('assets')).single).value,
          200.0,
        );
        await upgraded.close();
      } finally {
        final remaining = await sql.openDatabase(path, password: password);
        await remaining.close();
        await sql.deleteDatabase(path);
      }
    });
  });

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

      final delayed = _DelayedMetalQuote(container.assetRepository);
      final quotedEditor = AssetEditViewModel(
        assetRepository: delayed,
        settingsRepository: container.settingsRepository,
        portfolioId: portfolioId,
        assetId: 0,
      );
      addTearDown(quotedEditor.dispose);
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AssetEditScreen(
                  portfolioId: portfolioId,
                  assetId: 0,
                  viewModel: quotedEditor,
                ),
              ),
            ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byType(DropdownSelector<AssetType>));
      await tap(tester, find.widgetWithText(ListTile, 'Valuables'));
      await tap(tester, find.widgetWithText(ListTile, 'Gold'));
      await tap(tester, find.widgetWithText(ListTile, '22K'));
      await enter(tester, 'Name', 'Quote focus probe');
      await tap(tester, field('Price per gram'));
      final rateInput = find.descendant(
        of: field('Price per gram'),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(rateInput).focusNode.hasFocus, isTrue);
      delayed.quote.complete(Result<double>.success(80.25));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(rateInput).controller.text, '80.25');
      expect(tester.widget<EditableText>(rateInput).focusNode.hasFocus, isTrue);
      await capture(tester, 'valuables-focused-quote');
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.text('Discard'));

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

      Future<void> saveAndReturn({
        Future<void> Function()? beforeReturn,
      }) async {
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
        if (beforeReturn != null) {
          await beforeReturn();
        }
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
      await tap(tester, find.text('Emulator gold'));
      await tap(tester, find.text('Edit asset'));
      await tap(tester, find.text('Total value'));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('Total value'),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '600.5',
      );
      await capture(tester, 'valuables-retained-appraisal');
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.text('Discard'));

      await addItem('Jewellery');
      expect(field('Weight (grams)'), findsNothing);
      await enter(tester, 'Name', 'Emulator ring');
      await enter(tester, 'Total value', '500.75');
      await saveAndReturn(
        beforeReturn: () async {
          final ring = await stored('Emulator ring');
          await tester.runAsync(() async {
            await container.database.db.execute(
              'CREATE TEMP TRIGGER valuables_undo_failure BEFORE DELETE ON assets '
              'WHEN OLD.id = ${ring.id} BEGIN '
              "SELECT RAISE(ABORT, 'controlled Undo failure'); END",
            );
            await container.settingsRepository.setLanguage(AppLanguage.spanish);
          });
          try {
            await tester.pumpAndSettle();
            await tap(tester, find.byKey(const ValueKey('undo-saved-holding')));
            expect(
              find.text('No se pudo deshacer este cambio.'),
              findsOneWidget,
            );
            await capture(tester, 'valuables-undo-error-es');
            expect((await stored('Emulator ring')).value, 500.75);
          } finally {
            await tester.runAsync(() async {
              await container.database.db.execute(
                'DROP TRIGGER temp.valuables_undo_failure',
              );
              await container.settingsRepository.setLanguage(
                AppLanguage.english,
              );
            });
            await tester.pumpAndSettle();
          }
        },
      );
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
