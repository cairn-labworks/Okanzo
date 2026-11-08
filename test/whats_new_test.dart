import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:okanzo/ui/components/type_icons.dart';
import 'package:okanzo/ui/components/whats_new_dialog.dart';
import 'package:okanzo/ui/lock/lock_screen.dart';
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
  String? cachedVersion = '1.2.3';
  int reloads = 0;

  @override
  String? getString(String key) =>
      key == 'last_seen_version' ? cachedVersion : null;

  @override
  bool? getBool(String key) => null;

  @override
  int? getInt(String key) => null;

  @override
  List<String>? getStringList(String key) => null;

  @override
  Future<bool> setString(String key, String value) async {
    cachedVersion = value;
    if (throwOnWrite) throw StateError('Storage unavailable');
    return false;
  }

  @override
  Future<void> reload() async {
    reloads++;
    cachedVersion = '1.2.3';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late SettingsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'USD',
    });
    preferences = await SharedPreferences.getInstance();
    repository = SettingsRepository(preferences);
    addTearDown(repository.dispose);
  });

  group('AppReleaseNotes', () {
    test(
      'currentVersion matches pubspec.yaml and has localized highlights',
      () {
        final String pubspec = File('pubspec.yaml').readAsStringSync();
        final RegExpMatch? match = RegExp(
          r'^version:\s*([^\s+]+)',
          multiLine: true,
        ).firstMatch(pubspec);
        expect(match, isNotNull);
        expect(AppReleaseNotes.currentVersion, match!.group(1));

        final ReleaseNotes? current = AppReleaseNotes.forVersion(
          AppReleaseNotes.currentVersion,
        );
        expect(current, isNotNull);
        expect(current!.highlights, isNotEmpty);

        for (final ReleaseHighlight highlight in current.highlights) {
          expect(highlight.title.trim(), isNotEmpty);
          expect(highlight.description.trim(), isNotEmpty);
          for (final Locale locale in AppLocalizations.supportedLocales.skip(
            1,
          )) {
            final AppLocalizations strings = AppLocalizations(locale);
            expect(
              strings.text(highlight.title),
              isNot(highlight.title),
              reason: '$locale title: ${highlight.title}',
            );
            expect(
              strings.text(highlight.description),
              isNot(highlight.description),
              reason: '$locale description: ${highlight.description}',
            );
          }
        }
      },
    );

    test('every highlight icon maps to a unique IconData and releases use distinct feature icons', () {
      final Set<IconData> mappedIcons = ReleaseHighlightIcon.values
          .map(releaseHighlightIcon)
          .toSet();
      expect(mappedIcons.length, ReleaseHighlightIcon.values.length);

      for (final ReleaseNotes release in AppReleaseNotes.all) {
        final Set<ReleaseHighlightIcon> usedInRelease = release.highlights
            .map((ReleaseHighlight h) => h.icon)
            .toSet();
        expect(
          usedInRelease.length,
          release.highlights.length,
          reason:
              'Release ${release.version} should use distinct feature icons for each highlight',
        );
      }
    });

    test('normalizes version tags and build suffixes', () {
      expect(AppReleaseNotes.normalizeVersion(' v1.3.0+9 '), '1.3.0');
      expect(AppReleaseNotes.normalizeVersion('V1.3.0'), '1.3.0');
      expect(AppReleaseNotes.normalizeVersion('1.3.0'), '1.3.0');
    });

    test(
      'shouldShowWhatsNew detects fresh installs, updates, and seen versions',
      () {
        expect(
          AppReleaseNotes.shouldShowWhatsNew(
            lastSeenVersion: null,
            installedVersion: '1.3.0',
          ),
          isTrue,
        );
        expect(
          AppReleaseNotes.shouldShowWhatsNew(
            lastSeenVersion: '',
            installedVersion: '1.3.0',
          ),
          isTrue,
        );
        expect(
          AppReleaseNotes.shouldShowWhatsNew(
            lastSeenVersion: '1.2.3',
            installedVersion: '1.3.0',
          ),
          isTrue,
        );
        expect(
          AppReleaseNotes.shouldShowWhatsNew(
            lastSeenVersion: '1.1.0',
            installedVersion: '1.3.0',
          ),
          isTrue,
        );
        expect(
          AppReleaseNotes.shouldShowWhatsNew(
            lastSeenVersion: '1.3.0',
            installedVersion: 'v1.3.0+9',
          ),
          isFalse,
        );
        expect(
          AppReleaseNotes.shouldShowWhatsNew(
            lastSeenVersion: null,
            installedVersion: '0.0.0',
          ),
          isFalse,
        );
        expect(
          AppReleaseNotes.shouldShowWhatsNew(
            lastSeenVersion: null,
            installedVersion: '1.3.0',
            releases: const <ReleaseNotes>[
              ReleaseNotes(version: '1.3.0', highlights: <ReleaseHighlight>[]),
            ],
          ),
          isFalse,
        );
      },
    );
  });

  group('SettingsRepository.lastSeenVersion', () {
    test('persists normalized version and notifies subscribers', () async {
      expect(repository.current.lastSeenVersion, isNull);
      final List<String?> versions = <String?>[];
      final StreamSubscription<AppSettings> sub = repository.settings.listen(
        (AppSettings value) => versions.add(value.lastSeenVersion),
      );
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      await repository.setLastSeenVersion('v1.3.0+9');
      await Future<void>.delayed(Duration.zero);
      expect(repository.current.lastSeenVersion, '1.3.0');
      expect(versions, <String?>[null, '1.3.0']);

      await preferences.reload();
      final SettingsRepository reopened = SettingsRepository(preferences);
      addTearDown(reopened.dispose);
      expect(reopened.current.lastSeenVersion, '1.3.0');
      expect(reopened.current.baseCurrency, 'USD');
    });

    test(
      'rejects empty versions and reloads on failed storage writes',
      () async {
        await expectLater(
          repository.setLastSeenVersion('   '),
          throwsArgumentError,
        );

        for (final bool throwOnWrite in <bool>[false, true]) {
          final _RejectingPreferences rejected = _RejectingPreferences(
            throwOnWrite: throwOnWrite,
          );
          final SettingsRepository failing = SettingsRepository(rejected);
          addTearDown(failing.dispose);
          await expectLater(
            failing.setLastSeenVersion('1.3.0'),
            throwsStateError,
          );
          expect(failing.current.lastSeenVersion, '1.2.3');
          expect(rejected.reloads, 1);
        }
      },
    );
  });

  group('WhatsNewDialog widget integration', () {
    testWidgets(
      'shows pop-up on first launch of a version and does not repeat after dismissal',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          AppScope(container: _Container(repository), child: const OkanzoApp()),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WhatsNewDialog), findsOneWidget);
        expect(
          find.text("What's new in ${AppReleaseNotes.currentVersion}"),
          findsOneWidget,
        );
        for (final ReleaseHighlight highlight
            in AppReleaseNotes.current.highlights) {
          expect(find.text(highlight.title), findsOneWidget);
          expect(find.text(highlight.description), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(WhatsNewDialog),
              matching: find.byIcon(releaseHighlightIcon(highlight.icon)),
            ),
            findsOneWidget,
          );
        }

        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();

        expect(find.byType(WhatsNewDialog), findsNothing);
        expect(
          repository.current.lastSeenVersion,
          AppReleaseNotes.currentVersion,
        );

        // Re-launching on the same version should not show the dialog again.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          AppScope(container: _Container(repository), child: const OkanzoApp()),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WhatsNewDialog), findsNothing);
      },
    );

    testWidgets(
      'shows latest release highlights when upgrading from an older version',
      (WidgetTester tester) async {
        await repository.setLastSeenVersion('1.2.3');
        await tester.pumpWidget(
          AppScope(container: _Container(repository), child: const OkanzoApp()),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WhatsNewDialog), findsOneWidget);
        expect(
          find.text("What's new in ${AppReleaseNotes.currentVersion}"),
          findsOneWidget,
        );

        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
        expect(find.byType(WhatsNewDialog), findsNothing);
        expect(
          repository.current.lastSeenVersion,
          AppReleaseNotes.currentVersion,
        );
      },
    );

    testWidgets('waits behind AppLockGate when app lock is enabled', (
      WidgetTester tester,
    ) async {
      await repository.setAppLockEnabled(true);
      await tester.pumpWidget(
        AppScope(container: _Container(repository), child: const OkanzoApp()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(WhatsNewDialog), findsNothing);

      await repository.setAppLockEnabled(false);
      await tester.pumpAndSettle();

      expect(find.byType(LockScreen), findsNothing);
      expect(find.byType(WhatsNewDialog), findsOneWidget);
    });

    testWidgets(
      'can be reopened anytime from Settings -> About and renders localized text',
      (WidgetTester tester) async {
        await repository.setLastSeenVersion(AppReleaseNotes.currentVersion);
        await repository.setLanguage(AppLanguage.spanish);

        await tester.pumpWidget(
          AppScope(container: _Container(repository), child: const OkanzoApp()),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WhatsNewDialog), findsNothing);

        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        await tester.tap(find.text('Acerca de'));
        await tester.pumpAndSettle();

        final Finder whatsNewRow = find.text('Novedades');
        await tester.scrollUntilVisible(
          whatsNewRow,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Versión ${AppReleaseNotes.currentVersion} · Código abierto (MIT)',
          ),
          findsOneWidget,
        );

        await tester.tap(whatsNewRow);
        await tester.pumpAndSettle();

        expect(find.byType(WhatsNewDialog), findsOneWidget);
        expect(
          find.text('Novedades en ${AppReleaseNotes.currentVersion}'),
          findsOneWidget,
        );
        expect(
          find.text(
            const AppLocalizations(Locale('es'))
                .text(AppReleaseNotes.current.highlights.first.title),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Entendido'));
        await tester.pumpAndSettle();
        expect(find.byType(WhatsNewDialog), findsNothing);
      },
    );
  });
}
