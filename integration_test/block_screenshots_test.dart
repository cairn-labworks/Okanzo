import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_language.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/main.dart' as app;
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/settings/settings_screen.dart';
import 'package:okanzo/util/screenshot_protection.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final Stopwatch timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed > const Duration(seconds: 45)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: description);
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await _wait(
    tester,
    () => target.hitTestable().evaluate().isNotEmpty,
    'tap target',
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _restore(
  SharedPreferences preferences,
  Map<String, Object?> original,
) async {
  for (final MapEntry<String, Object?> entry in original.entries) {
    final bool saved = switch (entry.value) {
      null => await preferences.remove(entry.key),
      final bool value => await preferences.setBool(entry.key, value),
      final int value => await preferences.setInt(entry.key, value),
      final String value => await preferences.setString(entry.key, value),
      final List<String> value => await preferences.setStringList(
        entry.key,
        value,
      ),
      _ => throw StateError('Unexpected preference type: ${entry.key}'),
    };
    expect(saved, isTrue, reason: entry.key);
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
    'Block screenshots defaults on, toggles live FLAG_SECURE and persists on device',
    (WidgetTester tester) async {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final Map<String, Object?> original = <String, Object?>{
        for (final String key in <String>[
          'block_screenshots',
          'app_language',
          'last_seen_version',
        ])
          key: preferences.get(key),
      };
      final List<String> checks = <String>[];
      final Map<String, Object?> report = <String, Object?>{
        'checks': checks,
        'preferencesRestored': false,
      };
      binding.reportData = report;
      void passed(String description) {
        checks.add(description);
        debugPrint('BLOCK SCREENSHOTS DEVICE PASS: $description');
      }

      AppContainer? container;
      try {
        await preferences.remove('block_screenshots');
        final SettingsRepository bootstrap = SettingsRepository(preferences);
        try {
          await bootstrap.setLanguage(AppLanguage.english);
          await bootstrap.setLastSeenVersion(AppReleaseNotes.currentVersion);
          expect(bootstrap.current.blockScreenshots, isTrue);
          await ScreenshotProtection.setEnabled(
            bootstrap.current.blockScreenshots,
          );
        } finally {
          await bootstrap.dispose();
        }

        await app.main();
        await _wait(
          tester,
          () => find.byType(HomeScreen).evaluate().isNotEmpty,
          'unlocked home screen',
        );
        container = AppScope.of(tester.element(find.byType(HomeScreen)));

        expect(container.settingsRepository.current.blockScreenshots, isTrue);
        expect(await ScreenshotProtection.isEnabled(), isTrue);
        passed(
          'default-on preference keeps live FLAG_SECURE enabled across Dart startup fixture',
        );

        await _tap(tester, find.byTooltip('Settings'));
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('App lock & screenshot protection'), findsOneWidget);
        await _tap(tester, find.text('Security'));

        SwitchListTile switchTile() => tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Block screenshots'),
        );
        expect(switchTile().value, isTrue);

        // Toggle OFF and verify live Android Window flags clear FLAG_SECURE.
        await _tap(tester, find.text('Block screenshots'));
        expect(switchTile().value, isFalse);
        expect(container.settingsRepository.current.blockScreenshots, isFalse);
        expect(await ScreenshotProtection.isEnabled(), isFalse);
        await preferences.reload();
        expect(preferences.getBool('block_screenshots'), isFalse);
        passed('toggling off clears live Android FLAG_SECURE and persists');

        // Navigate back to Home and reopen Settings -> Security.
        await _tap(tester, find.byIcon(Icons.arrow_back));
        await _tap(tester, find.byIcon(Icons.arrow_back));
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(await ScreenshotProtection.isEnabled(), isFalse);

        // Simulate app relaunch while Block screenshots is OFF.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await container.settingsRepository.dispose();
        await container.database.close();
        container = null;

        await app.main();
        await _wait(
          tester,
          () => find.byType(HomeScreen).evaluate().isNotEmpty,
          'relaunched home with Block screenshots off',
        );
        container = AppScope.of(tester.element(find.byType(HomeScreen)));
        expect(container.settingsRepository.current.blockScreenshots, isFalse);
        expect(await ScreenshotProtection.isEnabled(), isFalse);
        passed('relaunch preserves disabled FLAG_SECURE state');

        // Reopen Settings -> Security and toggle back ON.
        await _tap(tester, find.byTooltip('Settings'));
        await _tap(tester, find.text('Security'));
        expect(switchTile().value, isFalse);
        await _tap(tester, find.text('Block screenshots'));
        expect(switchTile().value, isTrue);
        expect(container.settingsRepository.current.blockScreenshots, isTrue);
        expect(await ScreenshotProtection.isEnabled(), isTrue);
        passed('toggling back on immediately restores Android FLAG_SECURE');

        // Verify 150% Arabic RTL layout on Security settings on physical phone.
        await container.settingsRepository.setLanguage(AppLanguage.arabic);
        const AppLocalizations ar = AppLocalizations(Locale('ar'));
        await tester.pumpWidget(
          AppScope(
            container: container,
            child: MediaQuery(
              data: MediaQueryData.fromView(tester.view)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: const app.OkanzoApp(),
            ),
          ),
        );
        await _wait(
          tester,
          () => find.byType(HomeScreen).evaluate().isNotEmpty,
          'large RTL home',
        );
        await _tap(tester, find.byTooltip(ar.text('Settings')));
        expect(
          find.text(ar.text('App lock & screenshot protection')),
          findsOneWidget,
        );
        await _tap(tester, find.text(ar.text('Security')));
        expect(find.text(ar.text('Block screenshots')), findsOneWidget);
        expect(
          Directionality.of(
            tester.element(find.text(ar.text('Block screenshots'))),
          ),
          TextDirection.rtl,
        );
        expect(tester.takeException(), isNull);
        passed('150% Arabic RTL Security settings render cleanly on device');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await container?.settingsRepository.dispose();
        await container?.database.close();
        await _restore(preferences, original);
        final bool restoredBlock =
            preferences.getBool('block_screenshots') ?? true;
        await ScreenshotProtection.setEnabled(restoredBlock);
        report['preferencesRestored'] = true;
      }
    },
  );
}
