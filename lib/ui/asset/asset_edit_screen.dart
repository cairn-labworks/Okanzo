import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import '../../data/remote/stock/stock_search_service.dart';
import '../../di/app_container.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/stock_exchange.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/form_components.dart';
import '../components/holding_editor_guard.dart';
import '../components/holding_editor_chrome.dart';
import '../components/type_icons.dart';
import '../components/ui_components.dart';
import 'asset_edit_view_model.dart';
import 'asset_form_state.dart';
import 'stock_exchange_field.dart';
import 'stock_search_field.dart';

/// Create or edit a single asset.
class AssetEditScreen extends StatefulWidget {
  const AssetEditScreen({
    required this.portfolioId,
    required this.assetId,
    this.viewModel,
    this.hasUnsavedChanges,
    this.onKindSelected,
    super.key,
  });

  final int portfolioId;
  final int assetId;
  final AssetEditViewModel? viewModel;
  final bool? hasUnsavedChanges;
  final ValueChanged<bool>? onKindSelected;

  @override
  State<AssetEditScreen> createState() => _AssetEditScreenState();
}

class _AssetEditScreenState extends State<AssetEditScreen> {
  AssetEditViewModel? _viewModel;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _customName = TextEditingController();
  final TextEditingController _symbol = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _pricePerUnit = TextEditingController();
  final TextEditingController _manualValue = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _symbolFocus = FocusNode();
  final FocusNode _quantityFocus = FocusNode();
  final FocusNode _pricePerUnitFocus = FocusNode();
  final FocusNode _manualValueFocus = FocusNode();
  bool _controllersPrimed = false;
  AssetFormState? _initialForm;
  bool _searchSelection = false;
  final GlobalKey<HoldingEditorGuardState> _guard =
      GlobalKey<HoldingEditorGuardState>();

  Map<FocusNode, TextEditingController> get _requiredFields =>
      switch (_viewModel!.form.valuationMode) {
        ValuationMode.market => <FocusNode, TextEditingController>{
          _symbolFocus: _symbol,
          _quantityFocus: _quantity,
        },
        ValuationMode.quantity => <FocusNode, TextEditingController>{
          _nameFocus: _name,
          _quantityFocus: _quantity,
          _pricePerUnitFocus: _pricePerUnit,
        },
        ValuationMode.flat => <FocusNode, TextEditingController>{
          _manualValueFocus: _manualValue,
          _nameFocus: _name,
        },
      };

