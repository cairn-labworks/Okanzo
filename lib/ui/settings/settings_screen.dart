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
import '../components/whats_new_dialog.dart';
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
        return Scaffold(
          appBar: AppBar(
            title: Text('Settings'.tr(context)),
            leading: IconButton(
              tooltip: 'Back'.tr(context),
              onPressed: widget.onClose,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: ListView(
            children: <Widget>[
              _SectionTitle('Appearance'.tr(context)),
              _SettingRow(
                title: 'App language'.tr(context),
                subtitle: settings.language == AppLanguage.system
                    ? 'Use device language'.tr(context)
                    : settings.language.displayName,
                onTap: () => _showLanguageDialog(settings.language),
              ),
              _SettingRow(
                title: 'App theme'.tr(context),
                subtitle:
                    '${settings.appTheme.displayName.tr(context)} — '
                    '${settings.appTheme.description.tr(context)}',
                onTap: () => _showAppThemeDialog(settings.appTheme),
              ),
              _SettingRow(
                title: 'Light / dark'.tr(context),
                subtitle: settings.appTheme == AppTheme.midnight
                    ? 'Always dark on Midnight'.tr(context)
                    : settings.themeMode.displayName.tr(context),
                onTap: settings.appTheme == AppTheme.midnight
                    ? null
                    : () => _showThemeDialog(settings.themeMode),
              ),
              _SwitchRow(
                title: 'Dynamic color'.tr(context),
                subtitle: settings.appTheme == AppTheme.midnight
                    ? 'Not used on Midnight'.tr(context)
                    : 'Use colors from your wallpaper (Android 12+)'.tr(
                        context,
                      ),
                value:
                    settings.dynamicColor &&
                    settings.appTheme == AppTheme.classic,
                onChanged: settings.appTheme == AppTheme.midnight
                    ? null
                    : viewModel.setDynamicColor,
              ),
              const Divider(height: 1),
              _SectionTitle('Currency'.tr(context)),
              _SettingRow(
                title: 'Base currency'.tr(context),
                subtitle:
                    '${settings.baseCurrency} — '
                    '${CurrencyUtil.displayName(settings.baseCurrency)}',
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
              const Divider(height: 1),
              _SectionTitle('Security'.tr(context)),
              _SwitchRow(
                title: 'App lock'.tr(context),
                subtitle: 'Require fingerprint or device PIN to open Okanzo'.tr(
                  context,
                ),
                value: settings.appLockEnabled,
                onChanged: _onAppLockChanged,
              ),
              const Divider(height: 1),
              _SectionTitle('Data'.tr(context)),
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
                onTap: () {
                  if (viewModel.portfolios.isNotEmpty) {
                    _showExportDialog(viewModel.portfolios);
                  }
                },
              ),
              _SettingRow(
                title: 'Import portfolios'.tr(context),
                subtitle: 'Restore from an encrypted backup file'.tr(context),
                onTap: _startImport,
              ),
              const Divider(height: 1),
              _SectionTitle('About'.tr(context)),
              _SettingRow(
                title: 'Okanzo'.tr(context),
                subtitle: 'Version {version} · Open source (MIT)'
                    .tr(context)
                    .replaceAll('{version}', AppReleaseNotes.currentVersion),
                onTap: _showWhatsNew,
              ),
              _SettingRow(
                title: "What's new".tr(context),
                subtitle: 'See the latest release highlights'.tr(context),
                onTap: _showWhatsNew,
              ),
              _SettingRow(
                title: 'Privacy policy'.tr(context),
                subtitle: 'cairn-labworks.github.io/Okanzo/privacy',
                onTap: _openPrivacyPolicy,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Text(
                  'Your data is stored encrypted on this device and never '
                          'leaves it, except when you export a backup. Stock and '
                          'exchange-rate lookups send only the ticker or currency code.'
                      .tr(context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
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

  Future<void> _showLanguageDialog(AppLanguage selected) => showDialog<void>(
    context: context,
    builder: (_) =>
        _LanguageDialog(selected: selected, onSave: _viewModel!.setLanguage),
  );

  Future<void> _onAppLockChanged(bool enabled) async {
    final SettingsViewModel viewModel = _viewModel!;
    if (!enabled) {
      viewModel.setAppLockEnabled(false);
      return;
    }
    switch (await BiometricAuthenticator.capability()) {
      case BiometricCapability.available:
        viewModel.setAppLockEnabled(true);
      case BiometricCapability.notEnrolled:
        viewModel.postMessage(
          'Set up a screen lock or fingerprint in system settings first'.tr(
            context,
          ),
        );
      case BiometricCapability.unavailable:
        viewModel.postMessage("This device can't authenticate you".tr(context));
    }
  }

  Future<void> _showThemeDialog(AppThemeMode selected) async {
    final AppThemeMode? mode = await showDialog<AppThemeMode>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Theme'.tr(context)),
        content: RadioGroup<AppThemeMode>(
          groupValue: selected,
          onChanged: (AppThemeMode? value) => Navigator.of(context).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final AppThemeMode mode in AppThemeMode.values)
                RadioListTile<AppThemeMode>(
                  value: mode,
                  title: Text(mode.displayName.tr(context)),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'.tr(context)),
          ),
        ],
      ),
    );
    if (mode != null) _viewModel?.setThemeMode(mode);
  }

  Future<void> _showAppThemeDialog(AppTheme selected) async {
    final AppTheme? theme = await showDialog<AppTheme>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('App theme'.tr(context)),
        content: RadioGroup<AppTheme>(
          groupValue: selected,
          onChanged: (AppTheme? value) => Navigator.of(context).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final AppTheme option in AppTheme.values)
                RadioListTile<AppTheme>(
                  value: option,
                  title: Text(option.displayName.tr(context)),
                  subtitle: Text(option.description.tr(context)),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'.tr(context)),
          ),
        ],
      ),
    );
    if (theme != null) _viewModel?.setAppTheme(theme);
  }

  Future<void> _showCurrencyPicker(String selected) async {
    final String? code = await showCurrencyPickerDialog(
      context,
      selected: selected,
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
    try {
      final Uint8List bytes = await viewModel.buildExport(
        request.portfolioIds,
        request.password,
      );
      final Uri? saved = await FilePicker.saveFile(
        dialogTitle: localizations.text('Export portfolios'),
        fileName: 'okanzo-backup.okanzo',
        bytes: bytes,
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
    final PlatformFile? file = await FilePicker.pickFile(
      dialogTitle: 'Import backup'.tr(context),
    );
    if (file == null || !mounted) return;
    final String? password = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _ImportPasswordDialog(),
    );
    if (password == null || !mounted) return;
    final AppLocalizations localizations = AppLocalizations.of(context);
    final SettingsViewModel viewModel = _viewModel!;
    try {
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

class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog({required this.selected, required this.onSave});

  final AppLanguage selected;
  final Future<void> Function(AppLanguage) onSave;

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  bool _saving = false;
  String? _error;

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
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text('App language'.tr(context)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: RadioGroup<AppLanguage>(
                  groupValue: widget.selected,
                  onChanged: _select,
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final AppLanguage language in AppLanguage.values)
                        RadioListTile<AppLanguage>(
                          key: ValueKey<AppLanguage>(language),
                          value: language,
                          enabled: !_saving,
                          title: Text(
                            language == AppLanguage.system
                                ? 'Use device language'.tr(context)
                                : language.displayName,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_saving) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                "Couldn't save app language: {error}"
                    .tr(context)
                    .replaceAll('{error}', _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text('Close'.tr(context)),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.bodyLarge),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
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
    final ValueChanged<bool>? onChanged = this.onChanged;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.bodyLarge),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
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

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<int> chosen = <int>[
      for (final PortfolioEntity portfolio in widget.portfolios)
        if (_selected[portfolio.id] == true) portfolio.id,
    ];
    final String password = _password.text;
    final String confirm = _confirm.text;
    final bool mismatch = confirm.isNotEmpty && password != confirm;
    final bool canExport =
        chosen.isNotEmpty && password.length >= 4 && password == confirm;

    return AlertDialog(
      title: Text('Export portfolios'.tr(context)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              "Choose portfolios and set a password. You'll need this exact "
                      'password to import the file again.'
                  .tr(context),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final PortfolioEntity portfolio in widget.portfolios)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _selected[portfolio.id] ?? false,
                onChanged: (bool? value) =>
                    setState(() => _selected[portfolio.id] = value ?? false),
                title: Text(portfolio.name),
              ),
            const SizedBox(height: 8),
            _PasswordField(
              controller: _password,
              label: 'Password'.tr(context),
              visible: _visible,
              onToggleVisibility: () => setState(() => _visible = !_visible),
              onChanged: (_) => setState(() {}),
              isError: password.isNotEmpty && password.length < 4,
              supportingText: password.isNotEmpty && password.length < 4
                  ? 'Use at least 4 characters'.tr(context)
                  : null,
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
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr(context)),
        ),
        TextButton(
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
        border: const OutlineInputBorder(),
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
