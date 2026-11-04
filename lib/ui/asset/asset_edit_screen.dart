import 'package:flutter/material.dart';

import '../../di/app_container.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/stock_exchange.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/form_components.dart';
import '../theme/theme.dart';
import 'asset_edit_view_model.dart';
import 'asset_form_state.dart';
import 'stock_exchange_field.dart';

/// Create or edit a single asset.
class AssetEditScreen extends StatefulWidget {
  const AssetEditScreen({
    required this.portfolioId,
    required this.assetId,
    super.key,
  });

  final int portfolioId;
  final int assetId;

  @override
  State<AssetEditScreen> createState() => _AssetEditScreenState();
}

class _AssetEditScreenState extends State<AssetEditScreen> {
  AssetEditViewModel? _viewModel;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _symbol = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _pricePerUnit = TextEditingController();
  final TextEditingController _manualValue = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  bool _controllersPrimed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final AppContainer container = AppScope.of(context);
    _viewModel = AssetEditViewModel(
      assetRepository: container.assetRepository,
      settingsRepository: container.settingsRepository,
      portfolioId: widget.portfolioId,
      assetId: widget.assetId,
    )..addListener(_onChanged);
  }

  void _onChanged() {
    final AssetEditViewModel viewModel = _viewModel!;
    final AssetEditEvent? event = viewModel.event;
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

  void _primeControllers(AssetFormState form) {
    if (_controllersPrimed) return;
    _controllersPrimed = true;
    _name.text = form.name;
    _symbol.text = form.symbol;
    _quantity.text = form.quantity;
    _pricePerUnit.text = form.pricePerUnit;
    _manualValue.text = form.manualValue;
    _notes.text = form.notes;
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onChanged);
    _viewModel?.dispose();
    _name.dispose();
    _symbol.dispose();
    _quantity.dispose();
    _pricePerUnit.dispose();
    _manualValue.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AssetEditViewModel viewModel = _viewModel!;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (BuildContext context, _) {
        final AssetFormState form = viewModel.form;
        if (!form.loading) _primeControllers(form);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              (form.isEditing ? 'Edit asset' : 'New asset').tr,
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
                    DropdownSelector<AssetType>(
                      label: 'Type'.tr,
                      selected: form.type,
                      options: AssetType.values,
                      optionLabel: (AssetType type) => type.displayName.tr,
                      onSelected: viewModel.onTypeChange,
                    ),
                    const SizedBox(height: 16),
                    LabeledTextField(
                      controller: _name,
                      label: 'Name'.tr,
                      placeholder: 'e.g. Apple shares'.tr,
                      onChanged: viewModel.onNameChange,
                    ),
                    const SizedBox(height: 16),
                    _CurrencyField(
                      currency: form.currency,
                      onTap: () => _pickCurrency(form.currency),
                    ),
                    const SizedBox(height: 16),
                    ..._valuationFields(form, viewModel),
                    const SizedBox(height: 16),
                    LabeledTextField(
                      controller: _notes,
                      label: 'Notes (optional)'.tr,
                      singleLine: false,
                      onChanged: viewModel.onNotesChange,
                    ),
                    const SizedBox(height: 16),
                    _EstimatedValueCard(
                      amount: CurrencyUtil.format(
                        form.estimatedValue,
                        form.currency,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
        );
      },
    );
  }

  List<Widget> _valuationFields(
    AssetFormState form,
    AssetEditViewModel viewModel,
  ) {
    final ThemeData theme = Theme.of(context);
    switch (form.valuationMode) {
      case ValuationMode.market:
        return <Widget>[
          if (form.usesStockExchange) ...<Widget>[
            StockExchangeField(
              selected:
                  form.isEditing ||
                      form.symbol.trim().isNotEmpty ||
                      viewModel.preferredExchanges.contains(form.exchange)
                  ? form.exchange
                  : null,
              preferredExchanges: viewModel.preferredExchanges,
              onSavePreferences: viewModel.savePreferredExchanges,
              onSelected: (StockExchange exchange) {
                viewModel.onExchangeChange(exchange);
                _symbol.text = viewModel.form.symbol;
              },
            ),
            const SizedBox(height: 16),
          ],
          LabeledTextField(
            controller: _symbol,
            label: 'Ticker symbol'.tr,
            placeholder: form.usesStockExchange
                ? 'e.g. ${form.exchange.example}'
                : 'e.g. BTC-USD, ETH-USD',
            supportingText: !form.usesStockExchange
                ? null
                : form.exchange.suffix.isEmpty
                ? 'Enter a Yahoo Finance ticker. Full exchange-qualified '
                      'tickers are also accepted.'
                : '${form.exchange.suffix} is added automatically. '
                      'Full Yahoo Finance tickers are also accepted.',
            onChanged: viewModel.onSymbolChange,
          ),
          const SizedBox(height: 16),
          LabeledTextField(
            controller: _quantity,
            label: 'Quantity'.tr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: viewModel.onQuantityChange,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: form.isFetchingPrice ? null : viewModel.fetchPrice,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (form.isFetchingPrice)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Text('Fetch latest price'.tr),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: form.lastPrice != null
                ? Text(
                    'Last price: {price}'
                        .tr
                        .replaceAll(
                          '{price}',
                          CurrencyUtil.format(form.lastPrice!, form.currency),
                        ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Text(
                    'Fetch the latest closing price, or it will show as 0 '
                            'until refreshed.'
                        .tr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ];
      case ValuationMode.quantity:
        return <Widget>[
          LabeledTextField(
            controller: _quantity,
            label: 'Quantity'.tr,
            suffix: form.type.unitLabel,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: viewModel.onQuantityChange,
          ),
          const SizedBox(height: 16),
          LabeledTextField(
            controller: _pricePerUnit,
            label: 'Price per {unit}'
                .tr
                .replaceAll('{unit}', form.type.unitLabel ?? 'unit'),
            prefix: CurrencyUtil.symbol(form.currency),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: viewModel.onPricePerUnitChange,
          ),
        ];
      case ValuationMode.flat:
        return <Widget>[
          LabeledTextField(
            controller: _manualValue,
            label: 'Value'.tr,
            prefix: CurrencyUtil.symbol(form.currency),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: viewModel.onManualValueChange,
          ),
        ];
    }
  }

  Future<void> _pickCurrency(String current) async {
    final String? picked = await showCurrencyPickerDialog(
      context,
      selected: current,
    );
    if (picked != null) _viewModel?.onCurrencyChange(picked);
  }
}

class _CurrencyField extends StatelessWidget {
  const _CurrencyField({required this.currency, required this.onTap});

  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'Currency'.tr,
        ),
        child: Text('$currency — ${CurrencyUtil.displayName(currency)}'),
      ),
    );
  }
}

class _EstimatedValueCard extends StatelessWidget {
  const _EstimatedValueCard({required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(shapeLarge),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Estimated value'.tr,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            Flexible(
              child: Text(
                amount,
                textAlign: TextAlign.end,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
