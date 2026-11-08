import 'package:flutter/material.dart';

import '../../di/app_container.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/stock_exchange.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/form_components.dart';
import '../components/ui_components.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((event.message ?? '').tr(context))),
        );
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
                  onPressed: viewModel.delete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
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
                      (form.isEditing ? 'Edit asset' : 'Add asset').tr(context),
                    ),
                    const SizedBox(height: 20),
                    if (form.valuationMode == ValuationMode.flat)
                      LabeledTextField(
                        controller: _manualValue,
                        label: 'Value'.tr(context),
                        prefix: CurrencyUtil.symbol(form.currency),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        prominent: true,
                        onChanged: viewModel.onManualValueChange,
                      )
                    else
                      _EstimatedValueSummary(
                        amount: CurrencyUtil.format(
                          form.estimatedValue,
                          form.currency,
                        ),
                        caption: form.valuationMode == ValuationMode.market
                            ? form.lastPrice == null
                                  ? null
                                  : '${form.quantity.isEmpty ? '0' : form.quantity} × '
                                        '${CurrencyUtil.format(form.lastPrice!, form.currency)}'
                            : '${form.quantity.isEmpty ? '0' : form.quantity} × '
                                  '${CurrencyUtil.format(double.tryParse(form.pricePerUnit) ?? 0, form.currency)}',
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        DropdownSelector<AssetType>(
                          label: 'Type'.tr(context),
                          selected: form.type,
                          options: AssetType.values,
                          optionLabel: (AssetType type) =>
                              type.displayName.tr(context),
                          onSelected: viewModel.onTypeChange,
                          compact: true,
                        ),
                        CurrencySelector(
                          currency: form.currency,
                          compact: true,
                          onTap: () => _pickCurrency(form.currency),
                        ),
                        if (form.usesStockExchange)
                          StockExchangeField(
                            selected:
                                form.isEditing ||
                                    form.symbol.trim().isNotEmpty ||
                                    viewModel.preferredExchanges.contains(
                                      form.exchange,
                                    )
                                ? form.exchange
                                : null,
                            preferredExchanges: viewModel.preferredExchanges,
                            onSavePreferences: viewModel.savePreferredExchanges,
                            compact: true,
                            onSelected: (StockExchange exchange) {
                              viewModel.onExchangeChange(exchange);
                              _symbol.text = viewModel.form.symbol;
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LabeledTextField(
                      controller: _name,
                      label: 'Name'.tr(context),
                      placeholder: 'e.g. Apple shares'.tr(context),
                      onChanged: viewModel.onNameChange,
                    ),
                    const SizedBox(height: 12),
                    ..._valuationFields(form, viewModel),
                    const SizedBox(height: 8),
                    OptionalNotesField(
                      key: const ValueKey<String>('asset-notes'),
                      controller: _notes,
                      onChanged: viewModel.onNotesChange,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: form.isSaving || form.isFetchingPrice
                          ? null
                          : viewModel.save,
                      child: Text('Save asset'.tr(context)),
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
          FormFieldPair(
            first: LabeledTextField(
              controller: _symbol,
              label: 'Ticker symbol'.tr(context),
              placeholder: form.usesStockExchange
                  ? 'e.g. {symbol}'
                        .tr(context)
                        .replaceAll('{symbol}', form.exchange.example)
                  : 'e.g. {symbol}'
                        .tr(context)
                        .replaceAll('{symbol}', 'BTC-USD, ETH-USD'),
              onChanged: viewModel.onSymbolChange,
            ),
            second: LabeledTextField(
              controller: _quantity,
              label: 'Quantity'.tr(context),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: viewModel.onQuantityChange,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: form.isFetchingPrice ? null : viewModel.fetchPrice,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: AlignmentDirectional.centerStart,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (form.isFetchingPrice)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.refresh, size: 16),
                  const SizedBox(width: 6),
                  Flexible(child: Text('Fetch latest price'.tr(context))),
                ],
              ),
            ),
          ),
          if (form.lastPrice == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Fetch the latest closing price, or it will show as 0 '
                        'until refreshed.'
                    .tr(context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ];
      case ValuationMode.quantity:
        return <Widget>[
          FormFieldPair(
            first: LabeledTextField(
              controller: _quantity,
              label: 'Quantity'.tr(context),
              suffix: form.type.unitLabel,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: viewModel.onQuantityChange,
            ),
            second: LabeledTextField(
              controller: _pricePerUnit,
              label: 'Price per {unit}'
                  .tr(context)
                  .replaceAll('{unit}', form.type.unitLabel ?? 'unit'),
              prefix: CurrencyUtil.symbol(form.currency),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: viewModel.onPricePerUnitChange,
            ),
          ),
        ];
      case ValuationMode.flat:
        return const <Widget>[];
    }
  }

  Future<void> _pickCurrency(String current) async {
    final String? picked = await showCurrencyPickerDialog(
      context,
      selected: current,
    );
    if (picked != null && mounted) {
      await _viewModel?.onCurrencyChange(picked);
    }
  }
}

class _EstimatedValueSummary extends StatelessWidget {
  const _EstimatedValueSummary({required this.amount, this.caption});

  final String amount;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Estimated value'.tr(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            amount,
            style: theme.textTheme.displaySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (caption != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              caption!,
              key: const ValueKey<String>('asset-valuation-caption'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
