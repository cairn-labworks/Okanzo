import 'package:flutter_test/flutter_test.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/domain/model/stock_exchange.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late SettingsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    repository = SettingsRepository(preferences);
    addTearDown(repository.dispose);
  });

  test('only US is preferred before the user customizes the list', () {
    expect(repository.current.preferredExchanges, <StockExchange>[
      StockExchange.us,
    ]);
  });

  test('persists a deduplicated shortlist in exchange order', () async {
    await repository.setPreferredExchanges(<StockExchange>[
      StockExchange.bse,
      StockExchange.us,
      StockExchange.bse,
      StockExchange.other,
    ]);
    await preferences.reload();
    final SettingsRepository reopened = SettingsRepository(preferences);
    addTearDown(reopened.dispose);

    expect(reopened.current.preferredExchanges, <StockExchange>[
      StockExchange.us,
      StockExchange.bse,
      StockExchange.other,
    ]);
    expect(
      () => reopened.current.preferredExchanges.add(StockExchange.tokyo),
      throwsUnsupportedError,
    );
  });

  test(
    'an explicitly empty list survives reload instead of restoring US',
    () async {
      await repository.setPreferredExchanges(const <StockExchange>[]);
      await preferences.reload();
      final SettingsRepository reopened = SettingsRepository(preferences);
      addTearDown(reopened.dispose);

      expect(reopened.current.preferredExchanges, isEmpty);
      expect(reopened.current.baseCurrency, repository.current.baseCurrency);
    },
  );

  test(
    'ignores obsolete preference names without adding other exchanges',
    () async {
      await preferences.setStringList('preferred_stock_exchanges', <String>[
        'bse',
        'removedExchange',
        'bse',
      ]);

      expect(repository.current.preferredExchanges, <StockExchange>[
        StockExchange.bse,
      ]);
    },
  );

  test('notifies settings subscribers after preferences are saved', () async {
    final List<List<StockExchange>> received = <List<StockExchange>>[];
    final subscription = repository.settings.listen(
      (AppSettings value) => received.add(value.preferredExchanges),
    );
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);

    await repository.setPreferredExchanges(<StockExchange>[StockExchange.bse]);
    await Future<void>.delayed(Duration.zero);

    expect(received, <List<StockExchange>>[
      <StockExchange>[StockExchange.us],
      <StockExchange>[StockExchange.bse],
    ]);
  });
}
