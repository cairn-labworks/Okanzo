import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import '../../di/app_container.dart';
import '../../domain/model/liability_type.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../asset/asset_edit_view_model.dart' show AssetEditEventType;
import '../components/form_components.dart';
import '../components/holding_editor_guard.dart';
import '../components/type_icons.dart';
import '../components/ui_components.dart';
import 'liability_edit_view_model.dart';
import 'liability_form_state.dart';

/// Create or edit a single liability.
class LiabilityEditScreen extends StatefulWidget {
  const LiabilityEditScreen({
    required this.portfolioId,
    required this.liabilityId,
    super.key,
  });

  final int portfolioId;
  final int liabilityId;

  @override
  State<LiabilityEditScreen> createState() => _LiabilityEditScreenState();
}

class _LiabilityEditScreenState extends State<LiabilityEditScreen> {
  LiabilityEditViewModel? _viewModel;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _nameFocus = FocusNode();
  bool _controllersPrimed = false;
  LiabilityFormState? _initialForm;
  final GlobalKey<HoldingEditorGuardState> _guard =
      GlobalKey<HoldingEditorGuardState>();

  Map<FocusNode, TextEditingController> get _requiredFields =>
      <FocusNode, TextEditingController>{
        _amountFocus: _amount,
        _nameFocus: _name,
      };

  void _focusNextRequired() => focusNextRequiredField(context, _requiredFields);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final AppContainer container = AppScope.of(context);
    _viewModel = LiabilityEditViewModel(
      liabilityRepository: container.liabilityRepository,
      settingsRepository: container.settingsRepository,
      portfolioId: widget.portfolioId,
      liabilityId: widget.liabilityId,
    )..addListener(_onChanged);
  }

  void _onChanged() {
    final LiabilityEditViewModel viewModel = _viewModel!;
    final LiabilityEditEvent? event = viewModel.event;
    if (event == null || !mounted) return;
    viewModel.consumeEvent();
    switch (event.type) {
      case AssetEditEventType.saved:
      case AssetEditEventType.deleted:
        unawaited(_guard.currentState!.close());
      case AssetEditEventType.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((event.message ?? '').tr(context))),
        );
    }
  }

  void _primeControllers(LiabilityFormState form) {
    if (_controllersPrimed) return;
    _controllersPrimed = true;
    _initialForm = form;
    _name.text = form.name;
    _amount.text = form.amount;
    _notes.text = form.notes;
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onChanged);
    _viewModel?.dispose();
    _name.dispose();
    _amount.dispose();
    _notes.dispose();
    _amountFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LiabilityEditViewModel viewModel = _viewModel!;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (BuildContext context, _) {
        final LiabilityFormState form = viewModel.form;
        if (!form.loading) _primeControllers(form);
        final bool dirty =
            _initialForm != null &&
            !mapEquals(
              _initialForm!.toEntity(now: 0).toMap(),
              form.toEntity(now: 0).toMap(),
            );
        return HoldingEditorGuard(
          key: _guard,
          dirty: dirty || form.isSaving,
          onDiscard: () {},
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 48,
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 16),
                  child: Center(
                    child: Text(
                      'OKANZO',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (form.isEditing)
                  IconButton(
                    tooltip: 'Delete'.tr(context),
                    onPressed: form.isSaving
                        ? null
                        : () async {
                            if (await confirmHoldingDeletion(
                              context,
                              form.name,
                            )) {
                              await viewModel.delete();
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            bottomNavigationBar: form.loading
                ? null
                : Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: SafeArea(
                      minimum: const EdgeInsets.fromLTRB(26, 12, 26, 12),
                      child: FormActionRow(
                        showCancel: false,
                        isSaving: form.isSaving,
                        onCancel: null,
                        onSave: form.isSaving || form.validate() != null
                            ? null
                            : () {
                                FocusScope.of(context).unfocus();
                                unawaited(viewModel.save());
                              },
                      ),
                    ),
                  ),
            body: form.loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 12,
                    ),
                    children: <Widget>[
                      PageHeading(
                        (form.isEditing ? 'Edit liability' : 'Add liability')
                            .tr(context),
                      ),
                      const SizedBox(height: 20),
                      LabeledTextField(
                        controller: _amount,
                        focusNode: _amountFocus,
                        textInputAction: requiredFieldInputAction(
                          _requiredFields,
                          current: _amountFocus,
                        ),
                        onSubmitted: (_) => _focusNextRequired(),
                        autofocus: !form.isEditing,
                        label: 'Outstanding amount'.tr(context),
                        prefix: CurrencyUtil.symbol(form.currency),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        prominent: true,
                        supportingText: 'The amount you still owe'.tr(context),
                        onChanged: viewModel.onAmountChange,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: <Widget>[
                          DropdownSelector<LiabilityType>(
                            label: 'Type'.tr(context),
                            selected: form.type,
                            options: LiabilityType.values,
                            optionLabel: (LiabilityType type) =>
                                type.displayName.tr(context),
                            optionIcon: liabilityTypeIcon,
                            onSelected: (LiabilityType type) {
                              viewModel.onTypeChange(type);
                              _focusNextRequired();
                            },
                            compact: true,
                          ),
                          CurrencySelector(
                            currency: form.currency,
                            compact: true,
                            onTap: () => _pickCurrency(form.currency),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LabeledTextField(
                        controller: _name,
                        focusNode: _nameFocus,
                        textInputAction: requiredFieldInputAction(
                          _requiredFields,
                          current: _nameFocus,
                        ),
                        onSubmitted: (_) => _focusNextRequired(),
                        label: 'Name'.tr(context),
                        placeholder: 'e.g. Home loan'.tr(context),
                        maxLength: 60,
                        onChanged: viewModel.onNameChange,
                      ),
                      const SizedBox(height: 16),
                      OptionalNotesField(
                        controller: _notes,
                        onChanged: viewModel.onNotesChange,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Future<void> _pickCurrency(String current) async {
    final String? picked = await showCurrencyPickerDialog(
      context,
      selected: current,
    );
    if (picked != null && mounted) {
      _viewModel?.onCurrencyChange(picked);
      _focusNextRequired();
    }
  }
}
