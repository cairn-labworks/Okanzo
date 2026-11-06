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
import 'util/biometric_authenticator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draws behind the system bars, as `enableEdgeToEdge()` did on Android.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Number and date formatting follows the device locale, as it did on Android.
  Intl.defaultLocale = Platform.localeName.split('.').first;
  final AppContainer container = await AppContainer.create();
  runApp(AppScope(container: container, child: const OkanzoApp()));
}

class OkanzoApp extends StatefulWidget {
  const OkanzoApp({super.key});

  @override
  State<OkanzoApp> createState() => _OkanzoAppState();
}

class _OkanzoAppState extends State<OkanzoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final AppTheme appTheme = settings.appTheme;
            // Wallpaper colors only apply to the Classic theme.
            final bool useDynamic =
                settings.dynamicColor && appTheme == AppTheme.classic;
            return MaterialApp(
              title: 'Okanzo',
              debugShowCheckedModeBanner: false,
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
                appTheme: appTheme,
              ),
              darkTheme: buildTheme(
                brightness: Brightness.dark,
                dynamicScheme: useDynamic ? darkDynamic : null,
                appTheme: appTheme,
              ),
              themeMode: appTheme == AppTheme.midnight
                  ? ThemeMode.dark
                  : switch (settings.themeMode) {
                      AppThemeMode.system => ThemeMode.system,
                      AppThemeMode.light => ThemeMode.light,
                      AppThemeMode.dark => ThemeMode.dark,
                    },
              home: AppLockGate(
                appLockEnabled: settings.appLockEnabled,
                child: const AppShell(),
              ),
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
    required this.child,
    super.key,
  });

  final bool appLockEnabled;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Turning the lock off discards the unlocked state, so turning it back on
    // challenges the user again — the Android gate did the same by dropping the
    // saveable state when the lock was disabled.
    if (oldWidget.appLockEnabled && !widget.appLockEnabled) _unlocked = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock whenever the app is sent to the background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_prompting && _unlocked) setState(() => _unlocked = false);
    }
  }

  Future<void> _authenticate() async {
    if (_prompting) return;
    _prompting = true;
    final String? error = await BiometricAuthenticator.authenticate(
      title: 'Unlock Okanzo'.tr(context),
      subtitle: "Confirm it's you to view your net worth".tr(context),
    );
    _prompting = false;
    // Stay locked on failure; the user can retry from the lock screen.
    if (error == null && mounted) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.appLockEnabled || _unlocked) return widget.child;
    return LockScreen(onUnlock: _authenticate);
  }
}
