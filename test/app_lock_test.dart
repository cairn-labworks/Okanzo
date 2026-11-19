import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okanzo/data/backup/backup_repository.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/data/local/entity/portfolio_entity.dart';
import 'package:okanzo/data/remote/stock/stock_search_service.dart';
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
import 'package:okanzo/ui/asset/asset_edit_screen.dart';
import 'package:okanzo/ui/components/form_components.dart';
import 'package:okanzo/ui/components/whats_new_dialog.dart';
import 'package:okanzo/ui/home/home_screen.dart';
import 'package:okanzo/ui/liability/liability_edit_screen.dart';
import 'package:okanzo/ui/lock/lock_screen.dart';
import 'package:okanzo/ui/navigation/app_shell.dart';
import 'package:okanzo/ui/settings/settings_screen.dart';
import 'package:okanzo/util/app_lock_coordinator.dart';
import 'package:okanzo/util/backup_file_picker.dart';
import 'package:okanzo/util/biometric_authenticator.dart';
import 'package:okanzo/util/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_biometric_authenticator.dart';

class _Portfolios extends Fake implements PortfolioRepository {
  @override
  Stream<List<PortfolioEntity>> observeAll() =>
      Stream<List<PortfolioEntity>>.value(const <PortfolioEntity>[
        PortfolioEntity(
          id: 1,
          name: 'Synthetic portfolio',
          isDefault: true,
          createdAt: 0,
          updatedAt: 0,
        ),
      ]);

  @override
  Future<int> ensureDefaultPortfolio([
    String defaultName = 'My Portfolio',
  ]) async => 1;
}

class _Rates extends Fake implements FxRepository {
  int refreshes = 0;

  @override
  Stream<CurrencyConverter> get converter =>
      Stream<CurrencyConverter>.value(const CurrencyConverter.empty());

  @override
  Future<Result<void>> ensureFreshRates([int maxAgeMillis = 0]) async {
    refreshes++;
    return Result<void>.success(null);
  }

  @override
  Future<int?> latestTimestamp() async => null;
}

class _Assets extends Fake implements AssetRepository {
  @override
  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<AssetEntity>>.value(const <AssetEntity>[]);

  @override
  Future<List<AssetEntity>> getForPortfolio(int portfolioId) async =>
      const <AssetEntity>[];
}

class _Liabilities extends Fake implements LiabilityRepository {
  @override
  Stream<List<LiabilityEntity>> observeForPortfolio(int portfolioId) =>
      Stream<List<LiabilityEntity>>.value(const <LiabilityEntity>[]);

  @override
  Future<List<LiabilityEntity>> getForPortfolio(int portfolioId) async =>
      const <LiabilityEntity>[];
}

class _Backups extends Fake implements BackupRepository {
  @override
  Future<Uint8List> export(List<int> portfolioIds, String password) async =>
      Uint8List.fromList(<int>[1, 2, 3]);
}

class _Search extends Fake implements StockSearchService {}

final class _PickedFile extends PlatformFile {
  @override
  String get name => 'synthetic.okanzo';
  @override
  Uri get uri => Uri.parse('memory:synthetic.okanzo');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int lengthSync() => 3;
  @override
  Future<int> length() async => 3;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List(3);
  @override
  Stream<Uint8List> readAsByteStream() => Stream<Uint8List>.value(Uint8List(3));
}

class _Picker implements BackupFilePicker {
  Completer<PlatformFile?>? picking;
  Completer<Uri?>? saving;
  int saves = 0;

  @override
  Future<PlatformFile?> pickFile({required String dialogTitle}) =>
      picking!.future;

  @override
  Future<Uri?> saveFile({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
  }) {
    saves++;
    return saving!.future;
  }
}

class _Container extends Fake implements AppContainer {
  _Container(this.settingsRepository);

  DateTime time = DateTime(2026, 1, 1);
  final FakeBiometricAuthenticator authenticator = FakeBiometricAuthenticator();
  @override
  late final AppLockCoordinator appLock = AppLockCoordinator(
    authenticator: authenticator,
    now: () => time,
  );
  @override
  final _Picker backupFilePicker = _Picker();
  @override
  final StockSearchService stockSearchService = _Search();
  @override
  final SettingsRepository settingsRepository;
  @override
  final PortfolioRepository portfolioRepository = _Portfolios();
  @override
  final _Rates fxRepository = _Rates();
  @override
  final AssetRepository assetRepository = _Assets();
  @override
  final LiabilityRepository liabilityRepository = _Liabilities();
  @override
  final BackupRepository backupRepository = _Backups();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _input(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (Widget widget) => widget is LabeledTextField && widget.label == label,
  ),
  matching: find.byType(TextField),
);

