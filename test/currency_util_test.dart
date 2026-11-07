import 'package:intl/intl.dart';
import 'package:okanzo/util/currency_util.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => Intl.defaultLocale = 'en_US');

  group('format', () {
    test('groups thousands and drops decimals', () {
      expect(CurrencyUtil.format(1234.0, 'USD'), '\$1,234');
      expect(CurrencyUtil.format(0.0, 'USD'), '\$0');
    });

    test('rounds like java.lang.Math.round (half up, towards +inf)', () {
      expect(CurrencyUtil.format(1234.5, 'USD'), '\$1,235');
      expect(CurrencyUtil.format(1234.49, 'USD'), '\$1,234');
      // -0.5 rounds to 0 on the JVM, not to -1 as Dart's round() would.
      expect(CurrencyUtil.format(-0.5, 'USD'), '\$0');
      expect(CurrencyUtil.format(-1.5, 'USD'), '-\$1');
      expect(CurrencyUtil.format(-2.5, 'USD'), '-\$2');
    });

    test('keeps the sign outside the symbol', () {
      expect(CurrencyUtil.format(-4200.0, 'USD'), '-\$4,200');
    });

    test('falls back to the code for unknown currencies', () {
      expect(CurrencyUtil.format(10.0, 'ZZZ'), 'ZZZ10');
    });

    test('separates a letter symbol from the amount', () {
      // "R$" style symbols get a space so they do not run into the digits.
      expect(CurrencyUtil.symbol('BRL'), 'R \$');
      expect(CurrencyUtil.symbol('EUR'), '€');
    });
  });

  group('formatCompact', () {
    test('uses K starting at one thousand', () {
      expect(CurrencyUtil.formatCompact(1000.0, 'USD'), '\$1K');
      expect(CurrencyUtil.formatCompact(7054.0, 'USD'), '\$7K');
      expect(CurrencyUtil.formatCompact(-7054.0, 'USD'), '-\$7K');
      expect(CurrencyUtil.formatCompact(7540.0, 'USD'), '\$7.5K');
      expect(CurrencyUtil.formatCompact(9999.0, 'USD'), '\$9.9K');
      expect(CurrencyUtil.formatCompact(12345.0, 'USD'), '\$12.3K');
      expect(CurrencyUtil.formatCompact(10000.0, 'USD'), '\$10K');
    });

    test('keeps the plain format below one thousand', () {
      expect(CurrencyUtil.formatCompact(999.0, 'USD'), '\$999');
      expect(CurrencyUtil.formatCompact(-999.0, 'USD'), '-\$999');
    });

    test('uses M and B for larger magnitudes', () {
      expect(CurrencyUtil.formatCompact(1250000.0, 'USD'), '\$1.2M');
      expect(CurrencyUtil.formatCompact(-2500000000.0, 'USD'), '-\$2.5B');
    });

    test('truncates rather than rounds the single decimal', () {
      expect(CurrencyUtil.formatCompact(1290000.0, 'USD'), '\$1.2M');
    });

    test('uses lakh and crore for INR with up to two truncated decimals', () {
      expect(CurrencyUtil.formatCompact(16534234, 'INR'), '₹1.65 Cr');
      expect(CurrencyUtil.formatCompact(123456, 'INR'), '₹1.23 L');
      expect(CurrencyUtil.formatCompact(19999999, 'INR'), '₹1.99 Cr');
      expect(CurrencyUtil.formatCompact(1000000000, 'INR'), '₹100 Cr');
      expect(CurrencyUtil.formatCompact(-16534234, 'INR'), '-₹1.65 Cr');
      expect(CurrencyUtil.formatCompact(-123456, 'INR'), '-₹1.23 L');
    });

    test('keeps INR thresholds and small amounts consistent', () {
      expect(CurrencyUtil.formatCompact(0, 'INR'), '₹0');
      expect(CurrencyUtil.formatCompact(-0.5, 'INR'), '₹0');
      expect(CurrencyUtil.formatCompact(999, 'INR'), '₹999');
      expect(CurrencyUtil.formatCompact(1000, 'INR'), '₹1K');
      expect(CurrencyUtil.formatCompact(7054, 'INR'), '₹7K');
      expect(CurrencyUtil.formatCompact(9999, 'INR'), '₹9.9K');
      expect(CurrencyUtil.formatCompact(10000, 'INR'), '₹10K');
      expect(CurrencyUtil.formatCompact(99999, 'INR'), '₹99.9K');
      expect(CurrencyUtil.formatCompact(100000, 'INR'), '₹1 L');
      expect(CurrencyUtil.formatCompact(9999999, 'INR'), '₹99.99 L');
      expect(CurrencyUtil.formatCompact(10000000, 'INR'), '₹1 Cr');
    });

    test('international units are selected by currency, not device locale', () {
      final String? original = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = original);
      for (final String locale in <String>['en_US', 'en_IN', 'de_DE']) {
        Intl.defaultLocale = locale;
        expect(CurrencyUtil.formatCompact(16534234, 'INR'), '₹1.65 Cr');
        expect(CurrencyUtil.formatCompact(16534234, 'USD'), '\$16.5M');
        expect(CurrencyUtil.formatCompact(165342340, 'USD'), '\$165.3M');
        expect(CurrencyUtil.formatCompact(165342340, 'EUR'), '€165.3M');
        expect(CurrencyUtil.formatCompact(999999, 'USD'), '\$999.9K');
        expect(CurrencyUtil.formatCompact(1000000, 'USD'), '\$1M');
        expect(CurrencyUtil.formatCompact(999999999, 'USD'), '\$999.9M');
        expect(CurrencyUtil.formatCompact(1000000000, 'USD'), '\$1B');
        expect(CurrencyUtil.formatCompact(1000000, 'ZZZ'), 'ZZZ1M');
      }
    });
  });

  group('metadata', () {
    test('masked balance uses the symbol and bullet placeholder', () {
      expect(CurrencyUtil.masked('USD'), '\$ ••••');
      expect(CurrencyUtil.maskShort, '••••');
    });

    test('display names come from the bundled ISO-4217 table', () {
      expect(CurrencyUtil.displayName('USD'), 'US Dollar');
      expect(CurrencyUtil.displayName('ZZZ'), 'ZZZ');
    });

    test('fraction digits follow the currency', () {
      expect(CurrencyUtil.fractionDigits('USD'), 2);
      expect(CurrencyUtil.fractionDigits('JPY'), 0);
      expect(CurrencyUtil.fractionDigits('ZZZ'), 2);
    });

    test('the currency list is alphabetical, complete and unique', () {
      final List<String> all = CurrencyUtil.allCurrencies;
      expect(all.length, 233);
      expect(all.toSet().length, all.length);
      expect(all, orderedEquals(List<String>.of(all)..sort()));
      expect(all, containsAll(CurrencyUtil.commonCurrencies));
    });
  });
}
