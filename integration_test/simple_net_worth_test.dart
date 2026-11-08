import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_language.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/home/net_worth_card.dart';
import 'package:okanzo/util/currency_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<(String, double, String)> _simpleExamples =
    <(String, double, String)>[
      ('USD', 0, '\$0'),
      ('USD', 42.75, '\$43'),
      ('USD', 999, '\$999'),
      ('USD', 1000, '\$1K'),
      ('USD', 7054, '\$7K'),
      ('USD', 7540, '\$7.5K'),
      ('USD', 9999, '\$9.9K'),
      ('USD', 12345, '\$12.3K'),
      ('USD', -7054, '-\$7K'),
      ('USD', 999999, '\$999.9K'),
      ('USD', 1234567, '\$1.2M'),
      ('USD', 2500000000, '\$2.5B'),
      ('INR', 123456, '₹1.23 L'),
      ('INR', 16534234, '₹1.65 Cr'),
    ];

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition,
  String description,
) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed >= const Duration(seconds: 45)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: description);
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: description);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _waitUntil(
    tester,
    () => finder.hitTestable().evaluate().isNotEmpty,
    'an unobstructed tap target',
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _openCurrencySettings(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('Settings'));
  if (find.text('Simple net worth').evaluate().isEmpty) {
    await _tap(tester, find.text('Currency'));
  }
}

