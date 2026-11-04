import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okanzo/l10n/app_localizations.dart';

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
    expect(
      const AppLocalizations(Locale('es')).text('Settings'),
      'Ajustes',
    );
    expect(
      const AppLocalizations(Locale('pt', 'BR')).text('Settings'),
      'Configurações',
    );
    expect(
      const AppLocalizations(Locale('es')).text('Updated 3 price(s)'),
      'Actualizados 3 precio(s)',
    );
  });

  test('falls back to the source string for English and unknown messages', () {
    expect(
      const AppLocalizations(Locale('en')).text('Settings'),
      'Settings',
    );
    expect(
      const AppLocalizations(Locale('fr')).text('An unknown phrase'),
      'An unknown phrase',
    );
  });
}
