import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/dao/portfolio_dao.dart';
import 'package:okanzo/data/local/entity/portfolio_entity.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_language.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/home/net_worth_card.dart';
import 'package:okanzo/ui/portfolio/portfolio_screen.dart';
import 'package:okanzo/ui/statistics/statistics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition,
  String description, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed >= timeout) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: description);
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty &&
      find.byType(Scrollable).evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _waitUntil(
    tester,
    () => finder.hitTestable().evaluate().isNotEmpty,
    'hit-testable target $finder',
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

AppContainer _container(WidgetTester tester) =>
    AppScope.of(tester.element(find.byType(HomeScreen)));

Finder _homeTitle(String name) => find.descendant(
  of: find.descendant(
    of: find.byType(HomeScreen),
    matching: find.byType(AppBar),
  ),
  matching: find.text(name),
);

Finder _statsTitle(String name) => find.descendant(
  of: find.descendant(
    of: find.byType(StatisticsScreen),
    matching: find.byType(AppBar),
  ),
  matching: find.text(name),
);

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

  testWidgets(
    'home shows default portfolio on launch and updates when default changes',
    (WidgetTester tester) async {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final Map<String, Object?> originalPrefs = <String, Object?>{
        for (final String key in <String>[
          'app_language',
          'app_lock_enabled',
          'last_seen_version',
          'selected_portfolio_id',
        ])
          key: preferences.get(key),
      };

      AppContainer? container;
      List<int> preExistingPortfolioIds = const <int>[];
      int? originalDefaultId;
      final List<int> createdPortfolioIds = <int>[];
      bool seededInitialPortfolio = false;

      try {
        final SettingsRepository setup = SettingsRepository(preferences);
        try {
          await setup.setLanguage(AppLanguage.english);
          await setup.setAppLockEnabled(false);
          await setup.setLastSeenVersion(AppReleaseNotes.currentVersion);
        } finally {
          await setup.dispose();
        }

        // Seed a legacy selected_portfolio_id in SharedPreferences to verify
        // cold launch still opens the Default portfolio rather than stale prefs.
        final AppContainer inspect = await AppContainer.create();
        try {
          final List<PortfolioEntity> existing = await inspect
              .portfolioRepository
              .getAll();
          if (existing.isEmpty) {
            await inspect.portfolioRepository.ensureDefaultPortfolio();
            seededInitialPortfolio = true;
          }
          preExistingPortfolioIds = (await inspect.portfolioRepository.getAll())
              .map((PortfolioEntity p) => p.id)
              .toList();
          originalDefaultId =
              (await inspect.portfolioRepository.getDefault())?.id;
        } finally {
          await inspect.settingsRepository.dispose();
          await inspect.database.close();
        }
        expect(originalDefaultId, isNotNull);

        await app.main();
        await _waitUntil(
          tester,
          () => find.byType(NetWorthCard).evaluate().isNotEmpty,
          'unlocked home screen',
        );
        container = _container(tester);

        final PortfolioEntity initialDefault = (await container
            .portfolioRepository
            .getDefault())!;
        expect(initialDefault.id, originalDefaultId);
        await _waitUntil(
          tester,
          () => _homeTitle(initialDefault.name).evaluate().isNotEmpty,
          'initial default portfolio on Home',
        );
        debugPrint(
          'DEVICE CHECK: Home opened with initial default "${initialDefault.name}"',
        );

        // Create a temporary secondary portfolio and select initialDefault via
        // the Home dropdown so active session has an explicit selection.
        final String suffix = '${DateTime.now().millisecondsSinceEpoch}';
        final String tempFirstName = 'Temp Old $suffix';
        final String tempDefaultName = 'Temp Default $suffix';
        final int tempFirstId = await container.portfolioRepository.create(
          tempFirstName,
        );
        createdPortfolioIds.add(tempFirstId);
        await tester.pumpAndSettle();

        await _tap(tester, find.byTooltip('Switch portfolio'));
        await _tap(tester, find.text(tempFirstName).last);
        await _waitUntil(
          tester,
          () => _homeTitle(tempFirstName).evaluate().isNotEmpty,
          'switched to $tempFirstName on Home',
        );
        expect(
          container.settingsRepository.current.selectedPortfolioId,
          tempFirstId,
        );

        // Open Portfolios tab, create a new portfolio via UI, and set it as Default.
        await _tap(tester, find.text('Portfolios'));
        await _tap(
          tester,
          find.descendant(
            of: find.byType(PortfolioScreen),
            matching: find.text('New'),
          ),
        );
        await tester.enterText(find.byType(TextField), tempDefaultName);
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Create'));
        await _waitUntil(
          tester,
          () => find.text(tempDefaultName).evaluate().isNotEmpty,
          'created $tempDefaultName in Portfolios screen',
        );
        final PortfolioEntity createdDefault =
            (await container.portfolioRepository.getAll()).singleWhere(
              (PortfolioEntity p) => p.name == tempDefaultName,
            );
        createdPortfolioIds.add(createdDefault.id);

        final Finder targetCard = find.ancestor(
          of: find.text(tempDefaultName),
          matching: find.byType(Card),
        );
        await _tap(
          tester,
          find.descendant(of: targetCard, matching: find.byTooltip('More')),
        );
        await _tap(tester, find.text('Set as default'));
        await _waitUntil(
          tester,
          () =>
              container!.settingsRepository.current.selectedPortfolioId == null,
          'cleared session override after Set as default',
        );

        // Verify Home and Statistics immediately switch to the new Default portfolio.
        await _tap(tester, find.text('Home'));
        await _waitUntil(
          tester,
          () => _homeTitle(tempDefaultName).evaluate().isNotEmpty,
          'Home switched to new default $tempDefaultName',
        );
        expect(_homeTitle(tempFirstName), findsNothing);
        debugPrint(
          'DEVICE CHECK: Home switched immediately to new default "$tempDefaultName"',
        );

        await _tap(tester, find.text('Statistics'));
        await _waitUntil(
          tester,
          () => _statsTitle(tempDefaultName).evaluate().isNotEmpty,
          'Statistics switched to new default $tempDefaultName',
        );

        // Switch to non-default tempFirstName during session, then relaunch app
        // and verify Home opens on Default (tempDefaultName) by default.
        await _tap(tester, find.text('Home'));
        await _tap(tester, find.byTooltip('Switch portfolio'));
        await _tap(tester, find.text(tempFirstName).last);
        await _waitUntil(
          tester,
          () => _homeTitle(tempFirstName).evaluate().isNotEmpty,
          'session switch to non-default $tempFirstName',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await container.settingsRepository.dispose();
        await container.database.close();
        container = null;
        await preferences.setInt('selected_portfolio_id', tempFirstId);
        await preferences.reload();

        await app.main();
        await _waitUntil(
          tester,
          () => find.byType(NetWorthCard).evaluate().isNotEmpty,
          'relaunched home screen',
        );
        container = _container(tester);
        await _waitUntil(
          tester,
          () => _homeTitle(tempDefaultName).evaluate().isNotEmpty,
          'Home opened Default portfolio $tempDefaultName after relaunch',
        );
        expect(_homeTitle(tempFirstName), findsNothing);
        debugPrint(
          'DEVICE CHECK: Relaunch opened Default portfolio "$tempDefaultName" on Home',
        );

        binding.reportData = <String, Object?>{
          'initialDefaultShown': true,
          'updatedDefaultShownOnHomeAndStats': true,
          'relaunchOpenedDefaultPortfolio': true,
          'seededInitialPortfolio': seededInitialPortfolio,
        };
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        final AppContainer cleanup = container ?? await AppContainer.create();
        try {
          final PortfolioDao dao = PortfolioDao(cleanup.database);
          if (originalDefaultId != null) {
            await dao.setDefault(originalDefaultId);
          }
          for (final int id in createdPortfolioIds) {
            await dao.deleteById(id);
          }
          await _restorePreferences(preferences, originalPrefs);
          final List<int> remainingIds =
              (await cleanup.portfolioRepository.getAll())
                  .map((PortfolioEntity p) => p.id)
                  .toList();
          expect(remainingIds.toSet(), preExistingPortfolioIds.toSet());
          expect(
            (await cleanup.portfolioRepository.getDefault())?.id,
            originalDefaultId,
          );
        } finally {
          await cleanup.settingsRepository.dispose();
          await cleanup.database.close();
        }
        binding.reportData = <String, Object?>{
          ...?binding.reportData,
          'originalDefaultRestored': true,
          'temporaryPortfoliosRemoved': createdPortfolioIds.length,
        };
        debugPrint(
          'DEVICE CHECK: original default portfolio & preferences restored; temporary portfolios removed',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
