import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/backup/backup_models.dart';
import '../../data/local/entity/portfolio_entity.dart';
import '../../di/app_container.dart';
import '../../domain/model/app_language.dart';
import '../../domain/model/app_theme.dart';
import '../../domain/model/release_notes.dart';
import '../../domain/model/theme_mode.dart';
import '../../l10n/app_localizations.dart';
import '../../util/biometric_authenticator.dart';
import '../../util/currency_util.dart';
import '../../util/link_opener.dart';
import '../../util/relative_time.dart';
import '../components/form_components.dart';
import '../components/type_icons.dart';
import '../components/ui_components.dart';
import '../components/whats_new_dialog.dart';
import '../theme/motion.dart';
import '../theme/app_material.dart';
import 'settings_view_model.dart';

/// Appearance, currency, security, backup and about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsViewModel? _viewModel;
  int? _selectedCategory;
  bool _movingForward = true;
  bool _authenticating = false;

  void _openCategory(int index) {
    setState(() {
      _movingForward = true;
      _selectedCategory = index;
    });
  }

  void _back() {
    if (_selectedCategory != null) {
      setState(() {
        _movingForward = false;
        _selectedCategory = null;
      });
    } else {
      widget.onClose();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final AppContainer container = AppScope.of(context);
    _viewModel = SettingsViewModel(
      settingsRepository: container.settingsRepository,
      portfolioRepository: container.portfolioRepository,
      fxRepository: container.fxRepository,
      backupRepository: container.backupRepository,
    )..addListener(_onChanged);
  }

  void _onChanged() {
    final String? message = _viewModel?.message;
    if (message != null && mounted) {
      _viewModel!.consumeMessage();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.tr(context))));
    }
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onChanged);
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsViewModel viewModel = _viewModel!;
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (BuildContext context, _) {
        final settings = viewModel.settings;
        final int? fxUpdatedAt = viewModel.fxUpdatedAt;
        final List<_SettingsSection> categories = <_SettingsSection>[
          _SettingsSection(
            title: 'Appearance'.tr(context),
            description: 'Language, theme & colour'.tr(context),
            icon: Icons.contrast,
            summary: settings.appearanceMode.displayName.tr(context),
            children: <Widget>[
              _ThemeSegmentedRow(
                selected: settings.appearanceMode,
                onSave: viewModel.setAppearanceMode,
              ),
              _SettingRow(
                title: 'Theme style'.tr(context),
                value: settings.themeStyle.displayName.tr(context),
                valueIcon: Icons.palette_outlined,
                onTap: () => _showThemeStyleDialog(settings.themeStyle),
              ),
              _SettingRow(
                title: 'App language'.tr(context),
                value: settings.language == AppLanguage.system
                    ? 'System default'.tr(context)
                    : settings.language.displayName,
                valueIcon: Icons.language,
                onTap: () => _showLanguageDialog(settings.language),
              ),
            ],
          ),
          _SettingsSection(
            title: 'Currency'.tr(context),
            description: 'Base currency & number display'.tr(context),
            icon: Icons.monetization_on_outlined,
            summary: settings.baseCurrency,
            children: <Widget>[
              _SettingRow(
                title: 'Base currency'.tr(context),
                subtitle: CurrencyUtil.displayName(settings.baseCurrency),
                value: settings.baseCurrency,
                valueIcon: currencyIcon(settings.baseCurrency),
                onTap: () => _showCurrencyPicker(settings.baseCurrency),
              ),
              _SwitchRow(
                title: 'Simple net worth'.tr(context),
                subtitle:
                    'Shorten the home net worth using currency-specific units'
                        .tr(context),
                value: settings.simpleNetWorth,
                onChanged: viewModel.isSavingSimpleNetWorth
                    ? null
                    : viewModel.setSimpleNetWorth,
              ),
            ],
          ),
          _SettingsSection(
            title: 'Security'.tr(context),
            description: 'App lock & screenshot protection'.tr(context),
            icon: Icons.lock_outline,
            children: <Widget>[
              _SwitchRow(
                title: 'App lock'.tr(context),
                subtitle: 'Require fingerprint or device PIN to open Okanzo'.tr(
                  context,
                ),
                value: settings.appLockEnabled,
                onChanged: _authenticating ? null : _onAppLockChanged,
              ),
              _SwitchRow(
                title: 'Block screenshots'.tr(context),
                subtitle: 'Prevent screenshots and hide Okanzo in recent apps'
                    .tr(context),
                value: settings.blockScreenshots,
                onChanged: viewModel.isSavingBlockScreenshots
                    ? null
                    : viewModel.setBlockScreenshots,
              ),
            ],
          ),
          _SettingsSection(
            title: 'Data'.tr(context),
            description: 'Exchange rates, export & import'.tr(context),
            icon: Icons.cloud_upload_outlined,
            children: <Widget>[
              _SettingRow(
                title: 'Exchange rates'.tr(context),
                subtitle: fxUpdatedAt == null
                    ? 'Not fetched yet'.tr(context)
                    : 'Updated {time}'
                          .tr(context)
                          .replaceAll(
                            '{time}',
                            relativeTimeSpan(
                              fxUpdatedAt,
                              localizations: AppLocalizations.of(context),
                            ),
                          ),
                trailing: IconButton(
                  tooltip: 'Refresh rates'.tr(context),
                  onPressed: viewModel.refreshRates,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              _SettingRow(
                title: 'Export portfolios'.tr(context),
                subtitle: 'Save an encrypted, password-protected backup'.tr(
                  context,
                ),
                onTap: _authenticating
                    ? null
                    : () async {
                        if (viewModel.portfolios.isNotEmpty &&
                            (!settings.appLockEnabled ||
                                await _confirmIdentity(
                                  "Confirm it's you to export portfolios",
                                )) &&
                            mounted) {
                          _showExportDialog(viewModel.portfolios);
                        }
                      },
              ),
              _SettingRow(
                title: 'Import portfolios'.tr(context),
                subtitle: 'Restore from an encrypted backup file'.tr(context),
                onTap: _startImport,
              ),
            ],
          ),
          _SettingsSection(
            title: 'About'.tr(context),
            description: 'Release notes & privacy'.tr(context),
            icon: Icons.info_outline,
            summary: 'v${AppReleaseNotes.currentVersion}',
            children: <Widget>[
              _SettingRow(
                title: 'Okanzo'.tr(context),
                subtitle: 'Version {version} · Open source (MIT)'
                    .tr(context)
                    .replaceAll('{version}', AppReleaseNotes.currentVersion),
                onTap: _showAppInformation,
              ),
              _SettingRow(
                title: "What's new".tr(context),
                subtitle: 'See the latest release highlights'.tr(context),
                onTap: _showWhatsNew,
              ),
              _SettingRow(
                title: 'Privacy policy'.tr(context),
                onTap: _openPrivacyPolicy,
              ),
            ],
            footer: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
              child: Text(
                <String>[
                  'Okanzo encrypts your data on this device. Your data leaves '
                          'it only when you export a backup. Price and '
                          'exchange-rate lookups send only the ticker or currency code.'
                      .tr(context),
                  'Company/ticker search sends the text you type to Yahoo Finance.'
                      .tr(context),
                ].join('\n'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ];
        final _SettingsSection? category = _selectedCategory == null
            ? null
            : categories[_selectedCategory!];
        return PopScope(
          canPop: _selectedCategory == null,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) _back();
          },
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 48,
              leading: IconButton(
                tooltip: 'Back'.tr(context),
                onPressed: _back,
                icon: const Icon(Icons.arrow_back),
              ),
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 26),
                  child: Center(
                    child: Text(
                      'OKANZO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: Builder(
              builder: (BuildContext context) {
                final Key pageKey = ValueKey<int?>(_selectedCategory);
                final Widget pageContent = ListView(
                  key: pageKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 12,
                  ),
                  children: <Widget>[
                    PageHeading(category?.title ?? 'Settings'.tr(context)),
                    const SizedBox(height: 28),
                    if (category != null) ...<Widget>[
                      AppCard(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: <Widget>[
                            for (
                              int i = 0;
                              i < category.children.length;
                              i++
                            ) ...<Widget>[
                              if (i > 0)
                                const Divider(indent: 16, endIndent: 16),
                              category.children[i],
                            ],
                          ],
                        ),
                      ),
                      ?category.footer,
                    ] else ...<Widget>[
                      AppCard(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: <Widget>[
                            for (
                              int i = 0;
                              i < categories.length;
                              i++
                            ) ...<Widget>[
                              if (i > 0)
                                const Divider(indent: 16, endIndent: 16),
                              ListTile(
                                key: ValueKey<String>('settings-category-$i'),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                minVerticalPadding: 16,
                                horizontalTitleGap: 12,
                                leading: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    categories[i].icon,
                                    size: 20,
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                                title: Text(
                                  categories[i].title,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  categories[i].description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing:
                                    categories[i].summary != null &&
                                        MediaQuery.sizeOf(context).width >=
                                            350 &&
                                        MediaQuery.textScalerOf(context)
                                                .scale(12) <=
                                            18
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 76,
                                            ),
                                            child: Text(
                                              categories[i].summary!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right,
                                            size: 18,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ],
                                      )
                                    : Icon(
                                        Icons.chevron_right,
                                        size: 18,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                onTap: () => _openCategory(i),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Private by design. Stored on your device.'.tr(
                                context,
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                );
                if (MediaQuery.disableAnimationsOf(context)) {
                  return pageContent;
                }
                return ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder:
                        (Widget? currentChild, List<Widget> previousChildren) =>
                            Stack(
                              alignment: Alignment.topCenter,
                              children: <Widget>[
                                ...previousChildren,
                                ?currentChild,
                              ],
                            ),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          final bool isRtl =
                              Directionality.of(context) == TextDirection.rtl;
                          final double dir =
                              (_movingForward ? 1.0 : -1.0) *
                              (isRtl ? -1.0 : 1.0);
                          final bool isIncoming = child.key == pageKey;
                          final Offset beginOffset = isIncoming
                              ? Offset(0.14 * dir, 0)
                              : Offset(-0.08 * dir, 0);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: beginOffset,
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                    child: pageContent,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showAppInformation() {
    showAboutDialog(
      context: context,
      applicationName: 'Okanzo',
      applicationVersion: AppReleaseNotes.currentVersion,
      applicationIcon: Icon(
        Icons.account_balance_wallet_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      applicationLegalese: 'Version {version} · Open source (MIT)'
          .tr(context)
          .replaceAll('{version}', AppReleaseNotes.currentVersion),
      children: <Widget>[
        const SizedBox(height: 16),
        Text('Private by design. Stored on your device.'.tr(context)),
      ],
    );
  }

  Future<void> _showWhatsNew() async {
    await showWhatsNewDialog(context);
    try {
      await _viewModel?.markWhatsNewSeen(AppReleaseNotes.currentVersion);
    } on Object {
      // Ignore storage errors when viewing release highlights from Settings.
    }
  }

  Future<void> _openPrivacyPolicy() async {
    if (await LinkOpener.open(LinkOpener.privacyPolicyUrl) || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Privacy policy'.tr(context)),
        content: const SelectableText(LinkOpener.privacyPolicyUrl),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Clipboard.setData(
                const ClipboardData(text: LinkOpener.privacyPolicyUrl),
              );
              Navigator.of(dialogContext).pop();
            },
            child: Text('Copy link'.tr(context)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Close'.tr(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _showLanguageDialog(AppLanguage selected) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<void>(
      context: context,
      barrierColor: dark ? const Color(0xAA10231B) : const Color(0x7310231B),
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: _LanguageDialog(
          selected: selected,
          onSave: _viewModel!.setLanguage,
        ),
      ),
    );
  }

  Future<void> _onAppLockChanged(bool enabled) async {
    if (await _confirmIdentity("Confirm it's you to change app lock") &&
        mounted) {
      if (enabled) AppScope.of(context).appLock.markUnlocked();
      _viewModel!.setAppLockEnabled(enabled);
    }
  }

  Future<bool> _confirmIdentity(String reason) async {
    if (_authenticating) return false;
    final AppContainer container = AppScope.of(context);
    setState(() => _authenticating = true);
    try {
      final BiometricResult result = await container.appLock.authenticate(
        title: 'Unlock Okanzo'.tr(context),
        subtitle: reason.tr(context),
      );
      if (!mounted) return false;
      if (result.message != null) _viewModel!.postMessage(result.message!);
      return result == BiometricResult.success;
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  Future<void> _showThemeStyleDialog(AppTheme selected) async {
    final AppTheme? picked = await showSelectionPickerDialog<AppTheme>(
      context,
      title: 'Theme style'.tr(context),
      selected: selected,
      options: const <AppTheme>[
        AppTheme.classic,
        AppTheme.sculpted,
        AppTheme.liquidGlass,
      ],
      optionLabel: (AppTheme theme) => theme.displayName.tr(context),
      optionIcon: (AppTheme theme) => switch (theme) {
        AppTheme.sculpted => Icons.layers_outlined,
        AppTheme.liquidGlass => Icons.blur_on,
        AppTheme.classic || AppTheme.midnight => Icons.contrast,
      },
      searchable: false,
    );
    if (!mounted || picked == null || picked == selected) return;
    try {
      await _viewModel!.setAppTheme(picked);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't save theme: {error}"
                .tr(context)
                .replaceAll('{error}', '$error'),
          ),
        ),
      );
    }
  }

  Future<void> _showCurrencyPicker(String selected) async {
    final String? code = await showCurrencyPickerDialog(
      context,
      selected: selected,
      eyebrow: 'Base currency'.tr(context),
    );
    if (code != null) _viewModel?.setBaseCurrency(code);
  }

  Future<void> _showExportDialog(List<PortfolioEntity> portfolios) async {
    final _ExportRequest? request = await showDialog<_ExportRequest>(
      context: context,
      builder: (BuildContext context) => _ExportDialog(portfolios: portfolios),
    );
    if (request == null || !mounted) return;
    final AppLocalizations localizations = AppLocalizations.of(context);
    final SettingsViewModel viewModel = _viewModel!;
    final AppContainer container = AppScope.of(context);
    try {
      final Uint8List bytes = await viewModel.buildExport(
        request.portfolioIds,
        request.password,
      );
      final Uri? saved = await container.appLock.withFilePicker(
        () => container.backupFilePicker.saveFile(
          dialogTitle: localizations.text('Export portfolios'),
          fileName: 'okanzo-backup.okanzo',
          bytes: bytes,
        ),
      );
      if (saved == null) return;
      viewModel.postMessage(
        localizations
            .text('Exported {count} portfolio(s)')
            .replaceAll('{count}', '${request.portfolioIds.length}'),
      );
    } catch (error) {
      viewModel.postMessage(
        localizations
            .text('Export failed: {error}')
            .replaceAll('{error}', '$error'),
      );
    }
  }

  Future<void> _startImport() async {
    final AppContainer container = AppScope.of(context);
    final AppLocalizations localizations = AppLocalizations.of(context);
    final SettingsViewModel viewModel = _viewModel!;
    try {
      final PlatformFile? file = await container.appLock.withFilePicker(
        () => container.backupFilePicker.pickFile(
          dialogTitle: localizations.text('Import backup'),
        ),
      );
      if (file == null || !mounted) return;
      final String? password = await showDialog<String>(
        context: context,
        builder: (BuildContext context) => const _ImportPasswordDialog(),
      );
      if (password == null || !mounted) return;
      final Uint8List bytes = await file.readAsBytes();
      final ImportResult result = await viewModel.importBackup(bytes, password);
      viewModel.postMessage(
        localizations
            .text(
              'Imported {portfolios} portfolio(s), {assets} assets, '
              '{liabilities} liabilities',
            )
            .replaceAll('{portfolios}', '${result.portfolios}')
            .replaceAll('{assets}', '${result.assets}')
            .replaceAll('{liabilities}', '${result.liabilities}'),
      );
    } catch (error) {
      viewModel.postMessage(
        localizations
            .text('Import failed: {error}')
            .replaceAll('{error}', '$error'),
      );
    }
  }
}

class _ThemeSegmentedRow extends StatefulWidget {
  const _ThemeSegmentedRow({required this.selected, required this.onSave});

  final AppThemeMode selected;
  final Future<void> Function(AppThemeMode) onSave;

  @override
  State<_ThemeSegmentedRow> createState() => _ThemeSegmentedRowState();
}

class _ThemeSegmentedRowState extends State<_ThemeSegmentedRow> {
  static const List<AppThemeMode> _modes = <AppThemeMode>[
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.system,
  ];

  bool _saving = false;
  String? _error;

  static IconData _iconFor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.light => Icons.wb_sunny_outlined,
    AppThemeMode.dark => Icons.dark_mode_outlined,
    AppThemeMode.system => Icons.brightness_auto_outlined,
  };

  Future<void> _select(AppThemeMode mode) async {
    if (_saving) return;
    if (mode == widget.selected) {
      if (_error != null) setState(() => _error = null);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(mode);
      if (mounted) setState(() => _saving = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final int selectedIndex = _modes.indexOf(widget.selected).clamp(0, 2);
    // Maps 0 -> -1.0 (start), 1 -> 0.0 (center), 2 -> 1.0 (end).
    final double alignmentX = (selectedIndex - 1).toDouble();
    final bool compactIcons =
        MediaQuery.sizeOf(context).width >= 350 &&
        MediaQuery.textScalerOf(context).scale(12) <= 18;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Theme'.tr(context), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 3),
          Text(
            'Light or Midnight dark'.tr(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            key: const ValueKey<String>('settings-theme-segmented'),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: canvasBoxBorderColor(colors)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: AnimatedAlign(
                      alignment: AlignmentDirectional(alignmentX, 0),
                      duration: interactionDuration(context),
                      curve: interactionCurve,
                      child: FractionallySizedBox(
                        widthFactor: 1 / 3,
                        heightFactor: 1.0,
                        child: DecoratedBox(
                          key: const ValueKey<String>('settings-theme-thumb'),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      for (final AppThemeMode mode in _modes)
                        Expanded(
                          child: Material(
                            type: MaterialType.transparency,
                            child: Semantics(
                              selected: widget.selected == mode,
                              button: true,
                              enabled: !_saving,
                              child: InkWell(
                                key: ValueKey<AppThemeMode>(mode),
                                borderRadius: BorderRadius.circular(11),
                                onTap: _saving ? null : () => _select(mode),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 44,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 8,
                                    ),
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          if (compactIcons) ...<Widget>[
                                            Icon(
                                              _iconFor(mode),
                                              size: 15,
                                              color: widget.selected == mode
                                                  ? colors.primary
                                                  : colors.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 5),
                                          ],
                                          Flexible(
                                            child: AnimatedDefaultTextStyle(
                                              duration: interactionDuration(
                                                context,
                                              ),
                                              curve: interactionCurve,
                                              style:
                                                  (theme.textTheme.bodySmall ??
                                                          const TextStyle())
                                                      .copyWith(
                                                        color:
                                                            widget.selected ==
                                                                mode
                                                            ? colors.onSurface
                                                            : colors
                                                                  .onSurfaceVariant,
                                                        fontWeight:
                                                            widget.selected ==
                                                                mode
                                                            ? FontWeight.w600
                                                            : FontWeight.w500,
                                                      ),
                                              child: Text(
                                                mode == AppThemeMode.system
                                                    ? 'System'.tr(context)
                                                    : mode.displayName.tr(
                                                        context,
                                                      ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_saving) ...<Widget>[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              "Couldn't save theme: {error}"
                  .tr(context)
                  .replaceAll('{error}', _error!),
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog({required this.selected, required this.onSave});

  final AppLanguage selected;
  final Future<void> Function(AppLanguage) onSave;

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  bool _searchOpen = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    if (_saving) return;
    if (_searchOpen) {
      setState(() {
        _query.clear();
        _searchOpen = false;
      });
    } else {
      setState(() => _searchOpen = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  String _labelFor(BuildContext context, AppLanguage language) =>
      language == AppLanguage.system
      ? 'Use device language'.tr(context)
      : language.displayName;

  List<AppLanguage> _filteredLanguages(BuildContext context) {
    final String needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return AppLanguage.values;
    return AppLanguage.values
        .where((AppLanguage language) {
          final String label = _labelFor(context, language).toLowerCase();
          return label.contains(needle) ||
              language.displayName.toLowerCase().contains(needle) ||
              language.name.toLowerCase().contains(needle) ||
              language.storageName.toLowerCase().contains(needle);
        })
        .toList(growable: false);
  }

  Future<void> _select(AppLanguage? language) async {
    if (language == null || _saving) return;
    if (language == widget.selected) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(language);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color boxBorder = canvasBoxBorderColor(colors);
    final String searchLabel = 'Search'.tr(context);
    final OutlineInputBorder searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: boxBorder),
    );
    final List<AppLanguage> results = _filteredLanguages(context);

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: boxBorder),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Appearance'.tr(context).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.35,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'App language'.tr(context),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.6,
                      height: 1.25,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey<String>('picker-search-button'),
              tooltip: searchLabel,
              onPressed: _saving ? null : _toggleSearch,
              style: IconButton.styleFrom(
                backgroundColor: _searchOpen
                    ? colors.secondaryContainer
                    : colors.surfaceContainerLow,
                foregroundColor: _searchOpen
                    ? colors.primary
                    : colors.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.search, size: 19),
            ),
          ],
        ),
        content: SizedBox(
          width: 375,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DisclosureSize(
                child: !_searchOpen
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Semantics(
                          label: searchLabel,
                          child: TextField(
                            controller: _query,
                            focusNode: _searchFocus,
                            enabled: !_saving,
                            onChanged: (_) => setState(() {}),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colors.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: searchLabel,
                              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                size: 18,
                                color: colors.onSurfaceVariant,
                              ),
                              suffixIcon: _query.text.isEmpty
                                  ? null
                                  : IconButton(
                                      key: const ValueKey<String>(
                                        'picker-search-clear',
                                      ),
                                      tooltip: 'Clear filter'.tr(context),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        _query.clear();
                                        setState(() {});
                                        _searchFocus.requestFocus();
                                      },
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                              filled: true,
                              fillColor: theme.brightness == Brightness.dark
                                  ? colors.surfaceContainerLow
                                  : colors.surfaceContainerLowest,
                              border: searchBorder,
                              enabledBorder: searchBorder,
                              focusedBorder: searchBorder.copyWith(
                                borderSide: BorderSide(
                                  color: colors.primary,
                                  width: 1.5,
                                ),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 342),
                  child: results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 16,
                          ),
                          child: Text(
                            'No matching options.'.tr(context),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ClipRect(
                          child: Material(
                            type: MaterialType.transparency,
                            clipBehavior: Clip.hardEdge,
                            child: Scrollbar(
                              controller: _scroll,
                              child: RadioGroup<AppLanguage>(
                                groupValue: widget.selected,
                                onChanged: _select,
                                child: ListView(
                                  controller: _scroll,
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  children: <Widget>[
                                    for (final AppLanguage language in results)
                                      RadioListTile<AppLanguage>(
                                        key: ValueKey<AppLanguage>(language),
                                        value: language,
                                        enabled: !_saving,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                        title: Text(
                                          _labelFor(context, language),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              if (_saving) const LinearProgressIndicator(),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  "Couldn't save app language: {error}"
                      .tr(context)
                      .replaceAll('{error}', _error!),
                  style: TextStyle(color: colors.error),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
                minimumSize: const Size.fromHeight(48),
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text('Close'.tr(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection {
  const _SettingsSection({
    required this.title,
    required this.description,
    required this.icon,
    required this.children,
    this.summary,
    this.footer,
  });

  final String title;
  final String description;
  final IconData icon;
  final String? summary;
  final List<Widget> children;
  final Widget? footer;
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    this.subtitle,
    this.value,
    this.valueIcon,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final IconData? valueIcon;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double maxPillWidth = math.min(
      184,
      MediaQuery.sizeOf(context).width * 0.46,
    );
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      titleTextStyle: theme.textTheme.bodyMedium,
      subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 16,
      onTap: onTap,
      trailing:
          trailing ??
          (value != null
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxPillWidth),
                  child: onTap == null
                      ? Text(
                          value!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : PickerChip(label: value!, icon: valueIcon),
                )
              : onTap == null
              ? null
              : Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                )),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SwitchListTile(
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ExportRequest {
  const _ExportRequest(this.portfolioIds, this.password);

  final List<int> portfolioIds;
  final String password;
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.portfolios});

  final List<PortfolioEntity> portfolios;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late final Map<int, bool> _selected = <int, bool>{
    for (final PortfolioEntity portfolio in widget.portfolios)
      portfolio.id: true,
  };
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _visible = false;
  bool _choosingPortfolios = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final List<int> chosen = <int>[
      for (final PortfolioEntity portfolio in widget.portfolios)
        if (_selected[portfolio.id] == true) portfolio.id,
    ];
    final String password = _password.text;
    final String confirm = _confirm.text;
    final bool mismatch = confirm.isNotEmpty && password != confirm;
    final bool canExport =
        chosen.isNotEmpty && password.length >= 4 && password == confirm;
    final bool allSelected = chosen.length == widget.portfolios.length;
    final String selection = allSelected && chosen.length > 1
        ? 'All {count} portfolios'
              .tr(context)
              .replaceAll('{count}', '${chosen.length}')
        : chosen.length == 1
        ? '1 portfolio selected'.tr(context)
        : '{count} portfolios selected'
              .tr(context)
              .replaceAll('{count}', '${chosen.length}');

    return AlertDialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: canvasBoxBorderColor(colors)),
      ),
      scrollable: true,
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      actionsPadding: const EdgeInsets.all(24),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsOverflowButtonSpacing: 12,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Icon(Icons.ios_share_outlined, color: colors.primary, size: 22),
              IconButton(
                tooltip: 'Cancel'.tr(context),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Export portfolios'.tr(context),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'One encrypted file. Yours to keep.'.tr(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 328,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'Include in backup'.tr(context),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  selection,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          expanded: _choosingPortfolios,
                          child: TextButton(
                            onPressed: () => setState(
                              () => _choosingPortfolios = !_choosingPortfolios,
                            ),
                            child: Text(
                              (_choosingPortfolios ? 'Done' : 'Change').tr(
                                context,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_choosingPortfolios) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => setState(
                            () => _selected.updateAll((_, _) => !allSelected),
                          ),
                          child: Text(
                            (allSelected ? 'Clear all' : 'Select all').tr(
                              context,
                            ),
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 224),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (final PortfolioEntity portfolio
                                  in widget.portfolios)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                  value: _selected[portfolio.id] ?? false,
                                  onChanged: (bool? value) => setState(
                                    () => _selected[portfolio.id] =
                                        value ?? false,
                                  ),
                                  title: Text(
                                    portfolio.name,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  subtitle: portfolio.isDefault
                                      ? Text(
                                          'Default'.tr(context),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        )
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _PasswordField(
              controller: _password,
              label: 'Password'.tr(context),
              visible: _visible,
              onToggleVisibility: () => setState(() => _visible = !_visible),
              onChanged: (_) => setState(() {}),
              isError: password.isNotEmpty && password.length < 4,
              supportingText: 'Use at least 4 characters'.tr(context),
            ),
            const SizedBox(height: 8),
            _PasswordField(
              controller: _confirm,
              label: 'Confirm password'.tr(context),
              visible: _visible,
              onToggleVisibility: () => setState(() => _visible = !_visible),
              onChanged: (_) => setState(() {}),
              isError: mismatch,
              supportingText: mismatch
                  ? "Passwords don't match".tr(context)
                  : null,
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.key_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Keep this password safe. You'll need it to import "
                            'your backup.'
                        .tr(context),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(128, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr(context)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(128, 48)),
          onPressed: canExport
              ? () =>
                    Navigator.of(context).pop(_ExportRequest(chosen, password))
              : null,
          child: Text('Export'.tr(context)),
        ),
      ],
    );
  }
}

class _ImportPasswordDialog extends StatefulWidget {
  const _ImportPasswordDialog();

  @override
  State<_ImportPasswordDialog> createState() => _ImportPasswordDialogState();
}

class _ImportPasswordDialogState extends State<_ImportPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  bool _visible = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text('Import backup'.tr(context)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Enter the password used when this backup was exported.'.tr(
              context,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _PasswordField(
            controller: _password,
            label: 'Password'.tr(context),
            visible: _visible,
            onToggleVisibility: () => setState(() => _visible = !_visible),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr(context)),
        ),
        TextButton(
          onPressed: _password.text.isEmpty
              ? null
              : () => Navigator.of(context).pop(_password.text),
          child: Text('Import'.tr(context)),
        ),
      ],
    );
  }
}

/// A password entry field with a show/hide toggle. Uses the password keyboard
/// so the IME does not auto-capitalize or auto-correct the input, which would
/// otherwise silently change the password between export and import.
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.visible,
    required this.onToggleVisibility,
    this.onChanged,
    this.isError = false,
    this.supportingText,
  });

  final TextEditingController controller;
  final String label;
  final bool visible;
  final VoidCallback onToggleVisibility;
  final ValueChanged<String>? onChanged;
  final bool isError;
  final String? supportingText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      keyboardType: visible ? TextInputType.visiblePassword : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: isError ? null : supportingText,
        errorText: isError ? supportingText : null,
        suffixIcon: IconButton(
          tooltip: (visible ? 'Hide password' : 'Show password').tr(context),
          onPressed: onToggleVisibility,
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    );
  }
}
