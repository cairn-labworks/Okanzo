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
import '../components/holding_editor_chrome.dart';
import '../components/holding_saved_summary_screen.dart';
import '../components/type_icons.dart';
import 'liability_edit_view_model.dart';
import 'liability_form_state.dart';

/// Create or edit a single liability.
class LiabilityEditScreen extends StatefulWidget {
  const LiabilityEditScreen({
    required this.portfolioId,
    required this.liabilityId,
    this.viewModel,
    this.hasUnsavedChanges,
    this.onKindSelected,
    super.key,
  });

  final int portfolioId;
  final int liabilityId;
  final LiabilityEditViewModel? viewModel;
  final bool? hasUnsavedChanges;
  final ValueChanged<bool>? onKindSelected;

  @override
  State<LiabilityEditScreen> createState() => _LiabilityEditScreenState();
}

class _LiabilityEditScreenState extends State<LiabilityEditScreen> {
  LiabilityEditViewModel? _viewModel;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _amount = TextEditingController();
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
    _viewModel =
        widget.viewModel ??
        LiabilityEditViewModel(
          liabilityRepository: container.liabilityRepository,
          settingsRepository: container.settingsRepository,
          portfolioId: widget.portfolioId,
          liabilityId: widget.liabilityId,
        );
    _viewModel!.addListener(_onChanged);
  }

  void _onChanged() {
    final LiabilityEditViewModel viewModel = _viewModel!;
    final LiabilityEditEvent? event = viewModel.event;
    if (event == null || !mounted) return;
    viewModel.consumeEvent();
    switch (event.type) {
      case AssetEditEventType.saved:
        final saved = event.savedLiability ?? viewModel.form.toEntity();
        unawaited(
          _guard.currentState!.close(
            replacement: MaterialPageRoute<void>(
              builder: (_) => HoldingSavedSummaryScreen(
                portfolioId: widget.portfolioId,
                updated: widget.liabilityId != 0,
                savedLiability: saved,
                previousLiability: event.previousLiability,
                notice: event.message,
              ),
            ),
          ),
        );
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
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onChanged);
    if (widget.viewModel == null) _viewModel?.dispose();
    _name.dispose();
    _amount.dispose();
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
          dirty: (widget.hasUnsavedChanges ?? dirty) || form.isSaving,
          onDiscard: () {},
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 48,
              centerTitle: true,
              title: Text(
                'OKANZO',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 16),
                  child: Center(
                    child: HoldingPortfolioLabel(
                      portfolioId: widget.portfolioId,
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
                : HoldingEditorFooter(
                    portfolioId: widget.portfolioId,
                    asset: false,
                    amount: double.tryParse(form.amount) ?? 0,
                    currency: form.currency,
                    saving: form.isSaving,
                    ready: form.validate() == null,
                    onSave: () {
                      FocusScope.of(context).unfocus();
                      unawaited(viewModel.save());
                    },
                  ),
            body: form.loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    children: <Widget>[
                      HoldingEditorHeading(
                        portfolioId: widget.portfolioId,
                        asset: false,
                        onKindSelected: widget.onKindSelected,
                        enabled: !form.isSaving,
                        title:
                            (form.isEditing
                                    ? 'Edit liability'
                                    : 'Add liability')
                                .tr(context),
                      ),
                      LabeledTextField(
                        canvas: true,
                        controller: _amount,
                        focusNode: _amountFocus,
                        textInputAction: requiredFieldInputAction(
                          _requiredFields,
                          current: _amountFocus,
                        ),
                        onSubmitted: (_) => _focusNextRequired(),
                        autofocus: !form.isEditing,
                        label: 'Outstanding amount'.tr(context),
                        placeholder: '0.00',
                        prefix: CurrencyUtil.symbol(form.currency),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        prominent: true,
                        supportingText: 'The amount you still owe'.tr(context),
                        onChanged: viewModel.onAmountChange,
                      ),
                      const SizedBox(height: 12),
                      FormFieldPair(
                        first: DropdownSelector<LiabilityType>(
                          canvas: true,
                          label: 'Type'.tr(context),
                          dialogEyebrow: 'What you owe'.tr(context),
                          dialogTitle: 'Choose a type'.tr(context),
                          searchPlaceholder: 'e.g. Loan, Mortgage, Credit card'
                              .tr(context),
                          supportingText: 'e.g. Loan, Mortgage, Credit card'.tr(
                            context,
                          ),
                          selected: form.type,
                          options: LiabilityType.values,
                          optionLabel: (LiabilityType type) =>
                              type.displayName.tr(context),
                          optionSubtitle: (LiabilityType type) =>
                              type.pickerHint.tr(context),
                          optionIcon: liabilityTypeIcon,
                          onSelected: (LiabilityType type) {
                            viewModel.onTypeChange(type);
                            _focusNextRequired();
                          },
                          compact: true,
                        ),
                        second: CurrencySelector(
                          canvas: true,
                          currency: form.currency,
                          supportingText: 'e.g. INR, USD, EUR, GBP'.tr(context),
                          compact: true,
                          onTap: () => _pickCurrency(form.currency),
                        ),
                      ),
                      const SizedBox(height: 14),
                      LabeledTextField(
                        canvas: true,
                        controller: _name,
                        focusNode: _nameFocus,
                        textInputAction: requiredFieldInputAction(
                          _requiredFields,
                          current: _nameFocus,
                        ),
                        onSubmitted: (_) => _focusNextRequired(),
                        label: 'Name'.tr(context),
                        placeholder: form.type.nameExample.tr(context),
                        maxLength: 60,
                        onChanged: viewModel.onNameChange,
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