Future<void> _closeCurrencySettings(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Finder _cardText(String value) =>
    find.descendant(of: find.byType(NetWorthCard), matching: find.text(value));

Finder get _headline =>
    find.byKey(const ValueKey<String>('net-worth-headline'));

Future<void> _expectHeadline(WidgetTester tester, String value) => _waitUntil(
  tester,
  () =>
      _headline.evaluate().length == 1 &&
      tester.widget<Text>(_headline).data == value,
  'headline $value',
);

AppContainer _container(WidgetTester tester) =>
    AppScope.of(tester.element(find.byType(HomeScreen)));

Future<int> _createPortfolio(
  AppContainer container,
  List<int> testPortfolios, {
  required String currency,
  required double assets,
  required double liabilities,
}) async {
  final int portfolioId = await container.portfolioRepository.create(
    'Simple worth smoke $currency ${DateTime.now().millisecondsSinceEpoch}',
  );
  testPortfolios.add(portfolioId);
  await container.assetRepository.save(
    AssetEntity(
      portfolioId: portfolioId,
      type: AssetType.cash,
      name: 'Test cash',
      currency: currency,
      manualValue: assets,
      createdAt: 0,
      updatedAt: 0,
    ),
  );
  await container.liabilityRepository.save(
    LiabilityEntity(
      portfolioId: portfolioId,
      type: LiabilityType.loan,
      name: 'Test loan',
      currency: currency,
      amount: liabilities,
      createdAt: 0,
      updatedAt: 0,
    ),
  );
  return portfolioId;
}

Future<void> _restorePreferences(
  SharedPreferences preferences,
  Map<String, Object?> original,
) async {
  for (final MapEntry<String, Object?> entry in original.entries) {
    final bool saved = switch (entry.value) {
      null => await preferences.remove(entry.key),
      final bool value => await preferences.setBool(entry.key, value),
      final int value => await preferences.setInt(entry.key, value),
      final String value => await preferences.setString(entry.key, value),
      _ => throw StateError('Unexpected preference type for ${entry.key}'),
    };
    expect(saved, isTrue, reason: 'Restore ${entry.key}');
  }
  await preferences.reload();
  for (final MapEntry<String, Object?> entry in original.entries) {
    expect(preferences.get(entry.key), entry.value, reason: entry.key);
  }
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('simple net worth works on device and persists across relaunch', (
    WidgetTester tester,
  ) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final Map<String, Object?> original = <String, Object?>{
      for (final String key in <String>[
        'base_currency',
        'hide_balances',
        'simple_net_worth',
        'selected_portfolio_id',
        'app_language',
        'last_seen_version',
      ])
        key: preferences.get(key),
    };
    AppContainer? container;
    final List<int> testPortfolios = <int>[];
    try {
      final SettingsRepository setup = SettingsRepository(preferences);
      try {
        await setup.setLanguage(AppLanguage.english);
        await setup.setLastSeenVersion(AppReleaseNotes.currentVersion);
        await setup.setHideBalances(true);
        await setup.setSimpleNetWorth(false);
      } finally {
        await setup.dispose();
      }
      await app.main();
      await _waitUntil(
        tester,
        () => find.byType(NetWorthCard).evaluate().isNotEmpty,
        'unlocked home screen',
      );
      container = _container(tester);
      final int inrPortfolio = await _createPortfolio(
        container,
        testPortfolios,
        currency: 'INR',
        assets: 17534234,
        liabilities: 1000000,
      );
      final int usdPortfolio = await _createPortfolio(
        container,
        testPortfolios,
        currency: 'USD',
        assets: 166342340,
        liabilities: 1000000,
      );
      await container.settingsRepository.setBaseCurrency('INR');
      await container.settingsRepository.setSelectedPortfolioId(inrPortfolio);
      await container.settingsRepository.setHideBalances(false);
      await _expectHeadline(tester, CurrencyUtil.format(16534234, 'INR'));
      debugPrint('DEVICE CHECK: detailed INR headline passed');

      await _openCurrencySettings(tester);
      await _tap(tester, find.text('Simple net worth'));
      await _waitUntil(
        tester,
        () => container!.settingsRepository.current.simpleNetWorth,
        'saved simple net worth setting',
      );
      await _closeCurrencySettings(tester);
      await tester.pumpAndSettle();
      await _expectHeadline(tester, '₹1.65 Cr');
      expect(_cardText(CurrencyUtil.format(17534234, 'INR')), findsOneWidget);
      expect(_cardText(CurrencyUtil.format(1000000, 'INR')), findsOneWidget);
      debugPrint('DEVICE CHECK: INR crore and exact detail totals passed');

      await _tap(tester, find.byTooltip('Hide balances'));
      await _expectHeadline(tester, CurrencyUtil.masked('INR'));
      expect(_cardText('₹1.65 Cr'), findsNothing);
      expect(_cardText(CurrencyUtil.maskShort), findsNWidgets(2));
      await _tap(tester, find.byTooltip('Show balances'));
      await _expectHeadline(tester, '₹1.65 Cr');
      debugPrint('DEVICE CHECK: hidden balances and reveal passed');

      await _openCurrencySettings(tester);
      await _tap(tester, find.text('Simple net worth'));
      await _waitUntil(
        tester,
        () => !container!.settingsRepository.current.simpleNetWorth,
        'disabled simple net worth setting',
      );
      await _closeCurrencySettings(tester);
      await tester.pumpAndSettle();
      await _expectHeadline(tester, CurrencyUtil.format(16534234, 'INR'));
      debugPrint('DEVICE CHECK: disabling restores the exact headline');

      await _openCurrencySettings(tester);
      await _tap(tester, find.text('Simple net worth'));
      await _waitUntil(
        tester,
        () => container!.settingsRepository.current.simpleNetWorth,
        're-enabled simple net worth setting',
      );
      await _closeCurrencySettings(tester);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await container.settingsRepository.dispose();
      await container.database.close();
      container = null;
      await preferences.reload();
      await app.main();
      await _expectHeadline(tester, '₹1.65 Cr');
      container = _container(tester);
      expect(container.settingsRepository.current.simpleNetWorth, isTrue);
      debugPrint(
        'DEVICE CHECK: persisted setting and database relaunch passed',
      );

      await _openCurrencySettings(tester);
      await _tap(tester, find.text('Base currency'));
      await _tap(tester, find.text('USD — US Dollar'));
      await _waitUntil(
        tester,
        () => container!.settingsRepository.current.baseCurrency == 'USD',
        'USD base currency selected in the picker',
      );
      await container.settingsRepository.setSelectedPortfolioId(usdPortfolio);
      await _closeCurrencySettings(tester);
      await tester.pumpAndSettle();
      await _expectHeadline(tester, '\$165.3M');
      expect(_cardText(CurrencyUtil.format(166342340, 'USD')), findsOneWidget);
      expect(_cardText(CurrencyUtil.format(1000000, 'USD')), findsOneWidget);
      debugPrint('DEVICE CHECK: USD millions and exact detail totals passed');
      final AssetEntity usdAsset =
          (await container.assetRepository.getForPortfolio(usdPortfolio))
              .single;
      final LiabilityEntity usdLiability =
          (await container.liabilityRepository.getForPortfolio(usdPortfolio))
              .single;
      await container.assetRepository.save(
        usdAsset.copyWith(manualValue: 8054),
      );
      await container.liabilityRepository.save(
        usdLiability.copyWith(amount: 1000),
      );
      await _expectHeadline(tester, '\$7K');
      expect(_cardText(CurrencyUtil.format(8054, 'USD')), findsOneWidget);
      expect(_cardText(CurrencyUtil.format(1000, 'USD')), findsOneWidget);
      await _openCurrencySettings(tester);
      await _tap(tester, find.text('Simple net worth'));
      await _waitUntil(
        tester,
        () => !container!.settingsRepository.current.simpleNetWorth,
        'disabled simple net worth setting for USD thousands',
      );
      await _closeCurrencySettings(tester);
      await tester.pumpAndSettle();
      await _expectHeadline(tester, CurrencyUtil.format(7054, 'USD'));
      await _openCurrencySettings(tester);
      await _tap(tester, find.text('Simple net worth'));
      await _waitUntil(
        tester,
        () => container!.settingsRepository.current.simpleNetWorth,
        're-enabled simple net worth setting for USD thousands',
      );
      await _closeCurrencySettings(tester);
      await tester.pumpAndSettle();
      await _expectHeadline(tester, '\$7K');
      debugPrint(
        'DEVICE CHECK: USD 7054 displays as 7K; exact view remains available',
      );
      final List<Map<String, Object?>> matrixResults = <Map<String, Object?>>[];
      for (final (String currency, double value, String expected)
          in _simpleExamples) {
        final int portfolioId = currency == 'INR' ? inrPortfolio : usdPortfolio;
        final double assets = value < 0 ? 0 : value;
        final double liabilities = value < 0 ? -value : 0;
        final AssetEntity asset =
            (await container.assetRepository.getForPortfolio(portfolioId))
                .single;
        final LiabilityEntity liability =
            (await container.liabilityRepository.getForPortfolio(portfolioId))
                .single;
        await container.assetRepository.save(
          asset.copyWith(manualValue: assets),
        );
        await container.liabilityRepository.save(
          liability.copyWith(amount: liabilities),
        );
        await container.settingsRepository.setBaseCurrency(currency);
        await container.settingsRepository.setSelectedPortfolioId(portfolioId);
        await _expectHeadline(tester, expected);
        final String actual = tester.widget<Text>(_headline).data!;
        final String detailed = CurrencyUtil.format(value, currency);
        expect(actual.length, lessThanOrEqualTo(8));
        if (value.abs() >= 1000) {
          expect(actual.length, lessThan(detailed.length));
          expect(actual, isNot(contains(',')));
        }
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          _headline,
        );
        expect(
          paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: actual.length),
          ),
          hasLength(1),
          reason: 'Simple headline must fit on one line',
        );
        expect(_cardText(CurrencyUtil.format(assets, currency)), findsWidgets);
        expect(
          _cardText(CurrencyUtil.format(liabilities, currency)),
          findsWidgets,
        );
        matrixResults.add(<String, Object?>{
          'currency': currency,
          'value': value,
          'headline': actual,
          'singleLine': true,
        });
        debugPrint('SIMPLE MATRIX: $currency $value -> $actual');
      }
      binding.reportData = <String, Object?>{
        'inrCompactHeadline': '₹1.65 Cr',
        'usdCompactHeadline': '\$165.3M',
        'usdThousandsHeadline': '\$7K',
        'valueMatrix': matrixResults,
        'exactDetailsPreserved': true,
        'balanceMaskingVerified': true,
        'toggleOffVerified': true,
        'persistedAcrossRelaunch': true,
      };
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final AppContainer cleanup = container ?? await AppContainer.create();
      try {
        await _restorePreferences(preferences, original);
        for (final int portfolioId in testPortfolios) {
          expect(
            await cleanup.portfolioRepository.delete(portfolioId),
            isTrue,
            reason: 'Delete temporary test portfolio',
          );
          expect(
            await cleanup.portfolioRepository.getById(portfolioId),
            isNull,
          );
          expect(
            await cleanup.assetRepository.getForPortfolio(portfolioId),
            isEmpty,
          );
          expect(
            await cleanup.liabilityRepository.getForPortfolio(portfolioId),
            isEmpty,
          );
        }
      } finally {
        await cleanup.settingsRepository.dispose();
        await cleanup.database.close();
      }
      binding.reportData = <String, Object?>{
        ...?binding.reportData,
        'settingsRestored': true,
        'testPortfoliosRemoved': testPortfolios.length,
      };
      debugPrint('DEVICE CHECK: original settings restored; test data removed');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