  void _focusNextRequired() => focusNextRequiredField(context, _requiredFields);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final AppContainer container = AppScope.of(context);
    _viewModel =
        widget.viewModel ??
        AssetEditViewModel(
          assetRepository: container.assetRepository,
          settingsRepository: container.settingsRepository,
          portfolioId: widget.portfolioId,
          assetId: widget.assetId,
        );
    _viewModel!.addListener(_onChanged);
  }

  void _onChanged() {
    final AssetEditViewModel viewModel = _viewModel!;
    final AssetEditEvent? event = viewModel.event;
    if (event == null || !mounted) return;
    viewModel.consumeEvent();
    switch (event.type) {
      case AssetEditEventType.saved:
      case AssetEditEventType.deleted:
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        final String? notice = event.message?.tr(context);
        unawaited(_guard.currentState!.close());
        if (notice != null && notice.isNotEmpty) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(notice)));
        }
      case AssetEditEventType.error:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text((event.message ?? '').tr(context))),
          );
    }
  }

  void _primeControllers(AssetFormState form) {
    if (_controllersPrimed) return;
    _controllersPrimed = true;
    _initialForm = form;
    _name.text = form.name;
    _customName.text = form.customName;
    _symbol.text = form.symbol;
    _quantity.text = form.quantity;
    _pricePerUnit.text = form.pricePerUnit;
    _manualValue.text = form.manualValue;
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onChanged);
    if (widget.viewModel == null) _viewModel?.dispose();
    _name.dispose();
    _customName.dispose();
    _symbol.dispose();
    _quantity.dispose();
    _pricePerUnit.dispose();
    _manualValue.dispose();
    _nameFocus.dispose();
    _symbolFocus.dispose();
    _quantityFocus.dispose();
    _pricePerUnitFocus.dispose();
    _manualValueFocus.dispose();
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
        final bool dirty =
            _initialForm != null &&
            !mapEquals(
              _initialForm!.toEntity(now: 0).toMap(),
              form.toEntity(now: 0).toMap(),
            );
        return HoldingEditorGuard(
          key: _guard,
          dirty:
              (widget.hasUnsavedChanges ?? dirty) ||
              form.isSaving ||
              form.isFetchingPrice,
          onDiscard: viewModel.cancel,
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
                              form.toEntity().displayName,
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
                    asset: true,
                    amount: form.estimatedValue,
                    currency: form.currency,
                    priced: !form.type.isMarketLinked || form.lastPrice != null,
                    saving: form.isSaving,
                    ready: !form.isFetchingPrice && form.validate() == null,
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
                        asset: true,
                        onKindSelected: widget.onKindSelected,
                        enabled: !form.isSaving && !form.isFetchingPrice,
                        title: (form.isEditing ? 'Edit asset' : 'Add asset').tr(
                          context,
                        ),
                      ),
                      if (form.valuationMode == ValuationMode.flat)
                        LabeledTextField(
                          canvas: true,
                          controller: _manualValue,
                          focusNode: _manualValueFocus,
                          textInputAction: requiredFieldInputAction(
                            _requiredFields,
                            current: _manualValueFocus,
                          ),
                          onSubmitted: (_) => _focusNextRequired(),
                          autofocus: !form.isEditing,
                          label: 'Value'.tr(context),
                          placeholder: '0.00',
                          supportingText: 'Your estimate of its value today. Zero is allowed.'
                              .tr(context),
                          prefix: CurrencyUtil.symbol(form.currency),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          prominent: true,
                          onChanged: viewModel.onManualValueChange,
                        )
                      else
                        _EstimatedValueSummary(
                          amount:
                              form.type.isMarketLinked && form.lastPrice == null
                              ? 'Price pending'.tr(context)
                              : CurrencyUtil.format(
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
                      FormFieldPair(
                        first: DropdownSelector<AssetType>(
                          canvas: true,
                          label: 'Type'.tr(context),
                          selected: form.type,
                          options: AssetType.values,
                          optionLabel: (AssetType type) =>
                              type.displayName.tr(context),
                          optionIcon: assetTypeIcon,
                          onSelected: (AssetType type) {
                            viewModel.onTypeChange(type);
                            _searchSelection = false;
                            _name.text = viewModel.form.name;
                            _customName.text = viewModel.form.customName;
                            _focusNextRequired();
                          },
                          compact: true,
                        ),
                        second: CurrencySelector(
                          canvas: true,
                          currency: form.currency,
                          compact: true,
                          onTap: () => _pickCurrency(form.currency),
                        ),
                      ),
                      if (form.usesStockExchange) ...<Widget>[
                        const SizedBox(height: 18),
                        StockExchangeField(
                          canvas: true,
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
                            _focusNextRequired();
                          },
                        ),
                      ],
                      if (!form.type.isMarketLinked) ...<Widget>[
                        const SizedBox(height: 12),
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
                          placeholder: 'e.g. Apple shares'.tr(context),
                          maxLength: 60,
                          onChanged: viewModel.onNameChange,
                        ),
                      ],
                      const SizedBox(height: 12),
                      ..._valuationFields(form, viewModel),
                      const SizedBox(height: 8),
                      HoldingNetWorthPreview(
                        portfolioId: widget.portfolioId,
                        holdingId: widget.assetId,
                        asset: true,
                        value: form.estimatedValue,
                        currency: form.currency,
                        priced:
                            !form.type.isMarketLinked || form.lastPrice != null,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        );
      },
    );
  }

  List<Widget> _valuationFields(
    AssetFormState form,
    AssetEditViewModel viewModel,
  ) {
    switch (form.valuationMode) {
      case ValuationMode.market:
        final Widget quantityField = LabeledTextField(
          canvas: true,
          controller: _quantity,
          focusNode: _quantityFocus,
          textInputAction: requiredFieldInputAction(
            _requiredFields,
            current: _quantityFocus,
          ),
          onSubmitted: (_) => _focusNextRequired(),
          label: 'Quantity'.tr(context),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: viewModel.onQuantityChange,
        );
        return <Widget>[
          if (form.name.trim().isNotEmpty && !_searchSelection) ...<Widget>[
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(13),
              child: ListTile(
                key: const ValueKey<String>('selected-market-holding'),
                leading: TypeAvatar(assetTypeIcon(form.type)),
                title: Text(form.name),
                subtitle: Text('${form.quoteSymbol} / ${form.currency}'),
                trailing: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.primary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                onTap: () {
                  setState(() => _searchSelection = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _symbolFocus.requestFocus();
                    _symbol.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _symbol.text.length,
                    );
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            quantityField,
          ] else
            StockSearchField(
              canvas: true,
              controller: _symbol,
              focusNode: _symbolFocus,
              textInputAction: requiredFieldInputAction(
                _requiredFields,
                current: _symbolFocus,
              ),
              onSubmitted: (_) => _focusNextRequired(),
              service: AppScope.of(context).stockSearchService,
              type: switch (form.type) {
                AssetType.crypto => StockSearchType.crypto,
                AssetType.mutualFund => StockSearchType.fund,
                _ => StockSearchType.stock,
              },
              quantityField: quantityField,
              onChanged: viewModel.onSymbolChange,
              onSelected: (result) {
                _searchSelection = false;
                viewModel.onStockSelected(result);
                _symbol.text = viewModel.form.symbol;
                _focusNextRequired();
                unawaited(viewModel.fetchPrice());
              },
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: form.isFetchingPrice || form.isSaving
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      unawaited(viewModel.fetchPrice());
                    },
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
          const SizedBox(height: 12),
          LabeledTextField(
            canvas: true,
            controller: _customName,
            textInputAction: requiredFieldInputAction(_requiredFields),
            onSubmitted: (_) => _focusNextRequired(),
            label: 'Custom name (optional)'.tr(context),
            maxLength: 60,
            placeholder: form.name.trim().isNotEmpty ? form.name.trim() : null,
            onChanged: viewModel.onCustomNameChange,
          ),
        ];
      case ValuationMode.quantity:
        return <Widget>[
          FormFieldPair(
            first: LabeledTextField(
              canvas: true,
              controller: _quantity,
              focusNode: _quantityFocus,
              textInputAction: requiredFieldInputAction(
                _requiredFields,
                current: _quantityFocus,
              ),
              onSubmitted: (_) => _focusNextRequired(),
              label: 'Quantity'.tr(context),
              suffix: form.type.unitLabel,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: viewModel.onQuantityChange,
            ),
            second: LabeledTextField(
              canvas: true,
              controller: _pricePerUnit,
              focusNode: _pricePerUnitFocus,
              textInputAction: requiredFieldInputAction(
                _requiredFields,
                current: _pricePerUnitFocus,
              ),
              onSubmitted: (_) => _focusNextRequired(),
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
      _focusNextRequired();
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
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Estimated value'.tr(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            amount,
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 32,
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
