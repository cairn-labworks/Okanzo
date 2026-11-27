import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'data/repository/settings_repository.dart';
import 'data/security/database_key_provider.dart';
import 'di/app_container.dart';
import 'domain/model/app_theme.dart';
import 'domain/model/theme_mode.dart';
import 'l10n/app_localizations.dart';
import 'ui/lock/lock_screen.dart';
import 'ui/navigation/app_shell.dart';
import 'ui/theme/app_material.dart';
import 'ui/theme/theme.dart';
import 'util/app_lock_coordinator.dart';
import 'util/biometric_authenticator.dart';
import 'util/screenshot_protection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Number and date formatting follows the device locale, as it did on Android.
  Intl.defaultLocale = Platform.localeName.split('.').first;

  // Kick off Keystore unwrap and DB directory lookup immediately in parallel
  // without stalling behind UI-thread window setup.
  const DatabaseKeyProvider keyProvider = DatabaseKeyProvider();
  final Future<SharedPreferences> prefsFuture = SharedPreferences.getInstance();
  final Future<String> passphraseFuture = keyProvider.getOrCreatePassphrase();
  final Future<String> databasesDirFuture = getDatabasesPath();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  final SharedPreferences preferences = await prefsFuture;
  final SettingsRepository settingsRepository = SettingsRepository(preferences);
  final BiometricAuthenticator authenticator = LocalBiometricAuthenticator();
  final AppLockCoordinator appLock = AppLockCoordinator(
    authenticator: authenticator,
  );
  // MainActivity.onCreate applies FLAG_SECURE before Frame 1 on cold Android
  // launch; keep a non-blocking sync here too so Dart-only restarts stay aligned.
  unawaited(
    ScreenshotProtection.setEnabled(settingsRepository.current.blockScreenshots)
        .catchError((Object _) {}),
  );

  final Future<AppContainer> containerFuture = AppContainer.create(
    preferences: preferences,
    settingsRepository: settingsRepository,
    appLock: appLock,
    passphraseFuture: passphraseFuture,
    databasesDirFuture: databasesDirFuture,
    biometricAuthenticator: authenticator,
  );

  runApp(
    OkanzoBootstrap(
      settingsRepository: settingsRepository,
      appLock: appLock,
      containerFuture: containerFuture,
    ),
  );
}

/// Renders the themed application (and [AppLockGate] if enabled) immediately
/// from [SettingsRepository] while the encrypted database finishes opening in
/// the background, then seamlessly mounts [AppScope] + [OkanzoApp].
class OkanzoBootstrap extends StatefulWidget {
  const OkanzoBootstrap({
    required this.settingsRepository,
    required this.appLock,
    required this.containerFuture,
    super.key,
  });

  final SettingsRepository settingsRepository;
  final AppLockCoordinator appLock;
  final Future<AppContainer> containerFuture;

  @override
  State<OkanzoBootstrap> createState() => _OkanzoBootstrapState();
}

class _OkanzoBootstrapState extends State<OkanzoBootstrap> {
  final GlobalKey<_OkanzoAppState> _appKey = GlobalKey<_OkanzoAppState>();
  AppContainer? _container;

  @override
  void initState() {
    super.initState();
    unawaited(_awaitContainer(widget.containerFuture));
  }

  @override
  void didUpdateWidget(OkanzoBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.containerFuture != widget.containerFuture) {
      _container = null;
      unawaited(_awaitContainer(widget.containerFuture));
    }
  }

  Future<void> _awaitContainer(Future<AppContainer> future) async {
    final AppContainer resolved = await future;
    if (!mounted || !identical(future, widget.containerFuture)) return;
    setState(() => _container = resolved);
  }

  @override
  Widget build(BuildContext context) {
    final Widget app = OkanzoApp(
      key: _appKey,
      settingsRepository: widget.settingsRepository,
      appLock: widget.appLock,
      isDatabaseReady: _container != null,
    );
    final AppContainer? container = _container;
    return container == null ? app : AppScope(container: container, child: app);
  }
}

class OkanzoApp extends StatefulWidget {
  const OkanzoApp({
    this.settingsRepository,
    this.appLock,
    this.isDatabaseReady = true,
    super.key,
  });

  final SettingsRepository? settingsRepository;
  final AppLockCoordinator? appLock;
  final bool isDatabaseReady;

  @override
  State<OkanzoApp> createState() => _OkanzoAppState();
}

class _OkanzoAppState extends State<OkanzoApp> with WidgetsBindingObserver {
  SettingsRepository? _settingsRepository;
  AppLockCoordinator? _appLock;
  bool _navigatorCanHandlePop = false;
  bool? _frameworkHandlesBack;

