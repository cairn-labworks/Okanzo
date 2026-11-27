import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okanzo/domain/model/app_theme.dart';
import 'package:okanzo/domain/model/net_worth_summary.dart';
import 'package:okanzo/ui/components/ui_components.dart';
import 'package:okanzo/ui/home/net_worth_card.dart';
import 'package:okanzo/ui/theme/app_material.dart';
import 'package:okanzo/ui/theme/theme.dart';

const NetWorthSummary _summary = NetWorthSummary(
  baseCurrency: 'USD',
  totalAssets: 360500,
  totalLiabilities: 148000,
  assetBreakdown: <CategoryTotal>[],
  liabilityBreakdown: <CategoryTotal>[],
  hasApproximateConversions: false,
);

Finder get _gradient => find.byWidgetPredicate(
  (Widget widget) =>
      widget is DecoratedBox &&
      switch (widget.decoration) {
        BoxDecoration(:final gradient) => gradient != null,
        ShapeDecoration(:final gradient) => gradient != null,
        _ => false,
      },
);

Widget _app(AppTheme style, Brightness brightness, Widget child) => MaterialApp(
  theme: buildTheme(brightness: brightness, appTheme: style),
  home: Scaffold(
    body: Center(child: SizedBox(width: 378, child: child)),
  ),
);

void main() {
  testWidgets('pushed glass pages own an opaque route backdrop', (
    WidgetTester tester,
  ) async {
    const Key nextPage = ValueKey<String>('glass-pushed-page');
    final theme = buildTheme(
      brightness: Brightness.light,
      appTheme: AppTheme.liquidGlass,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (_, child) => AppThemeBackground(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(key: nextPage, body: Text('Next page')),
                ),
              ),
              child: const Text('Open page'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final Finder localBackdrops = find.descendant(
      of: find.byType(Navigator),
      matching: find.byType(AppThemeBackground),
    );
    final Finder pageBackdrop = find.ancestor(
      of: find.byKey(nextPage),
      matching: localBackdrops,
    );
    expect(pageBackdrop, findsWidgets);
    final ColoredBox background = tester.widget<ColoredBox>(
      find
          .descendant(of: pageBackdrop.first, matching: find.byType(ColoredBox))
          .first,
    );
    expect(background.color.a, 1);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(nextPage))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Open page'), findsOneWidget);
  });

  testWidgets('opaque glass avatar tints do not add backdrop filters', (
    WidgetTester tester,
  ) async {
    for (final Brightness brightness in Brightness.values) {
      await tester.pumpWidget(
        _app(
          AppTheme.liquidGlass,
          brightness,
          const TypeAvatar(Icons.wallet_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
    }
  });

  for (final AppTheme style in <AppTheme>[
    AppTheme.sculpted,
    AppTheme.liquidGlass,
  ]) {
    testWidgets('$style layers surfaces without changing the overview layout', (
      WidgetTester tester,
    ) async {
      for (final Brightness brightness in Brightness.values) {
        const Widget card = NetWorthCard(
          summary: _summary,
          hideBalances: false,
        );
        await tester.pumpWidget(_app(AppTheme.classic, brightness, card));
        await tester.pumpAndSettle();
        final Finder block = find.byKey(
          const ValueKey<String>('net-worth-block'),
        );
        final Size originalSize = tester.getSize(block);
        final String? originalHeadline = tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('net-worth-headline')),
            )
            .data;

        await tester.pumpWidget(_app(style, brightness, card));
        await tester.pumpAndSettle();

        expect(tester.getSize(block), originalSize);
        expect(find.ancestor(of: block, matching: _gradient), findsWidgets);
        expect(
          find.ancestor(of: block, matching: find.byType(BackdropFilter)),
          style == AppTheme.liquidGlass ? findsOneWidget : findsNothing,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey<String>('net-worth-headline')),
              )
              .data,
          originalHeadline,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('$style keeps native button states and destructive colors', (
      WidgetTester tester,
    ) async {
      int saves = 0;
      final ThemeData theme = buildTheme(
        brightness: Brightness.light,
        appTheme: style,
      );
      await tester.pumpWidget(
        _app(
          style,
          Brightness.light,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FilledButton(
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                onPressed: () => saves++,
                child: const Text('Save'),
              ),
              const FilledButton(onPressed: null, child: Text('Disabled')),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                ),
                onPressed: () {},
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final Decoration sheen = tester
          .widget<DecoratedBox>(
            find.descendant(
              of: find.widgetWithText(FilledButton, 'Save'),
              matching: _gradient,
            ),
          )
          .decoration;
      expect(
        sheen.hitTest(
          const Size(100, 50),
          const Offset(7, 7),
          textDirection: TextDirection.ltr,
        ),
        isFalse,
        reason:
            'The sheen must follow the button shape, not paint a rectangle.',
      );
      Material buttonMaterial(String text) => tester.widget<Material>(
        find
            .ancestor(of: find.text(text), matching: find.byType(Material))
            .first,
      );
      final double restingElevation = buttonMaterial('Save').elevation;
      expect(restingElevation, greaterThan(0));
      final TestGesture press = await tester.startGesture(
        tester.getCenter(find.text('Save')),
      );
      await tester.pumpAndSettle();
      expect(buttonMaterial('Save').elevation, lessThan(restingElevation));
      await press.up();
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(
        find.descendant(
          of: find.widgetWithText(FilledButton, 'Disabled'),
          matching: _gradient,
        ),
        findsNothing,
      );
      expect(buttonMaterial('Delete').color, theme.colorScheme.error);
    });
  }
}
