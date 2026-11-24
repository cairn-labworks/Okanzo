import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/remote/stock/stock_search_service.dart';
import '../../di/app_container.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/holding_type.dart';
import '../../domain/model/precious_metal.dart';
import '../../domain/model/stock_exchange.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../asset/asset_edit_view_model.dart' show AssetEditEventType;
import '../asset/asset_form_state.dart'
    show isPositiveDecimal, isValidTickerSymbol;
import '../asset/stock_exchange_field.dart';
import '../asset/stock_search_field.dart';
import '../components/form_components.dart';
import '../components/holding_editor_chrome.dart';
import '../components/holding_editor_guard.dart';
import '../components/holding_saved_summary_screen.dart';
import '../components/type_icons.dart';
import '../components/ui_components.dart';
import '../theme/theme.dart';
import 'holding_create_form_state.dart';
import 'holding_create_view_model.dart';
import 'holding_type_selector.dart';

/// Unified creation screen that automatically classifies an entry as an asset
/// or a liability based on the selected [HoldingType].
class HoldingCreateScreen extends StatefulWidget {
  const HoldingCreateScreen({
    required this.portfolioId,
    this.initialType = const HoldingType.asset(AssetType.stock),
    this.viewModel,
    this.onHoldingSaved,
    super.key,
  });

  final int portfolioId;
  final HoldingType initialType;
  final HoldingCreateViewModel? viewModel;
  final ValueChanged<HoldingKind>? onHoldingSaved;

  @override
  State<HoldingCreateScreen> createState() => _HoldingCreateScreenState();
}

class _HoldingCreateScreenState extends State<HoldingCreateScreen> {
  HoldingCreateViewModel? _viewModel;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _customName = TextEditingController();
  final TextEditingController _symbol = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _pricePerUnit = TextEditingController();
  final TextEditingController _flatAmount = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _symbolFocus = FocusNode();
  final FocusNode _quantityFocus = FocusNode();
  final FocusNode _pricePerUnitFocus = FocusNode();
  final FocusNode _flatAmountFocus = FocusNode();
  final FocusNode _metalFocus = FocusNode();
  final FocusNode _purityFocus = FocusNode();
  bool _controllersPrimed = false;
  HoldingCreateFormState? _initialForm;
  final GlobalKey<HoldingEditorGuardState> _guard =
      GlobalKey<HoldingEditorGuardState>();

  Map<FocusNode, TextEditingController> get _requiredFields {
    final HoldingCreateFormState form = _viewModel!.form;
    if (form.isLiability) {
      return <FocusNode, TextEditingController>{
        _flatAmountFocus: _flatAmount,
        _nameFocus: _name,
      };
    }
    return switch (form.assetValuationMode!) {
      ValuationMode.market => <FocusNode, TextEditingController>{
        _symbolFocus: _symbol,
        _quantityFocus: _quantity,
      },
      ValuationMode.metal when form.useTotalValue =>
        <FocusNode, TextEditingController>{
          _nameFocus: _name,
          _flatAmountFocus: _flatAmount,
        },
      ValuationMode.metal ||
      ValuationMode.quantity => <FocusNode, TextEditingController>{
        _nameFocus: _name,
        _quantityFocus: _quantity,
        _pricePerUnitFocus: _pricePerUnit,
      },
      ValuationMode.flat => <FocusNode, TextEditingController>{
        _flatAmountFocus: _flatAmount,
        _nameFocus: _name,
      },
    };
  }