  bool get _locked =>
      _settingsRepository != null &&
      _appLock != null &&
      _settingsRepository!.current.appLockEnabled &&
      !_appLock!.unlocked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _appLock?.removeListener(_updateBackHandling);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindDependencies();
  }

  @override
  void didUpdateWidget(OkanzoApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindDependencies();
  }

  void _bindDependencies() {
    final AppScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    final SettingsRepository nextSettings =
        widget.settingsRepository ?? scope!.container.settingsRepository;
    final AppLockCoordinator nextLock =
        widget.appLock ?? scope!.container.appLock;
    if (!identical(_appLock, nextLock)) {
      _appLock?.removeListener(_updateBackHandling);
      _appLock = nextLock..addListener(_updateBackHandling);
    }
    _settingsRepository = nextSettings;
    _updateBackHandling();
  }

  void _updateBackHandling() {
    final bool handlesBack = !_locked && _navigatorCanHandlePop;
    if (_frameworkHandlesBack == handlesBack) return;
    _frameworkHandlesBack = handlesBack;
    // Let Android's predictive back exit the activity, not animate a hidden route.
    unawaited(SystemNavigator.setFrameworkHandlesBack(handlesBack));
  }

  // This observer precedes WidgetsApp's Navigator observer. A PopScope outside
  // the Navigator cannot by itself intercept back events for its hidden routes.
  @override
  Future<bool> didPopRoute() async {
    if (_locked) {
      await SystemNavigator.pop();
      return true;
    }
    return false;
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    Intl.defaultLocale = locales != null && locales.isNotEmpty
        ? locales.first.toString()
        : Intl.systemLocale;
  }

  @override
  Widget build(BuildContext context) {
    final SettingsRepository settingsRepository = _settingsRepository!;
    final AppLockCoordinator appLock = _appLock!;
    return StreamBuilder<AppSettings>(
      stream: settingsRepository.settings,
      initialData: settingsRepository.current,
      builder: (BuildContext context, AsyncSnapshot<AppSettings> snapshot) {
        final AppSettings? settings = snapshot.data;
        if (settings == null) {
          // Brief splash while preferences load; avoids flashing the wrong theme.
          return const SizedBox.shrink();
        }
        _updateBackHandling();
        final AppTheme themeStyle = settings.themeStyle;
        return MaterialApp(
          title: 'Okanzo',
          debugShowCheckedModeBanner: false,
          onNavigationNotification: (NavigationNotification notification) {
            _navigatorCanHandlePop = notification.canHandlePop;
            _updateBackHandling();
            return true;
          },
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: AppLocalizations.localeForLanguage(settings.language),
          theme: buildTheme(brightness: Brightness.light, appTheme: themeStyle),
          darkTheme: buildTheme(
            brightness: Brightness.dark,
            appTheme: themeStyle == AppTheme.classic
                ? AppTheme.midnight
                : themeStyle,
          ),
          themeMode: switch (settings.appearanceMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          builder: (BuildContext context, Widget? navigator) =>
              AppThemeBackground(
                child: AppLockGate(
                  appLockEnabled: settings.appLockEnabled,
                  coordinator: appLock,
                  child: navigator!,
                ),
              ),
          home: widget.isDatabaseReady
              ? const AppShell()
              : const Scaffold(body: SizedBox.shrink()),
        );
      },
    );
  }
}

/// Shows the lock screen until the user passes a biometric / device-credential
/// challenge, and re-locks whenever the app leaves the foreground.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    required this.appLockEnabled,
    required this.coordinator,
    required this.child,
    super.key,
  });

  final bool appLockEnabled;
  final AppLockCoordinator coordinator;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _shellMounted = false;
  bool _autoPrompted = false;
  bool _promptScheduled = false;
  bool _unlockOnResume = false;
  String? _error;
  late AppLifecycleState _lifecycle;

  bool get _locked => widget.appLockEnabled && !widget.coordinator.unlocked;

  @override
  void initState() {
    super.initState();
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.coordinator.addListener(_onLockChanged);
    _schedulePrompt();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.coordinator.removeListener(_onLockChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator != widget.coordinator) {
      oldWidget.coordinator.removeListener(_onLockChanged);
      widget.coordinator.addListener(_onLockChanged);
    }
    if (!oldWidget.appLockEnabled && widget.appLockEnabled && _locked) {
      FocusManager.instance.primaryFocus?.unfocus();
      _autoPrompted = false;
    }
    _schedulePrompt();
  }

  void _onLockChanged() {
    if (_locked) FocusManager.instance.primaryFocus?.unfocus();
    if (!_locked) _error = null;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.paused &&
        !widget.coordinator.authenticating &&
        !widget.coordinator.deferPickerPause()) {
      _unlockOnResume = false;
      _autoPrompted = false;
      if (widget.appLockEnabled) widget.coordinator.lock();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.coordinator.consumeExpiredPickerPause() &&
          widget.appLockEnabled) {
        _autoPrompted = false;
        widget.coordinator.lock();
      }
      if (_unlockOnResume) {
        _unlockOnResume = false;
        widget.coordinator.markUnlocked();
      }
      _schedulePrompt();
    }
  }

  void _schedulePrompt() {
    if (!_locked ||
        _autoPrompted ||
        _promptScheduled ||
        widget.coordinator.authenticating ||
        _lifecycle != AppLifecycleState.resumed) {
      return;
    }
    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptScheduled = false;
      if (!mounted ||
          !_locked ||
          _autoPrompted ||
          widget.coordinator.authenticating ||
          _lifecycle != AppLifecycleState.resumed) {
        return;
      }
      _autoPrompted = true;
      unawaited(_authenticate());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _authenticate() async {
    if (widget.coordinator.authenticating ||
        _lifecycle != AppLifecycleState.resumed) {
      return;
    }
    _autoPrompted = true;
    final BiometricResult result = await widget.coordinator.authenticate(
      title: 'Unlock Okanzo'.tr(context),
      subtitle: "Confirm it's you to view your net worth".tr(context),
    );
    if (!mounted) return;
    if (result == BiometricResult.success) {
      if (_lifecycle == AppLifecycleState.resumed) {
        widget.coordinator.markUnlocked();
      } else {
        _unlockOnResume = true;
      }
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) _shellMounted = true;
    return PopScope(
      canPop: !_locked,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _locked) unawaited(SystemNavigator.pop());
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_shellMounted)
            Visibility(
              visible: !_locked,
              maintainState: true,
              child: IgnorePointer(
                ignoring: _locked,
                child: ExcludeFocus(
                  excluding: _locked,
                  child: ExcludeSemantics(
                    excluding: _locked,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          if (_locked) LockScreen(onUnlock: _authenticate, error: _error),
        ],
      ),
    );
  }
}
