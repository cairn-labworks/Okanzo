import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_language.dart';
import 'package:okanzo/domain/model/app_theme.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/domain/model/theme_mode.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/theme/app_style.dart';
import 'package:okanzo/util/screenshot_protection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/device_test_cleanup.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Sculpted and Liquid Glass retain appearance and native flows', (
    WidgetTester tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    const List<String> keys = <String>[
      'app_theme',
      'theme_mode',
      'base_currency',
      'app_lock_enabled',
      'block_screenshots',
      'hide_balances',
      'simple_net_worth',
      'app_language',
      'last_seen_version',
    ];
    final Map<String, Object?> original = <String, Object?>{
      for (final String key in keys) key: preferences.get(key),
    };
    final bool blockScreenshots =
        preferences.getBool('block_screenshots') ?? true;
    final AppContainer container = await AppContainer.create(
      preferences: preferences,
    );
    final settings = container.settingsRepository;
    int? fixtureId;

    Future<void> settle() async {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 30),
      );
    }

    Future<void> tap(Finder target) async {
      expect(target, findsWidgets);
      await tester.ensureVisible(target.first);
      await tester.tap(target.first);
      await settle();
    }

    Future<void> capture(String name) async {
      await settle();
      final Finder dialogs = find.byType(Dialog);
      final BuildContext page = tester.element(
        dialogs.evaluate().isNotEmpty
            ? dialogs.last
            : find.byType(Scaffold).last,
      );
      expect(
        ModalRoute.of(page)?.animation?.status,
        AnimationStatus.completed,
        reason: 'Capture $name after its route has finished entering.',
      );
      final AppTheme expected =
          settings.current.themeStyle == AppTheme.classic &&
              settings.current.appearanceMode == AppThemeMode.dark
          ? AppTheme.midnight
          : settings.current.themeStyle;
      expect(AppStyle.of(page).appTheme, expected, reason: name);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot(name);
    }

    Future<void> openAppearance() async {
      await tap(find.byTooltip('Settings'));
      await tap(find.text('Appearance'));
    }

    Future<void> returnHome() async {
      await tap(find.byTooltip('Back'));
      await tap(find.byTooltip('Back'));
    }

    Future<void> resetHomeScroll() async {
      final Finder scroller = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      );
      if (scroller.evaluate().isNotEmpty) {
        tester.state<ScrollableState>(scroller.first).position.jumpTo(0);
      }
      await settle();
    }

    try {
      await container.portfolioRepository.ensureDefaultPortfolio();
      fixtureId = await container.portfolioRepository.create(
        'Theme preview ${DateTime.now().millisecondsSinceEpoch}',
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (final (AssetType type, String name, double value)
          in <(AssetType, String, double)>[
            (AssetType.realEstate, 'Home value', 215000),
            (AssetType.bankDeposit, 'Bank reserve', 133500),
            (AssetType.cash, 'Cash reserve', 12000),
          ]) {
        await container.assetRepository.save(
          AssetEntity(
            portfolioId: fixtureId,
            type: type,
            name: name,
            currency: 'USD',
            manualValue: value,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await container.liabilityRepository.save(
        LiabilityEntity(
          portfolioId: fixtureId,
          type: LiabilityType.loan,
          name: 'Home loan',
          currency: 'USD',
          amount: 148000,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await settings.setAppLockEnabled(false);
      await settings.setBlockScreenshots(false);
      await settings.setHideBalances(false);
      await settings.setSimpleNetWorth(false);
      await settings.setBaseCurrency('USD');
      await settings.setLanguage(AppLanguage.english);
      await settings.setLastSeenVersion(AppReleaseNotes.currentVersion);
      await settings.setSelectedPortfolioId(fixtureId);
      await settings.setAppTheme(AppTheme.classic);
      await settings.setAppearanceMode(AppThemeMode.light);

      await tester.pumpWidget(
        AppScope(container: container, child: const app.OkanzoApp()),
      );
      await settle();
      expect(
        find.byKey(const ValueKey<String>('net-worth-headline')),
        findsOneWidget,
      );
      await binding.convertFlutterSurfaceToImage();
      await capture('original-light');
      await settings.setAppearanceMode(AppThemeMode.dark);
      await capture('original-dark');

      for (final AppTheme style in <AppTheme>[
        AppTheme.sculpted,
        AppTheme.liquidGlass,
      ]) {
        await openAppearance();
        await tap(find.text('Theme style'));
        await tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(style.displayName),
          ),
        );
        expect(settings.current.themeStyle, style);
        await returnHome();
        final String prefix = style == AppTheme.sculpted
            ? 'sculpted'
            : 'liquid-glass';

        for (final AppThemeMode mode in <AppThemeMode>[
          AppThemeMode.light,
          AppThemeMode.dark,
        ]) {
          await openAppearance();
          await tap(find.byKey(ValueKey<AppThemeMode>(mode)));
          expect(settings.current.themeStyle, style);
          expect(settings.current.appearanceMode, mode);
          if (style == AppTheme.liquidGlass) {
            await capture('$prefix-${mode.name}-settings');
          }
          await returnHome();
          final BuildContext home = tester.element(find.byType(HomeScreen));
          expect(AppStyle.of(home).appTheme, style);
          expect(
            Theme.of(home).brightness,
            mode == AppThemeMode.dark ? Brightness.dark : Brightness.light,
          );
          if (find.text('Cash reserve').evaluate().isNotEmpty) {
            await tap(find.text('Cash'));
          }
          await resetHomeScroll();
          await capture('$prefix-${mode.name}-home');

          if (style == AppTheme.liquidGlass) {
            await tap(find.text('Cash'));
            await tap(find.text('Cash reserve'));
            await capture('$prefix-${mode.name}-details');
            await tap(find.text('Edit asset'));
            await capture('$prefix-${mode.name}-form');
            await tester.pageBack();
            await settle();
          }
        }
      }
    } finally {
      await runDeviceTestCleanup(<DeviceTestCleanupStep>[
        (
          'restore native screenshot protection',
          () => ScreenshotProtection.setEnabled(blockScreenshots),
        ),
        for (final entry in original.entries)
          (
            'restore ${entry.key}',
            () => restoreDeviceTestPreference(
              preferences,
              entry.key,
              entry.value,
            ),
          ),
        (
          'unmount test widgets',
          () => tester.pumpWidget(const SizedBox.shrink()),
        ),
        ('settle test widgets', settle),
        if (fixtureId case final int id) ...<DeviceTestCleanupStep>[
          (
            'delete test portfolio',
            () async =>
                expect(await container.portfolioRepository.delete(id), isTrue),
          ),
          (
            'verify test assets removed',
            () async => expect(
              await container.assetRepository.getForPortfolio(id),
              isEmpty,
            ),
          ),
          (
            'verify test liabilities removed',
            () async => expect(
              await container.liabilityRepository.getForPortfolio(id),
              isEmpty,
            ),
          ),
        ],
        ('dispose settings', settings.dispose),
        ('close database', container.database.close),
      ]);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
