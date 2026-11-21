import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import '../../data/remote/stock/stock_search_service.dart';
import '../../di/app_container.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/precious_metal.dart';
import '../../domain/model/stock_exchange.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../components/form_components.dart';
import '../components/holding_editor_guard.dart';
import '../components/holding_editor_chrome.dart';
import '../components/holding_saved_summary_screen.dart';
import '../components/type_icons.dart';
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
  final FocusNode _metalFocus = FocusNode();
  final FocusNode _purityFocus = FocusNode();
  bool _controllersPrimed = false;
  AssetFormState? _initialForm;
  final GlobalKey<HoldingEditorGuardState> _guard =
      GlobalKey<HoldingEditorGuardState>();

  Map<FocusNode, TextEditingController> get _requiredFields =>
      switch (_viewModel!.form.valuationMode) {
        ValuationMode.market => <FocusNode, TextEditingController>{
          _symbolFocus: _symbol,
          _quantityFocus: _quantity,
        },
        ValuationMode.metal when _viewModel!.form.useTotalValue =>
          <FocusNode, TextEditingController>{
            _nameFocus: _name,
            _manualValueFocus: _manualValue,
          },
        ValuationMode.metal => <FocusNode, TextEditingController>{
          _nameFocus: _name,
          _quantityFocus: _quantity,
          _pricePerUnitFocus: _pricePerUnit,
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

  void _focusNextRequired() {
    final form = _viewModel!.form;
    if (form.type == AssetType.metals) {
      if (form.metal == null) {
        _metalFocus.requestFocus();
        return;
      }
      if (form.metal!.hasPurity && !form.useTotalValue && form.purity == null) {
        _purityFocus.requestFocus();
        return;
      }
    }
    focusNextRequiredField(context, _requiredFields);
  }

  StockExchange? _activeExchange(
    AssetFormState form,
    AssetEditViewModel viewModel,
  ) =>
      form.isEditing ||
          form.symbol.trim().isNotEmpty ||
          viewModel.preferredExchanges.contains(form.exchange)
      ? form.exchange
      : null;

  String _footerCalculation(BuildContext context, AssetFormState form) {
    final String qty = form.quantity.trim().isEmpty
        ? '0'
        : form.quantity.trim();
    switch (form.valuationMode) {
      case ValuationMode.market:
        if (form.lastPrice == null) {
          return '$qty × ${CurrencyUtil.format(0, form.currency)} · '
              '${'price not fetched yet'.tr(context)}';
        }
        return '$qty × ${CurrencyUtil.format(form.lastPrice!, form.currency)}';
      case ValuationMode.quantity:
        final double unitPrice = double.tryParse(form.pricePerUnit) ?? 0;
        final String unit = form.type.unitLabel == null
            ? ''
            : ' ${form.type.unitLabel}';
        return '$qty$unit × ${CurrencyUtil.format(unitPrice, form.currency)}';
      case ValuationMode.metal:
        if (form.useTotalValue) return 'Total value'.tr(context);
        final rate = form.metalRate;
        if (form.metal?.hasPurity == true && form.purity == null) {
          return 'Choose a metal and purity for an estimate.'.tr(context);
        }
        return rate == null
            ? '$qty g · ${'Price pending'.tr(context)}'
            : '$qty g × ${CurrencyUtil.formatRate(rate, form.currency)}'
                  '${form.customPrice ? ' · ${'Custom rate'.tr(context)}' : ''}';
      case ValuationMode.flat:
        return 'Current value in {currency}'
            .tr(context)
            .replaceAll('{currency}', form.currency);
    }
  }

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
    if (mounted &&
        viewModel.form.type == AssetType.metals &&
        !_pricePerUnitFocus.hasFocus &&
        _pricePerUnit.text != viewModel.form.pricePerUnit) {
      _pricePerUnit.text = viewModel.form.pricePerUnit;
    }
    final AssetEditEvent? event = viewModel.event;
    if (event == null || !mounted) return;
    viewModel.consumeEvent();
    switch (event.type) {
      case AssetEditEventType.saved:
        final saved = event.savedAsset ?? viewModel.form.toEntity();
        unawaited(
          _guard.currentState!.close(
            confirmationAfterClose: holdingSavedSummaryRoute(
              context,
              builder: (_) => HoldingSavedSummaryScreen(
                portfolioId: widget.portfolioId,
                updated: widget.assetId != 0,
                savedAsset: saved,
                previousAsset: event.previousAsset,
                notice: event.message,
              ),
            ),
          ),
        );
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
    _metalFocus.dispose();
    _purityFocus.dispose();
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
                    priced: form.type == AssetType.metals
                        ? form.useTotalValue ||
                              form.metal == null ||
                              form.metalRate != null
                        : !form.type.isMarketLinked || form.lastPrice != null,
                    calculation: _footerCalculation(context, form),
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
                      if (form.valuationMode == ValuationMode.flat) ...<Widget>[
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
                        ),
                        const SizedBox(height: 12),
                      ],
                      FormFieldPair(
                        first: DropdownSelector<AssetType>(
                          canvas: true,
                          label: 'Type'.tr(context),
                          dialogEyebrow: 'What you own'.tr(context),
                          dialogTitle: 'Choose a type'.tr(context),
                          searchPlaceholder:
                              'e.g. Stock, Cash, Valuables, Real estate'.tr(
                                context,
                              ),
                          supportingText:
                              'e.g. Stock, Cash, Valuables, Real estate'.tr(
                                context,
                              ),
                          selected: form.type,
                          options: [
                            for (final type in AssetType.values)
                              if (type != AssetType.gold) type,
                          ],
                          optionLabel: (AssetType type) =>
                              type.displayCategory.displayName.tr(context),
                          optionSubtitle: (AssetType type) =>
                              type.pickerHint.tr(context),
                          optionIcon: assetTypeIcon,
                          onSelected: (AssetType type) {
                            FocusScope.of(context).unfocus();
                            viewModel.onTypeChange(type);
                            _name.text = viewModel.form.name;
                            _customName.text = viewModel.form.customName;
                            _symbol.text = viewModel.form.symbol;
                            _quantity.text = viewModel.form.quantity;
                            _pricePerUnit.text = viewModel.form.pricePerUnit;
                            _manualValue.text = viewModel.form.manualValue;
                            if (type == AssetType.metals) {
                              unawaited(_pickMetal());
                            } else {
                              _focusNextRequired();
                            }
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
                      if (form.usesStockExchange) ...<Widget>[
                        const SizedBox(height: 18),
                        StockExchangeField(
                          canvas: true,
                          selected: _activeExchange(form, viewModel),
                          isMutualFund: form.type == AssetType.mutualFund,
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
                      if (form.type == AssetType.metals) ...<Widget>[
                        const SizedBox(height: 14),
                        _metalSelectors(form),
                      ],
                      if (!form.type.isMarketLinked) ...<Widget>[
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
                          placeholder:
                              (form.metal?.nameExample ?? form.type.nameExample)
                                  .tr(context),
                          maxLength: 60,
                          onChanged: viewModel.onNameChange,
                        ),
                      ],
                      const SizedBox(height: 14),
                      ..._valuationFields(form, viewModel),
                      const SizedBox(height: 56),
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
    final bool invalidQuantity =
        form.quantity.trim().isNotEmpty &&
        (double.tryParse(form.quantity.trim()) ?? 0) <= 0;
    switch (form.valuationMode) {
      case ValuationMode.market:
        final String quantityPlaceholder = switch (form.type) {
          AssetType.crypto =>
            'e.g. {symbol}'.tr(context).replaceAll('{symbol}', '0.25'),
          AssetType.mutualFund =>
            'e.g. {symbol}'.tr(context).replaceAll('{symbol}', '15'),
          _ => 'e.g. {symbol}'.tr(context).replaceAll('{symbol}', '10'),
        };
        final String quantityHint = switch (form.type) {
          AssetType.crypto => 'Fractional coins supported (e.g. 0.25)'.tr(
            context,
          ),
          AssetType.mutualFund => 'Units held (e.g. 15.5)'.tr(context),
          _ => 'Shares held (e.g. 10)'.tr(context),
        };
        final bool invalidSymbol =
            form.quoteSymbol.isNotEmpty &&
            !isValidTickerSymbol(
              form.quoteSymbol,
              isCrypto: form.type == AssetType.crypto,
            );
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
          placeholder: quantityPlaceholder,
          supportingText: invalidQuantity
              ? 'Enter a positive number (decimals allowed, e.g. 0.25).'.tr(
                  context,
                )
              : quantityHint,
          isError: invalidQuantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: viewModel.onQuantityChange,
        );
        return <Widget>[
          StockSearchField(
            canvas: true,
            controller: _symbol,
            focusNode: _symbolFocus,
            selectedName: form.name,
            selectedSymbol: form.quoteSymbol,
            currency: form.currency,
            exchange: form.usesStockExchange
                ? _activeExchange(form, viewModel)
                : null,
            errorText: invalidSymbol
                ? (form.type == AssetType.crypto
                          ? 'Search by name or enter a valid ticker (e.g. BTC or BTC-USD).'
                          : 'Search by name or enter a valid ticker (e.g. AAPL, AIR.PA, or 7203.T).')
                      .tr(context)
                : null,
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
            onManualSelected: (String ticker) {
              viewModel.onSymbolChange(ticker);
              _symbol.text = viewModel.form.symbol;
              _focusNextRequired();
            },
            onSelected: (result) {
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
          OptionalCustomNameField(
            key: ValueKey<AssetType>(form.type),
            controller: _customName,
            textInputAction: requiredFieldInputAction(_requiredFields),
            onSubmitted: (_) => _focusNextRequired(),
            label: 'Custom name (optional)'.tr(context),
            maxLength: 60,
            placeholder: form.name.trim().isNotEmpty
                ? form.name.trim()
                : form.type.nameExample.tr(context),
            onChanged: viewModel.onCustomNameChange,
          ),
        ];
      case ValuationMode.quantity:
        final bool invalidUnitPrice =
            form.pricePerUnit.trim().isNotEmpty &&
            (double.tryParse(form.pricePerUnit.trim()) ?? 0) <= 0;
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
              placeholder: 'e.g. {symbol}'
                  .tr(context)
                  .replaceAll('{symbol}', '10'),
              supportingText: invalidQuantity
                  ? 'Enter a positive number (decimals allowed, e.g. 0.25).'.tr(
                      context,
                    )
                  : 'Total weight in grams'.tr(context),
              isError: invalidQuantity,
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
              placeholder: 'e.g. {symbol}'
                  .tr(context)
                  .replaceAll('{symbol}', '7200'),
              supportingText: invalidUnitPrice
                  ? 'Enter a positive price.'.tr(context)
                  : 'Rate in {currency} / g'
                        .tr(context)
                        .replaceAll('{currency}', form.currency),
              isError: invalidUnitPrice,
              prefix: CurrencyUtil.symbol(form.currency),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: viewModel.onPricePerUnitChange,
            ),
          ),
        ];
      case ValuationMode.metal:
        final theme = Theme.of(context);
        final invalidRate =
            form.customPrice && !isPositiveDecimal(form.pricePerUnit);
        final invalidTotal =
            form.manualValue.isNotEmpty && !isPositiveDecimal(form.manualValue);
        return <Widget>[
          Text(
            'Valuation method'.tr(context),
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 7),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text('By weight'.tr(context))),
              ButtonSegment(
                value: true,
                label: Text('Total value'.tr(context)),
              ),
            ],
            selected: {form.useTotalValue},
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: theme.colorScheme.primaryContainer,
              selectedForegroundColor: theme.colorScheme.onPrimaryContainer,
              backgroundColor: theme.colorScheme.surfaceContainerLow,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            onSelectionChanged: (selection) {
              FocusScope.of(context).unfocus();
              viewModel.onTotalValueChange(selection.single);
            },
          ),
          const SizedBox(height: 18),
          if (form.useTotalValue)
            LabeledTextField(
              canvas: true,
              controller: _manualValue,
              focusNode: _manualValueFocus,
              label: 'Total value'.tr(context),
              placeholder: '0.00',
              supportingText: invalidTotal
                  ? 'Enter a positive total value'.tr(context)
                  : null,
              isError: invalidTotal,
              prefix: CurrencyUtil.symbol(form.currency),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [],
              textInputAction: requiredFieldInputAction(
                _requiredFields,
                current: _manualValueFocus,
              ),
              onSubmitted: (_) => _focusNextRequired(),
              onChanged: viewModel.onManualValueChange,
            )
          else ...[
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
                label: 'Weight (grams)'.tr(context),
                placeholder: 'e.g. {symbol}'
                    .tr(context)
                    .replaceAll('{symbol}', '10.5'),
                supportingText: invalidQuantity
                    ? 'Enter a positive weight'.tr(context)
                    : 'Total weight in grams'.tr(context),
                isError: invalidQuantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: viewModel.onQuantityChange,
              ),
              second: LabeledTextField(
                canvas: true,
                controller: _pricePerUnit,
                focusNode: _pricePerUnitFocus,
                label: 'Price per gram'.tr(context),
                placeholder: '0.00',
                prefix: CurrencyUtil.symbol(form.currency),
                supportingText: invalidRate
                    ? 'Enter a positive price per gram'.tr(context)
                    : form.customPrice
                    ? 'Your custom rate'.tr(context)
                    : form.isFetchingPrice
                    ? 'Fetching price…'.tr(context)
                    : form.metal?.ticker == null
                    ? 'No automatic quote for this item'.tr(context)
                    : 'Indicative futures price, not a retail quote.'.tr(
                        context,
                      ),
                isError: invalidRate,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [],
                textInputAction: requiredFieldInputAction(
                  _requiredFields,
                  current: _pricePerUnitFocus,
                ),
                onSubmitted: (_) => _focusNextRequired(),
                onChanged: viewModel.onPricePerUnitChange,
              ),
            ),
            if (form.metal?.hasPurity == true && form.purity != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: form.isFetchingPrice
                      ? null
                      : viewModel.fetchMetalPrice,
                  icon: const Icon(Icons.refresh),
                  label: Text('Refresh price'.tr(context)),
                ),
              ),
          ],
        ];
      case ValuationMode.flat:
        return const <Widget>[];
    }
  }

  Widget _metalSelectors(AssetFormState form) {
    final item = PickerChip(
      focusNode: _metalFocus,
      fieldLabel: 'Precious item'.tr(context),
      label:
          form.metal?.label.tr(context) ?? 'Choose a precious item'.tr(context),
      icon: form.metal == null
          ? assetTypeIcon(AssetType.metals)
          : metalIcon(form.metal!),
      onPressed: _pickMetal,
    );
    if (form.metal?.hasPurity != true) return item;
    return FormFieldPair(
      first: item,
      second: PickerChip(
        focusNode: _purityFocus,
        fieldLabel: 'Purity'.tr(context),
        label:
            form.purity ??
            (form.metal == null
                    ? 'Not selected'
                    : form.metal == PreciousMetal.gold
                    ? 'Choose karat'
                    : 'Choose grade')
                .tr(context),
        supportingText:
            (form.metal == null
                    ? 'Choose a metal first.'
                    : form.metal == PreciousMetal.gold
                    ? 'Measured in karats.'
                    : 'Fineness in parts per thousand.')
                .tr(context),
        onPressed: form.metal == null ? null : _pickPurity,
      ),
    );
  }

  Future<void> _pickMetal() async {
    final metal = await showSelectionPickerDialog<PreciousMetal>(
      context,
      eyebrow: 'Valuables'.tr(context),
      title: 'Choose a precious item'.tr(context),
      selected: _viewModel!.form.metal,
      options: PreciousMetal.values,
      optionLabel: (metal) => metal.label.tr(context),
      optionIcon: metalIcon,
      searchPlaceholder: 'e.g. Gold, Diamond, Jewellery'.tr(context),
    );
    if (!mounted || metal == null) return;
    _viewModel!.onMetalChange(metal);
    _quantity.text = _viewModel!.form.quantity;
    _manualValue.text = _viewModel!.form.manualValue;
    // The purity chip is disabled until the new metal is rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.isCurrentOf(context) == true) {
        if (metal.hasPurity) {
          unawaited(_pickPurity());
        } else {
          _focusNextRequired();
        }
      }
    });
  }

  Future<void> _pickPurity() async {
    final form = _viewModel!.form;
    final metal = form.metal;
    if (metal == null || !metal.hasPurity) return;
    final purity = await showSelectionPickerDialog<String>(
      context,
      eyebrow: metal.label.tr(context),
      title: (metal == PreciousMetal.gold ? 'Choose karat' : 'Choose fineness')
          .tr(context),
      selected: form.purity,
      options: metal.grades.keys.toList(growable: false),
      optionLabel: (grade) => grade,
      optionSubtitle: (grade) => metal == PreciousMetal.silver && grade == '925'
          ? 'Sterling silver'.tr(context)
          : '${(metal.grades[grade]! * 100).toStringAsFixed(1)}%',
      searchable: false,
    );
    if (!mounted || purity == null) return;
    final priceUpdate = _viewModel!.onPurityChange(purity);
    _focusNextRequired();
    await priceUpdate;
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
