import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/remote/stock/stock_search_service.dart';
import '../../di/app_container.dart';
import '../../domain/model/asset_type.dart';
import '../../domain/model/holding_type.dart';
import '../../domain/model/stock_exchange.dart';
import '../../l10n/app_localizations.dart';
import '../../util/currency_util.dart';
import '../asset/asset_edit_view_model.dart' show AssetEditEventType;
import '../asset/stock_exchange_field.dart';
import '../asset/stock_search_field.dart';
import '../components/form_components.dart';
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
    super.key,
  });

  final int portfolioId;
  final HoldingType initialType;

  @override
  State<HoldingCreateScreen> createState() => _HoldingCreateScreenState();
}

class _HoldingCreateScreenState extends State<HoldingCreateScreen> {
  HoldingCreateViewModel? _viewModel;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _symbol = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _pricePerUnit = TextEditingController();
  final TextEditingController _flatAmount = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  bool _controllersPrimed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final AppContainer container = AppScope.of(context);
    _viewModel = HoldingCreateViewModel(
      assetRepository: container.assetRepository,
      liabilityRepository: container.liabilityRepository,
      settingsRepository: container.settingsRepository,
      portfolioId: widget.portfolioId,
      initialType: widget.initialType,
    )..addListener(_onChanged);
  }

  void _onChanged() {
    final HoldingCreateViewModel viewModel = _viewModel!;
    final HoldingCreateEvent? event = viewModel.event;
    if (event == null || !mounted) return;
    viewModel.consumeEvent();
    switch (event.type) {
      case AssetEditEventType.saved:
      case AssetEditEventType.deleted:
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        final String? notice = event.message?.tr(context);
        Navigator.of(context).pop(event.savedKind);
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

  void _primeControllers(HoldingCreateFormState form) {
    if (_controllersPrimed) return;
    _controllersPrimed = true;
    _name.text = form.name;
    _symbol.text = form.symbol;
    _quantity.text = form.quantity;
    _pricePerUnit.text = form.pricePerUnit;
    _flatAmount.text = form.flatAmount;
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
    _flatAmount.dispose();
    _notes.dispose();
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
                    PageHeading('New entry'.tr(context)),
                    const SizedBox(height: 10),
                    _DetectedKindBanner(kind: form.detectedKind),
                    const SizedBox(height: 16),
                    _buildValueHero(context, form, viewModel),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        HoldingTypeSelector(
                          selected: form.holdingType,
                          onSelected: viewModel.onTypeChange,
                        ),
                        CurrencySelector(
                          currency: form.currency,
                          compact: true,
                          onTap: () => _pickCurrency(form.currency),
                        ),
                        if (form.usesStockExchange)
                          StockExchangeField(
                            selected:
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
                      placeholder:
                          (form.isAsset
                                  ? 'e.g. Apple shares'
                                  : 'e.g. Home loan')
                              .tr(context),
                      onChanged: viewModel.onNameChange,
                    ),
                    ..._valuationFields(context, form, viewModel),
                    SizedBox(height: form.isLiability ? 16 : 8),
                    OptionalNotesField(
                      key: const ValueKey<String>('holding-notes'),
                      controller: _notes,
                      onChanged: viewModel.onNotesChange,
                    ),
                    const SizedBox(height: 12),
                    FormActionRow(
                      isSaving: form.isSaving,
                      onCancel: form.isSaving
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              viewModel.cancel();
                              Navigator.of(context).pop();
                            },
                      onSave: form.isSaving || form.isFetchingPrice
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              unawaited(viewModel.save());
                            },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildValueHero(
    BuildContext context,
    HoldingCreateFormState form,
    HoldingCreateViewModel viewModel,
  ) {
    if (form.isLiability) {
      return LabeledTextField(
        key: const ValueKey<String>('holding-flat-amount-field'),
        controller: _flatAmount,
        label: 'Outstanding amount'.tr(context),
        prefix: CurrencyUtil.symbol(form.currency),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        prominent: true,
        supportingText: 'The amount you still owe'.tr(context),
        onChanged: viewModel.onFlatAmountChange,
      );
    }
    if (form.assetValuationMode == ValuationMode.flat) {
      return LabeledTextField(
        key: const ValueKey<String>('holding-flat-amount-field'),
        controller: _flatAmount,
        label: 'Value'.tr(context),
        prefix: CurrencyUtil.symbol(form.currency),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        prominent: true,
        onChanged: viewModel.onFlatAmountChange,
      );
    }
    return _EstimatedValueSummary(
      amount: CurrencyUtil.format(form.estimatedValue, form.currency),
      caption: form.isMarketLinked
          ? form.lastPrice == null
                ? null
                : '${form.quantity.isEmpty ? '0' : form.quantity} × '
                      '${CurrencyUtil.format(form.lastPrice!, form.currency)}'
          : '${form.quantity.isEmpty ? '0' : form.quantity} × '
                '${CurrencyUtil.format(double.tryParse(form.pricePerUnit) ?? 0, form.currency)}',
    );
  }

  List<Widget> _valuationFields(
    BuildContext context,
    HoldingCreateFormState form,
    HoldingCreateViewModel viewModel,
  ) {
    if (form.isLiability) return const <Widget>[];
    final ThemeData theme = Theme.of(context);
    final AssetType assetType = form.holdingType.assetType!;
    switch (assetType.valuationMode) {
      case ValuationMode.market:
        final Widget quantityField = LabeledTextField(
          controller: _quantity,
          label: 'Quantity'.tr(context),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: viewModel.onQuantityChange,
        );
        return <Widget>[
          const SizedBox(height: 12),
          StockSearchField(
            controller: _symbol,
            service: AppScope.of(context).stockSearchService,
            type: switch (assetType) {
              AssetType.crypto => StockSearchType.crypto,
              AssetType.mutualFund => StockSearchType.fund,
              _ => StockSearchType.stock,
            },
            quantityField: quantityField,
            onChanged: viewModel.onSymbolChange,
            onSelected: (StockSearchResult result) {
              viewModel.onStockSelected(result);
              _symbol.text = viewModel.form.symbol;
              _name.text = viewModel.form.name;
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
          if (form.lastPrice == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Price is fetched automatically on save when online.'.tr(
                  context,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ];
      case ValuationMode.quantity:
        return <Widget>[
          const SizedBox(height: 12),
          FormFieldPair(
            first: LabeledTextField(
              controller: _quantity,
              label: 'Quantity'.tr(context),
              suffix: assetType.unitLabel,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: viewModel.onQuantityChange,
            ),
            second: LabeledTextField(
              controller: _pricePerUnit,
              label: 'Price per {unit}'
                  .tr(context)
                  .replaceAll('{unit}', assetType.unitLabel ?? 'unit'),
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
