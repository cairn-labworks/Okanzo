import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat, Intl;
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/ui/asset/stock_exchange_field.dart';
import 'package:okanzo/util/relative_time.dart';

Widget _app(Widget child, {Locale? locale}) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

class _LocalizedLabel extends StatelessWidget {
  const _LocalizedLabel();

  @override
  Widget build(BuildContext context) => Text('Settings'.tr(context));
}

void main() {
  test('supports English and all twenty requested locales', () {
    expect(AppLocalizations.supportedLocales, hasLength(21));
    expect(
      AppLocalizations.supportedLocales
          .map((Locale locale) => locale.languageCode)
          .toSet(),
      containsAll(<String>[
        'en',
        'es',
        'pt',
        'fr',
        'de',
        'ja',
        'ko',
        'zh',
        'it',
        'hi',
        'ar',
        'id',
        'tr',
        'pl',
        'nl',
        'vi',
        'th',
        'ru',
        'sv',
        'da',
        'nb',
      ]),
    );
    expect(
      AppLocalizations.supportedLocales
          .singleWhere((Locale locale) => locale.languageCode == 'pt')
          .countryCode,
      'BR',
    );
    expect(
      AppLocalizations.supportedLocales
          .singleWhere((Locale locale) => locale.languageCode == 'zh')
          .scriptCode,
      'Hans',
    );
  });

  test('returns localized strings and interpolates dynamic message values', () {
    expect(const AppLocalizations(Locale('es')).text('Settings'), 'Ajustes');
    expect(
      const AppLocalizations(Locale('pt', 'BR')).text('Settings'),
      'Configurações',
    );
    expect(
      const AppLocalizations(Locale('es')).text('Updated 3 price(s)'),
      'Actualizados 3 precio(s)',
    );
    expect(
      const AppLocalizations(Locale('es')).text('Updated 3, 2 failed'),
      'Actualizados 3, 2 fallidos',
    );
    expect(
      const AppLocalizations(Locale('es')).text('Updated yesterday'),
      'Actualizado yesterday',
    );
  });

  test('interpolation preserves opaque values and multiline errors', () {
    const AppLocalizations strings = AppLocalizations(Locale('es'));
    expect(
      strings.text('Imported {assets} portfolio(s), 4 assets, 2 liabilities'),
      strings
          .text(
            'Imported {portfolios} portfolio(s), {assets} assets, {liabilities} liabilities',
          )
          .replaceAll('{assets}', '4')
          .replaceAll('{liabilities}', '2')
          .replaceAll('{portfolios}', '{assets}'),
    );
    expect(
      strings.text('Export failed: Network error\nPlease retry'),
      'Error al exportar: Network error\nPlease retry',
    );
  });

  test('all catalogs provide messages and preserve every placeholder', () {
    final RegExp tokens = RegExp(r'\{\w+\}');
    List<String> placeholders(String text) =>
        tokens.allMatches(text).map((RegExpMatch match) => match[0]!).toList()
          ..sort();
    for (final Locale locale in AppLocalizations.supportedLocales.skip(1)) {
      final AppLocalizations strings = AppLocalizations(locale);
      expect(strings.text('Settings'), isNot('Settings'), reason: '$locale');
      for (final String source in AppLocalizations.messageKeys) {
        final String translation = strings.text(source);
        expect(translation.trim(), isNotEmpty, reason: '$locale: $source');
        expect(
          placeholders(translation),
          placeholders(source),
          reason: '$locale: $source',
        );
      }
    }
  });

  test(
    'date labels use the resolved UI locale, not the formatting default',
    () async {
      await initializeDateFormatting('es');
      final String? original = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = original);
      Intl.defaultLocale = 'de_DE';
      final DateTime now = DateTime(2026, 11, 5, 12);
      const AppLocalizations strings = AppLocalizations(Locale('es'));
      expect(
        relativeTimeSpan(
          now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
          now: now,
          localizations: strings,
        ),
        strings.text('{count} minutes ago').replaceAll('{count}', '5'),
      );
      final DateTime old = now.subtract(const Duration(days: 30));
      expect(
        relativeTimeSpan(
          old.millisecondsSinceEpoch,
          now: now,
          localizations: strings,
        ),
        DateFormat.yMMMd('es').format(old),
      );
      final DateTime future = now.add(const Duration(days: 2));
      expect(
        relativeTimeSpan(
          future.millisecondsSinceEpoch,
          now: now,
          localizations: strings,
        ),
        DateFormat.yMMMd('es').format(future),
      );
    },
  );

  test('falls back to the source string for English and unknown messages', () {
    expect(const AppLocalizations(Locale('en')).text('Settings'), 'Settings');
    expect(
      const AppLocalizations(Locale('fr')).text('An unknown phrase'),
      'An unknown phrase',
    );
    expect(const AppLocalizations(Locale('uk')).text('Settings'), 'Settings');
  });

  testWidgets(
    'locale selection honors secondary languages and English fallback',
    (WidgetTester tester) async {
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.localesTestValue = <Locale>[
        const Locale('uk', 'UA'),
        const Locale('es', 'MX'),
      ];
      await tester.pumpWidget(_app(const _LocalizedLabel()));
      await tester.pumpAndSettle();
      expect(find.text('Ajustes'), findsOneWidget);

      tester.binding.platformDispatcher.localesTestValue = <Locale>[
        const Locale('uk', 'UA'),
      ];
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    },
  );

  testWidgets(
    'existing widgets update on device-language changes without remounting',
    (WidgetTester tester) async {
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final String? original = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = original);
      Intl.defaultLocale = 'de_DE';
      tester.binding.platformDispatcher.localesTestValue = <Locale>[
        const Locale('es'),
      ];
      await tester.pumpWidget(_app(const _LocalizedLabel()));
      await tester.pumpAndSettle();
      final Element label = tester.element(find.byType(_LocalizedLabel));
      expect(find.text('Ajustes'), findsOneWidget);

      tester.binding.platformDispatcher.localesTestValue = <Locale>[
        const Locale('fr'),
      ];
      await tester.pumpAndSettle();
      expect(find.text('Paramètres'), findsOneWidget);
      expect(tester.element(find.byType(_LocalizedLabel)), same(label));
    },
  );

  testWidgets('all supported locales load and Arabic uses RTL layout', (
    WidgetTester tester,
  ) async {
    for (final Locale locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(_app(const _LocalizedLabel(), locale: locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$locale');
      expect(
        Directionality.of(tester.element(find.byType(_LocalizedLabel))),
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        reason: '$locale',
      );
    }
  });

  testWidgets('exchange selector and preference errors are localized', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        StockExchangeField(
          selected: StockExchange.us,
          preferredExchanges: const <StockExchange>[StockExchange.us],
          onSelected: (_) {},
          onSavePreferences: (_) async =>
              throw StateError('Storage unavailable'),
        ),
        locale: const Locale('es'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bolsa'), findsOneWidget);
    expect(
      tester
          .widget<DropdownMenu<Object>>(find.byType(DropdownMenu<Object>))
          .controller!
          .text,
      'EE. UU. (NYSE / Nasdaq)',
    );
    await tester.tap(find.byType(DropdownMenu<Object>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seleccionar bolsas preferidas...').last);
    await tester.pumpAndSettle();
    expect(find.text('Bolsas preferidas'), findsOneWidget);
    expect(find.text('1 seleccionadas'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No se pudieron guardar las bolsas preferidas:'),
      findsOneWidget,
    );
    expect(find.textContaining('Storage unavailable'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
