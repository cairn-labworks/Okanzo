import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:okanzo/data/backup/backup_repository.dart';
import 'package:okanzo/data/local/entity/portfolio_entity.dart';
import 'package:okanzo/data/repository/asset_repository.dart';
import 'package:okanzo/data/repository/currency_converter.dart';
import 'package:okanzo/data/repository/fx_repository.dart';
import 'package:okanzo/data/repository/liability_repository.dart';
import 'package:okanzo/data/repository/portfolio_repository.dart';
import 'package:okanzo/data/repository/settings_repository.dart';
import 'package:okanzo/di/app_container.dart';
import 'package:okanzo/domain/model/app_language.dart';
import 'package:okanzo/domain/model/release_notes.dart';
import 'package:okanzo/l10n/app_localizations.dart';
import 'package:okanzo/main.dart';
import 'package:okanzo/ui/settings/settings_screen.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PortfolioRepository extends Fake implements PortfolioRepository {
  @override
  Stream<List<PortfolioEntity>> observeAll() =>
      Stream<List<PortfolioEntity>>.value(const <PortfolioEntity>[]);

  @override
  Future<int> ensureDefaultPortfolio([
    String defaultName = 'My Portfolio',
  ]) async => 1;
}

class _FxRepository extends Fake implements FxRepository {
  @override
  Stream<CurrencyConverter> get converter =>
      Stream<CurrencyConverter>.value(const CurrencyConverter.empty());

  @override
  Future<Result<void>> ensureFreshRates([int maxAgeMillis = 0]) async =>
      Result<void>.success(null);

  @override
  Future<int?> latestTimestamp() async => null;
}

class _AssetRepository extends Fake implements AssetRepository {}

class _LiabilityRepository extends Fake implements LiabilityRepository {}

class _BackupRepository extends Fake implements BackupRepository {}

class _Container extends Fake implements AppContainer {
  _Container(this.settingsRepository);

  @override
  final SettingsRepository settingsRepository;

  @override
  final PortfolioRepository portfolioRepository = _PortfolioRepository();

  @override
  final FxRepository fxRepository = _FxRepository();

  @override
  final AssetRepository assetRepository = _AssetRepository();

  @override
  final LiabilityRepository liabilityRepository = _LiabilityRepository();

  @override
  final BackupRepository backupRepository = _BackupRepository();
}

class _RejectingPreferences extends Fake implements SharedPreferences {
  _RejectingPreferences({this.throwOnWrite = false});

  final bool throwOnWrite;
  String? cachedLanguage = 'en';
  int reloads = 0;

  @override
  String? getString(String key) => switch (key) {
    'app_language' => cachedLanguage,
    'last_seen_version' => AppReleaseNotes.currentVersion,
    _ => null,
  };

  @override
  bool? getBool(String key) => null;

  @override
  int? getInt(String key) => null;

  @override
  List<String>? getStringList(String key) => null;

  @override
  Future<bool> setString(String key, String value) async {
    cachedLanguage = value;
    if (throwOnWrite) throw StateError('Storage unavailable');
    return false;
  }

  @override
  Future<bool> remove(String key) async {
    cachedLanguage = null;
    return false;
  }

  @override
  Future<void> reload() async {
    reloads++;
    cachedLanguage = 'en';
  }
}

class _DelayedSettingsRepository extends SettingsRepository {
  _DelayedSettingsRepository(super.preferences);

  final Completer<void> pending = Completer<void>();
  int writes = 0;

