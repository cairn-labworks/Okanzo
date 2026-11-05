import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:okanzo/ui/asset/asset_form_state.dart';
import 'package:okanzo/ui/liability/liability_form_state.dart';
import 'package:test/test.dart';

void main() {
  group('AssetFormState exchange selection', () {
    test('exchange suffixes and currencies match Yahoo coverage', () {
      const Map<StockExchange, (String, String?)> expected =
          <StockExchange, (String, String?)>{
            StockExchange.us: ('', 'USD'),
            StockExchange.shanghai: ('.SS', 'CNY'),
            StockExchange.euronextParis: ('.PA', 'EUR'),
            StockExchange.euronextAmsterdam: ('.AS', 'EUR'),
            StockExchange.euronextBrussels: ('.BR', 'EUR'),
            StockExchange.euronextLisbon: ('.LS', 'EUR'),
            StockExchange.euronextDublin: ('.IR', 'EUR'),
            StockExchange.euronextOslo: ('.OL', 'NOK'),
            StockExchange.euronextMilan: ('.MI', 'EUR'),
            StockExchange.tokyo: ('.T', 'JPY'),
            StockExchange.hongKong: ('.HK', 'HKD'),
            StockExchange.bse: ('.BO', 'INR'),
            StockExchange.other: ('', null),
          };

      expect(expected.keys, unorderedEquals(StockExchange.values));
      for (final MapEntry<StockExchange, (String, String?)> entry
          in expected.entries) {
        expect(entry.key.suffix, entry.value.$1);
        expect(entry.key.currency, entry.value.$2);
      }
    });

    test('adds each exchange suffix when saving stocks and funds', () {
      for (final AssetType type in <AssetType>[
        AssetType.stock,
        AssetType.mutualFund,
      ]) {
        for (final StockExchange exchange in StockExchange.values) {
          final AssetFormState form = AssetFormState(
            type: type,
            name: 'Holding',
            quantity: '1',
          ).withExchange(exchange).withSymbol(exchange.example);
          final String symbol = exchange.qualify(exchange.example);

          expect(form.validate(), isNull);
          expect(form.quoteSymbol, symbol);
          expect(form.toEntity().symbol, symbol);
        }
      }
    });

    test(
      'preserves leading zeros and accepts full tickers without doubling',
      () {
        final AssetFormState form = const AssetFormState()
            .withExchange(StockExchange.hongKong)
            .withSymbol(' 0700.hk ');

        expect(form.exchange, StockExchange.hongKong);
        expect(form.quoteSymbol, '0700.HK');
        expect(form.toEntity().symbol, '0700.HK');
      },
    );

    test('a full ticker selects its exchange and currency', () {
      final AssetFormState form = const AssetFormState(currency: 'USD')
          .withSymbol('reliance.bo');

      expect(form.exchange, StockExchange.bse);
      expect(form.currency, 'INR');
      expect(form.quoteSymbol, 'RELIANCE.BO');
    });

    test('changing exchange replaces the suffix and clears the quote', () {
      final AssetFormState form = const AssetFormState(
        symbol: 'RELIANCE.BO',
        exchange: StockExchange.bse,
        currency: 'INR',
        lastPrice: 100,
        lastPriceTimestamp: 10,
      ).withExchange(StockExchange.euronextParis);

      expect(form.symbol, 'RELIANCE');
      expect(form.quoteSymbol, 'RELIANCE.PA');
      expect(form.currency, 'EUR');
      expect(form.lastPrice, isNull);
      expect(form.lastPriceTimestamp, isNull);
    });

    test('other mode keeps the full ticker, including unlisted exchanges', () {
      final AssetFormState form = const AssetFormState(
        symbol: '0700',
        exchange: StockExchange.hongKong,
      ).withExchange(StockExchange.other);

      expect(form.symbol, '0700.HK');
      expect(form.quoteSymbol, '0700.HK');
      expect(form.withSymbol(' vod.l ').quoteSymbol, 'VOD.L');
      expect(form.withSymbol(' vod.l ').exchange, StockExchange.other);
      expect(
        form.withSymbol('VOD.L').withExchange(StockExchange.bse).quoteSymbol,
        'VOD.BO',
      );
    });

    test('existing listings round-trip without a storage migration', () {
      for (final String symbol in <String>[
        'AAPL',
        '0700.HK',
        'RELIANCE.BO',
        'AIR.PA',
        'VOD.L',
        '000001.SZ',
      ]) {
        final AssetEntity entity = AssetEntity(
          portfolioId: 1,
          type: AssetType.stock,
          name: symbol,
          currency: 'USD',
          symbol: symbol,
          createdAt: 1,
          updatedAt: 2,
        );
        final AssetFormState form = AssetFormState.fromEntity(entity);

        expect(form.exchange, StockExchange.fromSymbol(symbol));
        expect(form.toEntity().symbol, symbol);
        expect(form.currency, entity.currency);
      }
    });

    test('exchange selection does not qualify cryptocurrency symbols', () {
      final AssetFormState form = const AssetFormState(
        type: AssetType.crypto,
        symbol: ' btc-usd ',
        exchange: StockExchange.hongKong,
      );

      expect(form.usesStockExchange, isFalse);
      expect(form.quoteSymbol, 'BTC-USD');
      expect(form.toEntity().symbol, 'BTC-USD');
    });

    test('blank local tickers remain invalid after selecting an exchange', () {
      final AssetFormState form = const AssetFormState(
        name: 'Holding',
        quantity: '1',
      ).withExchange(StockExchange.bse);

      expect(form.quoteSymbol, isEmpty);
      expect(form.validate(), 'Enter a ticker symbol');
      expect(form.toEntity().symbol, isNull);
    });
  });

  group('AssetFormState.validate', () {
    test('requires a name and a currency first', () {
      expect(
        const AssetFormState(name: '  ').validate(),
        'Give this asset a name',
      );
      expect(
        const AssetFormState(name: 'Apple', currency: ' ').validate(),
        'Choose a currency',
      );
    });

    test('market assets need a symbol and a positive quantity', () {
      const AssetFormState base = AssetFormState(
        name: 'Apple',
        type: AssetType.stock,
      );
      expect(base.validate(), 'Enter a ticker symbol');
      expect(base.copyWith(symbol: 'AAPL').validate(), 'Enter a quantity');
      expect(
        base.copyWith(symbol: 'AAPL', quantity: '0').validate(),
        'Enter a quantity',
      );
      expect(base.copyWith(symbol: 'AAPL', quantity: '1.5').validate(), isNull);
    });

    test('quantity assets need a quantity and a unit price', () {
      const AssetFormState base = AssetFormState(
        name: 'Bars',
        type: AssetType.gold,
      );
      expect(base.validate(), 'Enter a quantity');
      expect(
        base.copyWith(quantity: '10').validate(),
        'Enter a price per unit',
      );
      expect(
        base.copyWith(quantity: '10', pricePerUnit: '65').validate(),
        isNull,
      );
    });

    test('flat assets accept any parsable value, including zero', () {
      const AssetFormState base = AssetFormState(
        name: 'Wallet',
        type: AssetType.cash,
      );
      expect(base.validate(), 'Enter a value');
      expect(base.copyWith(manualValue: '0').validate(), isNull);
      expect(base.copyWith(manualValue: '-5').validate(), isNull);
      expect(base.copyWith(manualValue: 'abc').validate(), 'Enter a value');
    });
  });

  group('AssetFormState.estimatedValue', () {
    test('market uses the fetched price, not the typed one', () {
      const AssetFormState state = AssetFormState(
        type: AssetType.stock,
        quantity: '3',
        pricePerUnit: '999',
        lastPrice: 10.0,
      );
      expect(state.estimatedValue, 30.0);
    });

    test('quantity multiplies the two typed numbers', () {
      const AssetFormState state = AssetFormState(
        type: AssetType.gold,
        quantity: '2.5',
        pricePerUnit: '40',
      );
      expect(state.estimatedValue, 100.0);
    });

    test('flat reads the manual value and tolerates junk', () {
      expect(
        const AssetFormState(
          type: AssetType.cash,
          manualValue: '12.5',
        ).estimatedValue,
        12.5,
      );
      expect(
        const AssetFormState(
          type: AssetType.cash,
          manualValue: 'x',
        ).estimatedValue,
        0.0,
      );
    });
  });

  group('AssetFormState.toEntity', () {
    test('trims text, upper-cases the ticker and nulls empty fields', () {
      final AssetEntity entity = const AssetFormState(
        id: 7,
        portfolioId: 3,
        type: AssetType.stock,
        name: '  Apple  ',
        currency: ' usd ',
        quantity: '2',
        symbol: ' aapl ',
        notes: '   ',
        lastPrice: 190.5,
      ).toEntity(now: 1000);

      expect(entity.id, 7);
      expect(entity.portfolioId, 3);
      expect(entity.name, 'Apple');
      expect(entity.currency, 'USD');
      expect(entity.symbol, 'AAPL');
      expect(entity.notes, isNull);
      expect(entity.quantity, 2.0);
      expect(entity.pricePerUnit, isNull);
      expect(entity.lastPrice, 190.5);
      expect(entity.createdAt, 1000);
      expect(entity.updatedAt, 1000);
    });

    test('round-trips through fromEntity', () {
      final AssetEntity entity = AssetEntity(
        id: 4,
        portfolioId: 1,
        type: AssetType.gold,
        name: 'Coins',
        currency: 'INR',
        quantity: 12.5,
        pricePerUnit: 6000.0,
        notes: 'safe',
        createdAt: 1,
        updatedAt: 2,
      );
      final AssetFormState form = AssetFormState.fromEntity(entity);

      expect(form.loading, isFalse);
      expect(form.quantity, '12.5');
      expect(form.pricePerUnit, '6000');
      expect(form.notes, 'safe');

      final AssetEntity again = form.toEntity(now: 9);
      expect(again.quantity, 12.5);
      expect(again.pricePerUnit, 6000.0);
      expect(again.type, AssetType.gold);
    });
  });

  group('LiabilityFormState', () {
    test('validates name, currency and amount', () {
      expect(
        const LiabilityFormState().validate(),
        'Give this liability a name',
      );
      expect(
        const LiabilityFormState(name: 'Car', currency: '').validate(),
        'Choose a currency',
      );
      expect(
        const LiabilityFormState(name: 'Car').validate(),
        'Enter an amount',
      );
      expect(
        const LiabilityFormState(name: 'Car', amount: '0').validate(),
        isNull,
      );
    });

    test('converts to an entity with trimmed fields', () {
      final LiabilityEntity entity = const LiabilityFormState(
        portfolioId: 2,
        type: LiabilityType.mortgage,
        name: ' House ',
        currency: 'eur',
        amount: '250000',
        notes: ' fixed ',
      ).toEntity(now: 55);

      expect(entity.name, 'House');
      expect(entity.currency, 'EUR');
      expect(entity.amount, 250000.0);
      expect(entity.notes, 'fixed');
      expect(entity.createdAt, 55);
      expect(entity.value, 250000.0);
    });

    test('an unparsable amount becomes zero in the entity', () {
      expect(
        const LiabilityFormState(name: 'X', amount: 'nope').toEntity().amount,
        0.0,
      );
    });
  });

  group('text field helpers', () {
    test('filterDecimal keeps digits and a single dot', () {
      expect(filterDecimal('12a.3b4'), '12.34');
      expect(filterDecimal('1.2.3'), '1.23');
      expect(filterDecimal('-5'), '5');
      expect(filterDecimal('.'), '.');
      expect(filterDecimal(''), '');
    });

    test('formatInput drops a trailing .0', () {
      expect(formatInput(12.0), '12');
      expect(formatInput(12.5), '12.5');
      expect(formatInput(0.0), '0');
      expect(formatInput(-3.0), '-3');
    });
  });
}