  void _focusNextRequired() {
    final HoldingCreateFormState form = _viewModel!.form;
    if (form.holdingType.assetType == AssetType.metals) {
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
    HoldingCreateFormState form,
    HoldingCreateViewModel viewModel,
  ) =>
      form.symbol.trim().isNotEmpty ||
          viewModel.preferredExchanges.contains(form.exchange)
      ? form.exchange
      : null;

  String _footerCalculation(BuildContext context, HoldingCreateFormState form) {
    final String qty = form.quantity.trim().isEmpty
        ? '0'
        : form.quantity.trim();
    switch (form.assetValuationMode!) {
      case ValuationMode.market:
        if (form.lastPrice == null) {
          return '$qty × ${CurrencyUtil.format(0, form.currency)} · '
              '${'price not fetched yet'.tr(context)}';
        }
        return '$qty × ${CurrencyUtil.format(form.lastPrice!, form.currency)}';
      case ValuationMode.quantity:
        final double unitPrice = double.tryParse(form.pricePerUnit) ?? 0;
        final String? unitLabel = form.holdingType.assetType?.unitLabel;
        final String unit = unitLabel == null ? '' : ' $unitLabel';
        return '$qty$unit × ${CurrencyUtil.format(unitPrice, form.currency)}';
      case ValuationMode.metal:
        if (form.useTotalValue) return 'Total value'.tr(context);
        final double? rate = form.metalRate;
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
        HoldingCreateViewModel(
          assetRepository: container.assetRepository,
          liabilityRepository: container.liabilityRepository,
          settingsRepository: container.settingsRepository,
          portfolioId: widget.portfolioId,
          initialType: widget.initialType,
        );
    _viewModel!.addListener(_onChanged);
  }

  void _onChanged() {
    final HoldingCreateViewModel viewModel = _viewModel!;
    if (mounted &&
        viewModel.form.holdingType.assetType == AssetType.metals &&
        _pricePerUnit.text != viewModel.form.pricePerUnit) {
      _pricePerUnit.text = viewModel.form.pricePerUnit;
    }
    final HoldingCreateEvent? event = viewModel.event;
    if (event == null || !mounted) return;
    viewModel.consumeEvent();
    switch (event.type) {
      case AssetEditEventType.saved:
        final HoldingKind kind = event.savedKind ?? viewModel.form.detectedKind;
        widget.onHoldingSaved?.call(kind);
        unawaited(
          _guard.currentState!.close(
            confirmationAfterClose: holdingSavedSummaryRoute(
              context,
              builder: (_) => HoldingSavedSummaryScreen(
                portfolioId: widget.portfolioId,
                updated: false,
                savedAsset: event.savedAsset,
                savedLiability: event.savedLiability,
                notice: event.message,
                onHoldingSaved: widget.onHoldingSaved,
              ),
            ),
          ),
        );
      case AssetEditEventType.deleted:
        unawaited(_guard.currentState!.close());
      case AssetEditEventType.error:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text((event.message ?? '').tr(context))),
          );
    }
  }

  void _primeControllers(HoldingCreateFormState form) {
    if (_controllersPrimed) return;
    _controllersPrimed = true;
    _initialForm = form;
    _name.text = form.name;
    _customName.text = form.customName;
    _symbol.text = form.symbol;
    _quantity.text = form.quantity;
    _pricePerUnit.text = form.pricePerUnit;
    _flatAmount.text = form.flatAmount;
  }

