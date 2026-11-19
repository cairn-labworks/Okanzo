import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'data/repository/settings_repository.dart';
import 'di/app_container.dart';
import 'domain/model/app_theme.dart';
import 'domain/model/theme_mode.dart';
import 'l10n/app_localizations.dart';
import 'ui/lock/lock_screen.dart';
import 'ui/navigation/app_shell.dart';
import 'ui/theme/dynamic_color.dart';
import 'ui/theme/theme.dart';
import 'util/app_lock_coordinator.dart';
import 'util/biometric_authenticator.dart';
import 'util/screenshot_protection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draws behind the system bars, as `enableEdgeToEdge()` did on Android.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Number and date formatting follows the device locale, as it did on Android.
  Intl.defaultLocale = Platform.localeName.split('.').first;
  final AppContainer container = await AppContainer.create();
  try {
    await ScreenshotProtection.setEnabled(
      container.settingsRepository.current.blockScreenshots,
    );
  } on PlatformException {
    // Keep startup non-fatal; MainActivity enables FLAG_SECURE by default.
  }
  runApp(AppScope(container: container, child: const OkanzoApp()));
}

class OkanzoApp extends StatefulWidget {
  const OkanzoApp({super.key});

  @override
  State<OkanzoApp> createState() => _OkanzoAppState();
}

class _OkanzoAppState extends State<OkanzoApp> with WidgetsBindingObserver {
  AppContainer? _container;
  bool _navigatorCanHandlePop = false;
  bool? _frameworkHandlesBack;

  bool get _locked =>
      _container != null &&
      _container!.settingsRepository.current.appLockEnabled &&
      !_container!.appLock.unlocked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _container?.appLock.removeListener(_updateBackHandling);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container?.appLock.removeListener(_updateBackHandling);
    _container = AppScope.of(context);
    _container!.appLock.addListener(_updateBackHandling);
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
    final AppContainer container = AppScope.of(context);
    return StreamBuilder<AppSettings>(
      stream: container.settingsRepository.settings,
      initialData: container.settingsRepository.current,
      builder: (BuildContext context, AsyncSnapshot<AppSettings> snapshot) {
        final AppSettings? settings = snapshot.data;
        if (settings == null) {
          // Brief splash while preferences load; avoids flashing the wrong theme.
          return const SizedBox.shrink();
        }
        _updateBackHandling();
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            // Wallpaper colours apply to light mode; dark is always Midnight.
            final bool useDynamic =
                settings.dynamicColor &&
                settings.appearanceMode != AppThemeMode.dark;
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
              theme: buildTheme(
                brightness: Brightness.light,
                dynamicScheme: useDynamic ? lightDynamic : null,
                appTheme: AppTheme.classic,
              ),
              darkTheme: buildTheme(
                brightness: Brightness.dark,
                appTheme: AppTheme.midnight,
              ),
              themeMode: switch (settings.appearanceMode) {
                AppThemeMode.system => ThemeMode.system,
                AppThemeMode.light => ThemeMode.light,
                AppThemeMode.dark => ThemeMode.dark,
              },
              builder: (BuildContext context, Widget? navigator) => AppLockGate(
                appLockEnabled: settings.appLockEnabled,
                coordinator: container.appLock,
                child: navigator!,
              ),
              home: const AppShell(),
            );
          },
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