void main({
  Future<void> Function(WidgetTester tester, String name)? capture,
  bool deviceViewport = false,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Container container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_currency': 'USD',
      'last_seen_version': AppReleaseNotes.currentVersion,
    });
    final SettingsRepository settings = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    addTearDown(settings.dispose);
    container = _Container(settings);
    addTearDown(container.appLock.dispose);
  });

  Future<void> start(
    WidgetTester tester, {
    bool locked = false,
    bool authenticated = false,
  }) async {
    if (!deviceViewport) {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await container.settingsRepository.setAppLockEnabled(locked);
    if (authenticated) container.appLock.markUnlocked();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey<String>('app-lock-evidence'),
        child: AppScope(container: container, child: const OkanzoApp()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unlock(WidgetTester tester) async {
    container.authenticator.result = BiometricResult.success;
    await _tap(tester, find.text('Unlock'));
    container.authenticator.result = BiometricResult.cancelled;
  }

  Future<void> settings(WidgetTester tester, String category) async {
    await _tap(tester, find.byTooltip('Settings'));
    await _tap(tester, find.text(category));
  }

  void pause(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('cold lock defers the shell, FX and release highlights', (
    WidgetTester tester,
  ) async {
    await container.settingsRepository.setLastSeenVersion('0.0.0');
    await start(tester, locked: true);
    expect(find.byType(AppShell, skipOffstage: false), findsNothing);
    expect(find.byType(WhatsNewDialog), findsNothing);
    expect(container.fxRepository.refreshes, 0);
    expect(container.authenticator.reasons, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(container.authenticator.reasons, hasLength(1));
    pause(tester);
    expect(container.authenticator.reasons, hasLength(1));
    await resume(tester);
    expect(container.authenticator.reasons, hasLength(2));
    await tester.pumpAndSettle();
    expect(container.authenticator.reasons, hasLength(2));

    await unlock(tester);
    expect(find.byType(WhatsNewDialog), findsOneWidget);
    expect(container.fxRepository.refreshes, greaterThan(0));
  });

  testWidgets('background lock covers a pushed Settings route', (
    WidgetTester tester,
  ) async {
    await start(tester, locked: true, authenticated: true);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    pause(tester);
    expect(container.authenticator.reasons, isEmpty);
    await resume(tester);
    await capture?.call(tester, 'settings-after-resume');
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(container.authenticator.reasons, hasLength(1));
    await unlock(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('a cold inactive mount waits for foreground before prompting', (
    WidgetTester tester,
  ) async {
    await container.settingsRepository.setAppLockEnabled(true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(
      AppScope(container: container, child: const OkanzoApp()),
    );
    await tester.pumpAndSettle();
    expect(container.authenticator.reasons, isEmpty);
    expect(find.byType(LockScreen), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(container.authenticator.reasons, hasLength(1));
  });

  for (final String tab in <String>['Home', 'Statistics', 'Portfolios']) {
    testWidgets('background lock covers the $tab tab', (
      WidgetTester tester,
    ) async {
      await start(tester, locked: true, authenticated: true);
      await _tap(tester, find.widgetWithText(NavigationDestination, tab));
      pause(tester);
      expect(container.authenticator.reasons, isEmpty);
      await resume(tester);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await unlock(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        <String>['Home', 'Statistics', 'Portfolios'].indexOf(tab),
      );
    });
  }

  for (final bool asset in <bool>[true, false]) {
    testWidgets(
      '${asset ? 'asset' : 'liability'} draft survives lock, hidden focus and System Back',
      (WidgetTester tester) async {
        await start(tester, locked: true, authenticated: true);
        final BuildContext context = tester.element(find.byType(HomeScreen));
        unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => asset
                  ? const AssetEditScreen(portfolioId: 1, assetId: 0)
                  : const LiabilityEditScreen(portfolioId: 1, liabilityId: 0),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final Finder input = _input(asset ? 'Quantity' : 'Name');
        await tester.ensureVisible(input);
        await tester.enterText(input, asset ? '37' : 'Synthetic draft');
        await tester.pumpAndSettle();
        final EditableText editable = tester.widget<EditableText>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        );
        expect(editable.focusNode.hasFocus, isTrue);
        final List<MethodCall> platformCalls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            platformCalls.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        pause(tester);
        expect(container.authenticator.reasons, isEmpty);
        await resume(tester);
        expect(editable.focusNode.hasFocus, isFalse);
        expect(find.byType(LockScreen), findsOneWidget);
        expect(find.byType(TextField).hitTestable(), findsNothing);
        final SemanticsHandle semantics = tester.ensureSemantics();
        expect(find.bySemanticsLabel(RegExp('Synthetic draft')), findsNothing);
        semantics.dispose();
        await tester.binding.handlePopRoute();
        expect(
          platformCalls.any(
            (MethodCall call) =>
                call.method == 'SystemNavigator.setFrameworkHandlesBack' &&
                call.arguments == false,
          ),
          isTrue,
        );
        expect(
          platformCalls.any(
            (MethodCall call) => call.method == 'SystemNavigator.pop',
          ),
          isTrue,
        );
        await unlock(tester);
        expect(find.text(asset ? '37' : 'Synthetic draft'), findsOneWidget);
        expect(
          find.byType(asset ? AssetEditScreen : LiabilityEditScreen),
          findsOneWidget,
        );
        await capture?.call(
          tester,
          asset ? 'asset-draft-restored' : 'liability-draft-restored',
        );
      },
    );
  }

  for (final bool sheet in <bool>[false, true]) {
    testWidgets('lock covers and restores a ${sheet ? 'sheet' : 'dialog'}', (
      WidgetTester tester,
    ) async {
      await start(tester, locked: true, authenticated: true);
      final BuildContext context = tester.element(find.byType(HomeScreen));
      const Widget content = Padding(
        padding: EdgeInsets.all(24),
        child: Text('Synthetic modal'),
      );
      if (sheet) {
        unawaited(
          showModalBottomSheet<void>(context: context, builder: (_) => content),
        );
      } else {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(content: content),
          ),
        );
      }
      await tester.pumpAndSettle();
      pause(tester);
      await resume(tester);
      expect(find.text('Synthetic modal'), findsNothing);
      expect(find.byType(LockScreen), findsOneWidget);
      await unlock(tester);
      expect(find.text('Synthetic modal'), findsOneWidget);
    });
  }

  testWidgets('App lock changes require successful step-up without relocking', (
    WidgetTester tester,
  ) async {
    await start(tester);
    await settings(tester, 'Security');
    for (final BiometricResult result in <BiometricResult>[
      BiometricResult.cancelled,
      BiometricResult.failed,
      BiometricResult.success,
    ]) {
      container.authenticator.result = result;
      await _tap(tester, find.text('App lock'));
      expect(
        container.settingsRepository.current.appLockEnabled,
        result == BiometricResult.success,
      );
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
    }

    container.authenticator.pending = Completer<BiometricResult>();
    await _tap(tester, find.text('App lock'));
    pause(tester);
    await resume(tester);
    expect(find.byType(LockScreen), findsNothing);
    container.authenticator.pending!.complete(BiometricResult.cancelled);
    await tester.pumpAndSettle();
    container.authenticator.pending = null;
    expect(container.settingsRepository.current.appLockEnabled, isTrue);
    container.authenticator.result = BiometricResult.failed;
    await _tap(tester, find.text('App lock'));
    expect(container.settingsRepository.current.appLockEnabled, isTrue);
    container.authenticator.result = BiometricResult.success;
    await _tap(tester, find.text('App lock'));
    expect(container.settingsRepository.current.appLockEnabled, isFalse);
    expect(
      container.authenticator.reasons,
      everyElement("Confirm it's you to change app lock"),
    );
  });

  for (final bool locked in <bool>[false, true]) {
    testWidgets('export step-up follows App lock enabled=$locked', (
      WidgetTester tester,
    ) async {
      await start(tester, locked: locked, authenticated: locked);
      await settings(tester, 'Data');
      await _tap(tester, find.text('Export portfolios'));
      expect(find.byType(AlertDialog), locked ? findsNothing : findsOneWidget);
      if (locked) {
        expect(container.authenticator.reasons, <String>[
          "Confirm it's you to export portfolios",
        ]);
        container.authenticator.result = BiometricResult.success;
        await _tap(tester, find.text('Export portfolios'));
        expect(find.byType(AlertDialog), findsOneWidget);
      } else {
        expect(container.authenticator.reasons, isEmpty);
      }
    });
  }

  testWidgets(
    'Settings uses app-language prompts and rejects missing credentials',
    (WidgetTester tester) async {
      const AppLocalizations es = AppLocalizations(Locale('es'));
      await container.settingsRepository.setLanguage(AppLanguage.spanish);
      await start(tester);
      await _tap(tester, find.byTooltip(es.text('Settings')));
      await _tap(tester, find.text(es.text('Security')));
      container.authenticator.available = BiometricCapability.notEnrolled;
      await _tap(tester, find.text(es.text('App lock')));
      expect(container.settingsRepository.current.appLockEnabled, isFalse);
      expect(
        find.text(
          es.text(
            'Set up a screen lock or fingerprint in system settings first',
          ),
        ),
        findsOneWidget,
      );
      container.authenticator.available = BiometricCapability.available;
      container.authenticator.result = BiometricResult.success;
      await _tap(tester, find.text(es.text('App lock')));
      expect(container.settingsRepository.current.appLockEnabled, isTrue);
      expect(
        container.authenticator.reasons.single,
        es.text("Confirm it's you to change app lock"),
      );
      container.authenticator.available = BiometricCapability.unavailable;
      await _tap(tester, find.text(es.text('App lock')));
      expect(container.settingsRepository.current.appLockEnabled, isTrue);
      expect(find.byType(SettingsScreen), findsOneWidget);
    },
  );

  testWidgets('an unfinished file picker can exempt only its first pause', (
    WidgetTester tester,
  ) async {
    await start(tester, locked: true, authenticated: true);
    await settings(tester, 'Data');
    container.backupFilePicker.picking = Completer<PlatformFile?>();
    await _tap(tester, find.text('Import portfolios'));
    pause(tester);
    await resume(tester);
    expect(find.byType(LockScreen), findsNothing);
    pause(tester);
    await resume(tester);
    expect(find.byType(LockScreen), findsOneWidget);
    container.backupFilePicker.picking!.complete(null);
    await tester.pumpAndSettle();
  });

  for (final bool export in <bool>[false, true]) {
    for (final int seconds in <int>[60, 61]) {
      testWidgets(
        '${export ? 'save' : 'pick'} file handoff at ${seconds}s is bounded and single-use',
        (WidgetTester tester) async {
          await start(tester, locked: true, authenticated: true);
          await settings(tester, 'Data');
          if (export) {
            container.authenticator.result = BiometricResult.success;
            await _tap(tester, find.text('Export portfolios'));
            container.authenticator.result = BiometricResult.cancelled;
            for (final Element field
                in find
                    .descendant(
                      of: find.byType(AlertDialog),
                      matching: find.byType(TextField),
                    )
                    .evaluate()
                    .toList()) {
              await tester.enterText(
                find.byWidget(field.widget),
                'synthetic-password',
              );
            }
            container.backupFilePicker.saving = Completer<Uri?>();
            await _tap(tester, find.widgetWithText(TextButton, 'Export'));
            expect(container.backupFilePicker.saves, 1);
          } else {
            container.backupFilePicker.picking = Completer<PlatformFile?>();
            await _tap(tester, find.text('Import portfolios'));
          }
          final int prompts = container.authenticator.reasons.length;
          pause(tester);
          container.time = container.time.add(Duration(seconds: seconds));
          // Plugins may resolve before the app's resumed lifecycle notification.
          if (export) {
            container.backupFilePicker.saving!.complete(null);
          } else {
            container.backupFilePicker.picking!.complete(_PickedFile());
          }
          await resume(tester);
          expect(
            find.byType(LockScreen),
            seconds == 61 ? findsOneWidget : findsNothing,
          );
          expect(
            container.authenticator.reasons.length,
            prompts + (seconds == 61 ? 1 : 0),
          );
          if (seconds == 61) await unlock(tester);
          expect(find.byType(SettingsScreen), findsOneWidget);
          if (!export) {
            expect(find.text('Import backup'), findsOneWidget);
            await _tap(tester, find.text('Cancel'));
          }
          pause(tester);
          await resume(tester);
          expect(find.byType(LockScreen), findsOneWidget);
        },
      );
    }
  }

  for (final BiometricCapability capability in <BiometricCapability>[
    BiometricCapability.notEnrolled,
    BiometricCapability.unavailable,
  ]) {
    testWidgets(
      'missing credentials ($capability) fail closed with localized guidance',
      (WidgetTester tester) async {
        await container.settingsRepository.setLanguage(AppLanguage.spanish);
        container.authenticator.available = capability;
        await start(tester, locked: true);
        final String message = capability == BiometricCapability.notEnrolled
            ? 'Set up a screen lock or fingerprint in system settings first'
            : "This device can't authenticate you";
        expect(
          find.text(const AppLocalizations(Locale('es')).text(message)),
          findsOneWidget,
        );
        expect(find.byType(AppShell, skipOffstage: false), findsNothing);
        expect(container.settingsRepository.current.appLockEnabled, isTrue);
        expect(container.authenticator.reasons, isEmpty);
      },
    );
  }
}