  Future<void> _handleCancel() async {
    final HoldingCreateViewModel viewModel = _viewModel!;
    if (viewModel.form.isPersisting) return;
    FocusScope.of(context).unfocus();
    viewModel.cancel();
    await _guard.currentState!.close();
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
    _flatAmount.dispose();
    _nameFocus.dispose();
    _symbolFocus.dispose();
    _quantityFocus.dispose();
    _pricePerUnitFocus.dispose();
    _flatAmountFocus.dispose();
    _metalFocus.dispose();
    _purityFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HoldingCreateViewModel viewModel = _viewModel!;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (BuildContext context, _) {
        final HoldingCreateFormState form = viewModel.form;
        if (!form.loading) _primeControllers(form);
        final bool dirty =
            _initialForm != null && form.hasUnsavedChangesFrom(_initialForm!);
        final bool priced =
            form.isLiability ||
            (form.holdingType.assetType == AssetType.metals
                ? form.useTotalValue ||
                      form.metal == null ||
                      form.metalRate != null
                : !form.isMarketLinked || form.lastPrice != null);
        return HoldingEditorGuard(
          key: _guard,
          dirty: dirty || form.isSaving || form.isFetchingPrice,
          canDiscard: !form.isPersisting,
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
              ],
            ),
            bottomNavigationBar: form.loading
                ? null
                : HoldingEditorFooter(
                    portfolioId: widget.portfolioId,
                    asset: form.isAsset,
                    amount: form.estimatedValue,
                    currency: form.currency,
                    priced: priced,
                    calculation: form.isAsset
                        ? _footerCalculation(context, form)
                        : null,
                    saving: form.isSaving,
                    ready: !form.isFetchingPrice && form.validate() == null,
                    cancelEnabled: !form.isPersisting,
                    onCancel: () => unawaited(_handleCancel()),
                    onSave: () {
                      FocusScope.of(context).unfocus();
                      unawaited(viewModel.save());
                    },
                  ),
            body: form.loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    key: const ValueKey<String>('holding-create-scroll'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        HoldingPortfolioLabel(
                          portfolioId: widget.portfolioId,
                          template: 'To {portfolio}'.tr(context),
                          uppercase: true,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                letterSpacing: 1.35,
                              ),
                        ),
                        const SizedBox(height: 9),
                        PageHeading('New entry'.tr(context)),
                        const SizedBox(height: 10),
                        _DetectedKindBanner(kind: form.detectedKind),
                        const SizedBox(height: 18),
                        if (form.isLiability ||
                            form.assetValuationMode ==
                                ValuationMode.flat) ...<Widget>[
                          _buildProminentAmountField(context, form, viewModel),
                          const SizedBox(height: 12),
                        ],
                        FormFieldPair(
                          first: HoldingTypeSelector(
                            canvas: true,
                            enabled: !form.isPersisting,
                            selected: form.holdingType,
                            supportingText:
                                (form.isAsset
                                        ? 'e.g. Stock, Cash, Valuables, Real estate'
                                        : 'e.g. Loan, Mortgage, Credit card')
                                    .tr(context),
                            onSelected: (HoldingType type) {
                              FocusScope.of(context).unfocus();
                              viewModel.onTypeChange(type);
                              _name.text = viewModel.form.name;
                              _customName.text = viewModel.form.customName;
                              _symbol.text = viewModel.form.symbol;
                              _quantity.text = viewModel.form.quantity;
                              _pricePerUnit.text = viewModel.form.pricePerUnit;
                              _flatAmount.text = viewModel.form.flatAmount;
                              if (type.assetType == AssetType.metals) {
                                unawaited(_pickMetal());
                              } else {
                                _focusNextRequired();
                              }
                            },
                          ),
                          second: CurrencySelector(
                            canvas: true,
                            currency: form.currency,
                            supportingText: 'e.g. INR, USD, EUR, GBP'.tr(
                              context,
                            ),
                            compact: true,
                            onTap: form.isPersisting
                                ? () {}
                                : () => _pickCurrency(form.currency),
                          ),
                        ),
                        if (form.usesStockExchange) ...<Widget>[
                          const SizedBox(height: 18),
                          StockExchangeField(
                            canvas: true,
                            selected: _activeExchange(form, viewModel),
                            isMutualFund:
                                form.holdingType.assetType ==
                                AssetType.mutualFund,
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
                        if (form.holdingType.assetType ==
                            AssetType.metals) ...<Widget>[
                          const SizedBox(height: 14),
                          _metalSelectors(form),
                        ],
                        if (!form.isMarketLinked) ...<Widget>[
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
                                (form.metal?.nameExample ??
                                        form.holdingType.nameExample)
                                    .tr(context),
                            maxLength: 60,
                            onChanged: viewModel.onNameChange,
                          ),
                        ],
                        if (form.isAsset &&
                            form.assetValuationMode !=
                                ValuationMode.flat) ...<Widget>[
                          const SizedBox(height: 14),
                          ..._valuationFields(context, form, viewModel),
                        ],
                        const SizedBox(height: 56),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildProminentAmountField(
    BuildContext context,
    HoldingCreateFormState form,
    HoldingCreateViewModel viewModel,
  ) {
    if (form.isLiability) {
      return LabeledTextField(
        key: const ValueKey<String>('holding-flat-amount-field'),
        canvas: true,
        controller: _flatAmount,
        focusNode: _flatAmountFocus,
        textInputAction: requiredFieldInputAction(
          _requiredFields,
          current: _flatAmountFocus,
        ),
        onSubmitted: (_) => _focusNextRequired(),
        autofocus: true,
        label: 'Outstanding amount'.tr(context),
        placeholder: '0.00',
        prefix: CurrencyUtil.symbol(form.currency),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        prominent: true,
        supportingText: 'The amount you still owe'.tr(context),
        onChanged: viewModel.onFlatAmountChange,
      );
    }
    return LabeledTextField(
      key: const ValueKey<String>('holding-flat-amount-field'),
      canvas: true,
      controller: _flatAmount,
      focusNode: _flatAmountFocus,
      textInputAction: requiredFieldInputAction(
        _requiredFields,
        current: _flatAmountFocus,
      ),
      onSubmitted: (_) => _focusNextRequired(),
      autofocus: true,
      label: 'Value'.tr(context),
      placeholder: '0.00',
      supportingText: 'Your estimate of its value today. Zero is allowed.'.tr(
        context,
      ),
      prefix: CurrencyUtil.symbol(form.currency),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      prominent: true,
      onChanged: viewModel.onFlatAmountChange,
    );
  }

  List<Widget> _valuationFields(
    BuildContext context,
    HoldingCreateFormState form,
    HoldingCreateViewModel viewModel,
  ) {
    final AssetType assetType = form.holdingType.assetType!;
    final bool invalidQuantity =
        form.quantity.trim().isNotEmpty &&
        (double.tryParse(form.quantity.trim()) ?? 0) <= 0;
    switch (assetType.valuationMode) {
      case ValuationMode.market:
        final String quantityPlaceholder = switch (assetType) {
          AssetType.crypto =>
            'e.g. {symbol}'.tr(context).replaceAll('{symbol}', '0.25'),
          AssetType.mutualFund =>
            'e.g. {symbol}'.tr(context).replaceAll('{symbol}', '15'),
          _ => 'e.g. {symbol}'.tr(context).replaceAll('{symbol}', '10'),
        };
        final String quantityHint = switch (assetType) {
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
              isCrypto: assetType == AssetType.crypto,
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
                ? (assetType == AssetType.crypto
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
            type: switch (assetType) {
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
            onSelected: (StockSearchResult result) {
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
            key: ValueKey<HoldingType>(form.holdingType),
            controller: _customName,
            textInputAction: requiredFieldInputAction(_requiredFields),
            onSubmitted: (_) => _focusNextRequired(),
            label: 'Custom name (optional)'.tr(context),
            maxLength: 60,
            placeholder: form.name.trim().isNotEmpty
                ? form.name.trim()
                : assetType.nameExample.tr(context),
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
              suffix: assetType.unitLabel,
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
                  .replaceAll('{unit}', assetType.unitLabel ?? 'unit'),
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
        final ThemeData theme = Theme.of(context);
        final bool invalidRate =
            form.customPrice && !isPositiveDecimal(form.pricePerUnit);
        final bool invalidTotal =
            form.flatAmount.isNotEmpty && !isPositiveDecimal(form.flatAmount);
        return <Widget>[
          Text(
            'Valuation method'.tr(context),
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 7),
          SegmentedButton<bool>(
            segments: <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                value: false,
                label: Text('By weight'.tr(context)),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('Total value'.tr(context)),
              ),
            ],
            selected: <bool>{form.useTotalValue},
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
            onSelectionChanged: form.isPersisting
                ? null
                : (Set<bool> selection) {
                    FocusScope.of(context).unfocus();
                    viewModel.onTotalValueChange(selection.single);
                  },
          ),
          const SizedBox(height: 18),
          if (form.useTotalValue)
            LabeledTextField(
              canvas: true,
              controller: _flatAmount,
              focusNode: _flatAmountFocus,
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
                current: _flatAmountFocus,
              ),
              onSubmitted: (_) => _focusNextRequired(),
              onChanged: viewModel.onFlatAmountChange,
            )
          else ...<Widget>[
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
                  onPressed: form.isFetchingPrice || form.isSaving
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

  Widget _metalSelectors(HoldingCreateFormState form) {
    final Widget item = PickerChip(
      focusNode: _metalFocus,
      fieldLabel: 'Precious item'.tr(context),
      label:
          form.metal?.label.tr(context) ?? 'Choose a precious item'.tr(context),
      icon: form.metal == null
          ? assetTypeIcon(AssetType.metals)
          : metalIcon(form.metal!),
      onPressed: form.isPersisting ? null : _pickMetal,
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
        onPressed: form.metal == null || form.isPersisting ? null : _pickPurity,
      ),
    );
  }

  Future<void> _pickMetal() async {
    final PreciousMetal? metal = await showSelectionPickerDialog<PreciousMetal>(
      context,
      eyebrow: 'Valuables'.tr(context),
      title: 'Choose a precious item'.tr(context),
      selected: _viewModel!.form.metal,
      options: PreciousMetal.values,
      optionLabel: (PreciousMetal item) => item.label.tr(context),
      optionIcon: metalIcon,
      searchPlaceholder: 'e.g. Gold, Diamond, Jewellery'.tr(context),
    );
    if (!mounted || metal == null) return;
    _viewModel!.onMetalChange(metal);
    _quantity.text = _viewModel!.form.quantity;
    _pricePerUnit.text = _viewModel!.form.pricePerUnit;
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
    final HoldingCreateFormState form = _viewModel!.form;
    final PreciousMetal? metal = form.metal;
    if (metal == null || !metal.hasPurity) return;
    final String? purity = await showSelectionPickerDialog<String>(
      context,
      eyebrow: metal.label.tr(context),
      title: (metal == PreciousMetal.gold ? 'Choose karat' : 'Choose fineness')
          .tr(context),
      selected: form.purity,
      options: metal.grades.keys.toList(growable: false),
      optionLabel: (String grade) => grade,
      optionSubtitle: (String grade) =>
          metal == PreciousMetal.silver && grade == '925'
          ? 'Sterling silver'.tr(context)
          : '${(metal.grades[grade]! * 100).toStringAsFixed(1)}%',
      searchable: false,
    );
    if (!mounted || purity == null) return;
    final Future<void> priceUpdate = _viewModel!.onPurityChange(purity);
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

class _DetectedKindBanner extends StatelessWidget {
  const _DetectedKindBanner({required this.kind});

  final HoldingKind kind;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FinanceColors finance = FinanceColors.of(context);
    final bool isAsset = kind == HoldingKind.asset;
    final Color accent = isAsset ? finance.positive : finance.negative;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Wrap(
        key: const ValueKey<String>('detected-holding-kind'),
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    isAsset ? Icons.trending_up : Icons.trending_down,
                    size: 14,
                    color: accent,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      (isAsset ? 'Asset' : 'Liability').tr(context),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            (isAsset ? 'Added to net worth' : 'Subtracted from net worth').tr(
              context,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
