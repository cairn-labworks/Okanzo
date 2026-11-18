import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okanzo/data/remote/stock/stock_search_service.dart';
import 'package:okanzo/domain/model/app_theme.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/ui/asset/stock_search_field.dart';
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/theme/theme.dart';
import 'package:okanzo/util/result.dart';

const StockSearchResult _apple = StockSearchResult(
  symbol: 'AAPL',
  name: 'Apple Inc.',
  exchange: 'NASDAQ',
);
const StockSearchResult _microsoft = StockSearchResult(
  symbol: 'MSFT',
  name: 'Microsoft Corporation',
  exchange: 'NASDAQ',
);

class _Search extends Fake implements StockSearchService {
  final List<
    ({
      String query,
      StockSearchType type,
      Completer<Result<List<StockSearchResult>>> response,
    })
  >
  requests = [];

  @override
  Future<Result<List<StockSearchResult>>> search(
    String query, {
    required StockSearchType type,
  }) {
    final Completer<Result<List<StockSearchResult>>> response = Completer();
    requests.add((query: query, type: type, response: response));
    return response.future;
  }

  void complete(int index, List<StockSearchResult> matches) => requests[index]
      .response
      .complete(Result<List<StockSearchResult>>.success(matches));
}

void main() {
  late TextEditingController symbol;
  late TextEditingController quantity;
  late _Search service;
  StockSearchResult? selected;

  setUp(() {
    symbol = TextEditingController();
    quantity = TextEditingController();
    service = _Search();
    selected = null;
  });

  tearDown(() {
    symbol.dispose();
    quantity.dispose();
  });

  Widget app({
    StockSearchType type = StockSearchType.stock,
    bool narrowRtl = false,
    double topPadding = 24,
  }) => MaterialApp(
    theme: buildTheme(
      brightness: narrowRtl ? Brightness.dark : Brightness.light,
      appTheme: narrowRtl ? AppTheme.midnight : AppTheme.classic,
    ),
    locale: narrowRtl ? const Locale('ar') : const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(narrowRtl ? 2 : 1)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, topPadding, 24, 24),
        child: StockSearchField(
          controller: symbol,
          service: service,
          type: type,
          quantityField: LabeledTextField(
            controller: quantity,
            label: 'Quantity',
          ),
          onChanged: (_) {},
          onSelected: (StockSearchResult result) {
            selected = result;
            symbol.text = result.symbol;
          },
        ),
      ),
    ),
  );

  Finder getSearch() => find.widgetWithText(TextField, 'Company or ticker');

  testWidgets(
    'crypto search shows coin names and preserves selected non-USD pairs',
    (WidgetTester tester) async {
      await tester.pumpWidget(app(type: StockSearchType.crypto));
      final Finder coin = find.widgetWithText(TextField, 'Coin or ticker');
      await tester.enterText(coin, 'Bitcoin');
      await tester.pump(const Duration(milliseconds: 350));
      expect(service.requests.single.type, StockSearchType.crypto);
      service.complete(0, <StockSearchResult>[
        const StockSearchResult(
          symbol: 'BTC-EUR',
          name: 'Bitcoin EUR',
          exchange: 'CCC',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Bitcoin EUR'), findsOneWidget);
      expect(find.text('BTC-EUR'), findsOneWidget);
      expect(find.textContaining('CCC'), findsNothing);
      await tester.tap(find.text('Bitcoin EUR'));
      await tester.pumpAndSettle();
      expect(selected!.symbol, 'BTC-EUR');
      expect(symbol.text, 'BTC-EUR');
    },
  );

  testWidgets(
    'switching from stock to crypto discards in-flight stock results',
    (WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.enterText(getSearch(), 'BTC');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpWidget(app(type: StockSearchType.crypto));
      service.complete(0, <StockSearchResult>[_apple]);
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Coin or ticker'),
        'Bitcoin',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(service.requests.last.type, StockSearchType.crypto);
      service.complete(1, <StockSearchResult>[]);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('can search funds after selecting a stock and changing type', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.enterText(getSearch(), 'Apple');
    await tester.pump(const Duration(milliseconds: 350));
    service.complete(0, <StockSearchResult>[_apple]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apple Inc.'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(type: StockSearchType.fund));
    await tester.pumpAndSettle();
    await tester.enterText(getSearch(), 'Vanguard');
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<TextField>(getSearch()).focusNode!.hasFocus, isTrue);
    expect(service.requests.last.query, 'Vanguard');
    expect(service.requests.last.type, StockSearchType.fund);
    service.complete(1, <StockSearchResult>[
      const StockSearchResult(
        symbol: 'VOO',
        name: 'Vanguard S&P 500 ETF',
        exchange: 'NYSEArca',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('VOO · NYSEArca'), findsOneWidget);
  });

  testWidgets(
    'debounces typing and selection fills the ticker without searching again',
    (WidgetTester tester) async {
      symbol.text = 'AAPL';
      await tester.pumpWidget(app());
      await tester.pump(const Duration(seconds: 1));
      expect(service.requests, isEmpty);
      await tester.enterText(getSearch(), 'A');
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.requests, isEmpty);
      await tester.enterText(getSearch(), 'Ap');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(getSearch(), 'Apple');
      await tester.pump(const Duration(milliseconds: 349));
      expect(service.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(service.requests.single.query, 'Apple');
      expect(service.requests.single.type, StockSearchType.stock);
      service.complete(0, <StockSearchResult>[_apple]);
      await tester.pumpAndSettle();
      expect(find.text('AAPL · NASDAQ'), findsOneWidget);
      final TestGesture click = await tester.startGesture(
        tester.getCenter(find.text('Apple Inc.')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await click.up();
      await tester.pumpAndSettle();
      expect(selected, _apple);
      expect(symbol.text, 'AAPL');
      expect(find.byType(ListTile), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(service.requests, hasLength(1));
    },
  );

  testWidgets(
    'ignores stale requests after new typing, clearing, or disposal',
    (WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.enterText(getSearch(), 'Apple');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(getSearch(), 'Microsoft');
      await tester.pump(const Duration(milliseconds: 350));
      service.complete(1, <StockSearchResult>[_microsoft]);
      await tester.pumpAndSettle();
      service.complete(0, <StockSearchResult>[_apple]);
      await tester.pumpAndSettle();
      expect(find.text('Microsoft Corporation'), findsOneWidget);
      expect(find.text('Apple Inc.'), findsNothing);
      await tester.enterText(getSearch(), 'App');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(getSearch(), '');
      service.complete(2, <StockSearchResult>[_apple]);
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      await tester.enterText(getSearch(), 'Apple');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpWidget(const SizedBox());
      service.complete(3, <StockSearchResult>[_apple]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('errors and empty results keep manual input usable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.enterText(getSearch(), 'AAPL');
    await tester.pump(const Duration(milliseconds: 350));
    service.requests.single.response.complete(
      Result<List<StockSearchResult>>.failure('HTTP 429'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Search unavailable. Enter a ticker manually or try again.'),
      findsOneWidget,
    );
    expect(symbol.text, 'AAPL');
    await tester.enterText(getSearch(), 'VOD.L');
    await tester.pump(const Duration(milliseconds: 350));
    service.complete(1, <StockSearchResult>[]);
    await tester.pumpAndSettle();
    expect(
      find.text('No matches. Try another name or enter a ticker.'),
      findsOneWidget,
    );
    expect(symbol.text, 'VOD.L');
    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '5');
    await tester.pumpAndSettle();
    expect(quantity.text, '5');
    expect(find.byType(ListTile), findsNothing);

    await tester.enterText(getSearch(), 'MSFT');
    await tester.pump(const Duration(milliseconds: 350));
    service.requests.last.response.complete(
      Result<List<StockSearchResult>>.offline(),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No internet connection. Enter a ticker manually to save offline.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(symbol.text, 'MSFT');
  });

  testWidgets('changing asset type invalidates pending stock results', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.enterText(getSearch(), 'Apple');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(app(type: StockSearchType.fund));
    service.complete(0, <StockSearchResult>[_apple]);
    await tester.pumpAndSettle();
    expect(find.text('Apple Inc.'), findsNothing);
    await tester.enterText(getSearch(), 'Vanguard');
    await tester.pump(const Duration(milliseconds: 350));
    expect(service.requests.last.type, StockSearchType.fund);
    service.complete(1, <StockSearchResult>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('suggestions scroll into view above the keyboard', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(topPadding: 420));
    await tester.enterText(getSearch(), 'Apple');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump(const Duration(milliseconds: 350));
    service.complete(0, <StockSearchResult>[_apple, _microsoft]);
    await tester.pumpAndSettle();
    final Rect suggestion = tester.getRect(
      find.widgetWithText(ListTile, 'Apple Inc.'),
    );
    expect(suggestion.bottom, lessThanOrEqualTo(844 - 320));
    expect(suggestion.top, greaterThanOrEqualTo(0));
    await tester.tap(find.text('Apple Inc.'));
    await tester.pumpAndSettle();
    expect(selected, _apple);
  });

  testWidgets(
    'suggestions fit Midnight on a narrow screen with large RTL text',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(narrowRtl: true));
      await tester.enterText(find.byType(TextField).first, 'Apple');
      await tester.pump(const Duration(milliseconds: 350));
      service.complete(0, <StockSearchResult>[
        const StockSearchResult(
          symbol: 'AAPL',
          name: 'Apple Inc. International listing with a long company name',
          exchange: 'NASDAQ Global Select Market',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final Finder tile = find.byType(ListTile);
      expect(Directionality.of(tester.element(tile)), TextDirection.rtl);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(selected!.symbol, 'AAPL');
    },
  );
}
