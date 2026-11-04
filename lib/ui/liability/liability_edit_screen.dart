import 'package:flutter/material.dart';

import '../../di/app_container.dart';
import '../../domain/model/liability_type.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../asset/asset_edit_view_model.dart' show AssetEditEventType;
import '../components/form_components.dart';
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
  bool _controllersPrimed = false;

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
        Navigator.of(context).pop();
      case AssetEditEventType.error:
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text((event.message ?? '').tr)));
    }
  }

  void _primeControllers(LiabilityFormState form) {
    if (_controllersPrimed) return;
    _controllersPrimed = true;
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
        return Scaffold(
          appBar: AppBar(
            title: Text(
              (form.isEditing ? 'Edit liability' : 'New liability').tr,
            ),
            actions: <Widget>[
              if (form.isEditing)
                IconButton(
                  tooltip: 'Delete'.tr,
                  onPressed: viewModel.delete,
                  icon: const Icon(Icons.delete),
                ),
              TextButton(
                onPressed: form.isSaving ? null : viewModel.save,
                child: Text('Save'.tr),
              ),
            ],
          ),
          body: form.loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  children: <Widget>[
                    DropdownSelector<LiabilityType>(
                      label: 'Type'.tr,
                      selected: form.type,
                      options: LiabilityType.values,
                      optionLabel: (LiabilityType type) =>
                          type.displayName.tr,
                      onSelected: viewModel.onTypeChange,
                    ),
                    const SizedBox(height: 16),
                    LabeledTextField(
                      controller: _name,
                      label: 'Name'.tr,
                      placeholder: 'e.g. Home loan'.tr,
                      onChanged: viewModel.onNameChange,
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () => _pickCurrency(form.currency),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: 'Currency'.tr,
                        ),
                        child: Text(
                          '${form.currency} — '
                          '${CurrencyUtil.displayName(form.currency)}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LabeledTextField(
                      controller: _amount,
                      label: 'Outstanding amount'.tr,
                      prefix: CurrencyUtil.symbol(form.currency),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: viewModel.onAmountChange,
                    ),
                    const SizedBox(height: 16),
                    LabeledTextField(
                      controller: _notes,
                      label: 'Notes (optional)'.tr,
                      singleLine: false,
                      onChanged: viewModel.onNotesChange,
                    ),
                  ],
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
    if (picked != null) _viewModel?.onCurrencyChange(picked);
  }
}