  @override
  Future<void> setLanguage(AppLanguage language) async {
    writes++;
    await pending.future;
    await super.setLanguage(language);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late SettingsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'JPY',
      'hide_balances': true,
      'last_seen_version': AppReleaseNotes.currentVersion,
    });
    preferences = await SharedPreferences.getInstance();
    repository = SettingsRepository(preferences);
    addTearDown(repository.dispose);
  });

  test(
    'device language is the default, including obsolete preference values',
    () async {
      expect(repository.current.language, AppLanguage.system);
      expect(AppLocalizations.localeForLanguage(AppLanguage.system), isNull);
      await preferences.setString('app_language', 'removed-language');
      expect(repository.current.language, AppLanguage.system);
    },
  );

  test('every supported locale has exactly one selectable language', () {
    final Iterable<AppLanguage> languages = AppLanguage.values.where(
      (AppLanguage value) => value != AppLanguage.system,
    );
    expect(
      languages.map(AppLocalizations.localeForLanguage).toList(),
      AppLocalizations.supportedLocales,
    );
    for (final AppLanguage language in AppLanguage.values) {
      expect(AppLanguage.fromName(language.storageName), language);
      expect(language.displayName, isNotEmpty);
    }
  });

  test(
    'each explicit language persists without changing unrelated preferences',
    () async {
      for (final AppLanguage language in AppLanguage.values.skip(1)) {
        await repository.setLanguage(language);
        await preferences.reload();
        final SettingsRepository reopened = SettingsRepository(preferences);
        expect(reopened.current.language, language);
        expect(reopened.current.baseCurrency, 'JPY');
        expect(reopened.current.hideBalances, isTrue);
        await reopened.dispose();
      }
    },
  );

  test(
    'returning to device language clears the override across restarts',
    () async {
      await repository.setLanguage(AppLanguage.spanish);
      await repository.setLanguage(AppLanguage.system);
      await preferences.reload();
      expect(preferences.containsKey('app_language'), isFalse);
      final SettingsRepository reopened = SettingsRepository(preferences);
      addTearDown(reopened.dispose);
      expect(reopened.current.language, AppLanguage.system);
    },
  );

  test('settings subscribers receive saved language changes', () async {
    final List<AppLanguage> received = <AppLanguage>[];
    final StreamSubscription<AppSettings> subscription = repository.settings
        .listen((AppSettings value) => received.add(value.language));
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    await repository.setLanguage(AppLanguage.arabic);
    await Future<void>.delayed(Duration.zero);
    await repository.setLanguage(AppLanguage.system);
    await Future<void>.delayed(Duration.zero);
    expect(received, <AppLanguage>[
      AppLanguage.system,
      AppLanguage.arabic,
      AppLanguage.system,
    ]);
  });

  for (final bool throwOnWrite in <bool>[false, true]) {
    test(
      'failed language write restores the preference cache (throws: $throwOnWrite)',
      () async {
        final _RejectingPreferences rejected = _RejectingPreferences(
          throwOnWrite: throwOnWrite,
        );
        final SettingsRepository failing = SettingsRepository(rejected);
        addTearDown(failing.dispose);
        await expectLater(
          failing.setLanguage(AppLanguage.spanish),
          throwsStateError,
        );
        expect(failing.current.language, AppLanguage.english);
        expect(rejected.reloads, 1);
      },
    );
  }

  test(
    'a failed reset to device language retains the stored override',
    () async {
      final _RejectingPreferences rejected = _RejectingPreferences();
      final SettingsRepository failing = SettingsRepository(rejected);
      addTearDown(failing.dispose);
      await expectLater(
        failing.setLanguage(AppLanguage.system),
        throwsStateError,
      );
      expect(failing.current.language, AppLanguage.english);
    },
  );

  Future<void> openSettings(
    WidgetTester tester,
    SettingsRepository settings,
  ) async {
    await tester.pumpWidget(
      AppScope(container: _Container(settings), child: const OkanzoApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    final BuildContext context = tester.element(find.byType(SettingsScreen));
    await tester.tap(find.text('App language'.tr(context)));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  }

  Future<void> selectLanguage(
    WidgetTester tester,
    AppLanguage language, {
    bool settle = true,
  }) async {
    final Finder option = find.byKey(ValueKey<AppLanguage>(language));
    await tester.scrollUntilVisible(
      option,
      150,
      scrollable: find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      ),
    );
    await Scrollable.ensureVisible(tester.element(option), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(option);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
    'picker changes the actual app immediately and preserves the settings route',
    (WidgetTester tester) async {
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.localesTestValue = <Locale>[
        const Locale('en'),
      ];
      final String? original = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = original);
      Intl.defaultLocale = 'en_US';
      await openSettings(tester, repository);
      expect(find.text('Use device language'), findsOneWidget);
      final Element settingsPage = tester.element(find.byType(SettingsScreen));

      await openPicker(tester);
      final ListView list = tester.widget<ListView>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(ListView),
        ),
      );
      expect(list.childrenDelegate.estimatedChildCount, 22);
      await selectLanguage(tester, AppLanguage.spanish);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
      expect(tester.element(find.byType(SettingsScreen)), same(settingsPage));
      expect(repository.current.language, AppLanguage.spanish);
      expect(Intl.defaultLocale, 'en_US');
      expect(repository.current.baseCurrency, 'JPY');

      await openPicker(tester);
      await selectLanguage(tester, AppLanguage.arabic);
      expect(
        Directionality.of(tester.element(find.byType(SettingsScreen))),
        TextDirection.rtl,
      );
      await openPicker(tester);
      await selectLanguage(tester, AppLanguage.english);
      expect(find.text('Settings'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(SettingsScreen))),
        TextDirection.ltr,
      );
    },
  );

  testWidgets(
    'saved override survives device changes and reset restores automatic selection',
    (WidgetTester tester) async {
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.localesTestValue = <Locale>[
        const Locale('fr'),
      ];
      await repository.setLanguage(AppLanguage.spanish);
      await openSettings(tester, repository);
      expect(find.text('Ajustes'), findsOneWidget);
      tester.binding.platformDispatcher.localesTestValue = <Locale>[
        const Locale('de'),
      ];
      await tester.pumpAndSettle();
      expect(find.text('Ajustes'), findsOneWidget);
      await openPicker(tester);
      await selectLanguage(tester, AppLanguage.system);
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(repository.current.language, AppLanguage.system);
      tester.binding.platformDispatcher.localesTestValue = <Locale>[
        const Locale('fr'),
      ];
      await tester.pumpAndSettle();
      expect(find.text('Paramètres'), findsOneWidget);
    },
  );

  testWidgets(
    'closing the picker without selecting leaves language unchanged',
    (WidgetTester tester) async {
      await openSettings(tester, repository);
      await openPicker(tester);
      final BuildContext context = tester.element(find.byType(AlertDialog));
      await tester.tap(find.widgetWithText(TextButton, 'Close'.tr(context)));
      await tester.pumpAndSettle();
      expect(repository.current.language, AppLanguage.system);
      expect(preferences.containsKey('app_language'), isFalse);
    },
  );

  testWidgets('storage failures keep the picker open with a visible error', (
    WidgetTester tester,
  ) async {
    final SettingsRepository failing = SettingsRepository(
      _RejectingPreferences(),
    );
    addTearDown(failing.dispose);
    await openSettings(tester, failing);
    await openPicker(tester);
    await selectLanguage(tester, AppLanguage.spanish);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining("Couldn't save app language:"), findsOneWidget);
    expect(failing.current.language, AppLanguage.english);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
  });

  testWidgets(
    'language options are disabled while saving to prevent conflicting writes',
    (WidgetTester tester) async {
      final _DelayedSettingsRepository delayed = _DelayedSettingsRepository(
        preferences,
      );
      addTearDown(delayed.dispose);
      await openSettings(tester, delayed);
      await openPicker(tester);
      await selectLanguage(tester, AppLanguage.spanish, settle: false);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      for (final RadioListTile<AppLanguage> option
          in tester.widgetList<RadioListTile<AppLanguage>>(
            find.byType(RadioListTile<AppLanguage>),
          )) {
        expect(option.enabled, isFalse);
      }
      expect(delayed.writes, 1);
      delayed.pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(delayed.current.language, AppLanguage.spanish);
    },
  );
}
