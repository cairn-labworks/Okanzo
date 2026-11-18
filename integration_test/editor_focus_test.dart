import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/liability/liability_edit_screen.dart';
import 'package:okanzo/ui/theme/theme.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final String scenario in <String>['Cash', 'Real estate', 'Loan']) {
    testWidgets('$scenario creation focuses its amount', (
      WidgetTester tester,
    ) async {
      final AppContainer container = await AppContainer.create();
      try {
        await tester.pumpWidget(
          AppScope(
            container: container,
            child: MaterialApp(
              theme: buildTheme(brightness: Brightness.light),
              locale: const Locale('en'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Builder(
                builder: (BuildContext context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => scenario == 'Loan'
                            ? const LiabilityEditScreen(
                                portfolioId: 0,
                                liabilityId: 0,
                              )
                            : const AssetEditScreen(portfolioId: 0, assetId: 0),
                      ),
                    ),
                    child: const Text('Open synthetic editor'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open synthetic editor'));
        await tester.pumpAndSettle();
        if (scenario != 'Loan') {
          await tester.tap(find.byType(DropdownSelector<AssetType>));
          await tester.pumpAndSettle();
          await tester.tap(find.text(scenario).last);
          await tester.pumpAndSettle();
        }
        final Finder field = find.byWidgetPredicate(
          (Widget widget) =>
              widget is LabeledTextField &&
              widget.label ==
                  (scenario == 'Loan' ? 'Outstanding amount' : 'Value'),
        );
        final EditableTextState input = tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        if (input.widget.focusNode.hasFocus) {
          final Stopwatch watch = Stopwatch()..start();
          while (View.of(tester.element(field)).viewInsets.bottom == 0 ||
              !input.cursorCurrentlyVisible) {
            if (watch.elapsed > const Duration(seconds: 15)) {
              fail('Timed out waiting for the keyboard and visible cursor');
            }
            await tester.pump(const Duration(milliseconds: 50));
          }
        }
        await binding.takeScreenshot(
          scenario.toLowerCase().replaceAll(' ', '-'),
        );
        debugPrint(
          'FOCUS CHECK $scenario: focused=${input.widget.focusNode.hasFocus}, '
          'selection=${input.widget.controller.selection}, '
          'keyboard=${View.of(tester.element(field)).viewInsets.bottom}',
        );
        expect(input.widget.focusNode.hasFocus, isTrue);
        expect(input.widget.controller.selection.isCollapsed, isTrue);
        final bool initialCursor = input.cursorCurrentlyVisible;
        bool blinked = false;
        for (int frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
          blinked |= input.cursorCurrentlyVisible != initialCursor;
        }
        expect(blinked, isTrue, reason: 'Amount cursor should blink');
        expect(
          View.of(tester.element(field)).viewInsets.bottom,
          greaterThan(0),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await container.settingsRepository.dispose();
        await container.database.close();
      }
    });
  }
}
