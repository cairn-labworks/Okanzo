import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/remote/stock/stock_search_service.dart';
import '../../domain/model/stock_exchange.dart';
import '../../l10n/app_localizations.dart';
import '../../util/result.dart';
import '../components/form_components.dart';
import 'asset_form_state.dart' show isValidTickerSymbol, sanitizeMarketQuery;

final List<TextInputFormatter> _marketQueryFormatters = <TextInputFormatter>[
  TextInputFormatter.withFunction((
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String filtered = sanitizeMarketQuery(newValue.text);
    if (filtered == newValue.text) return newValue;
    final int cursor = newValue.selection.extentOffset.clamp(
      0,
      newValue.text.length,
    );
    final int filteredCursor = sanitizeMarketQuery(
      newValue.text.substring(0, cursor),
    ).length;
    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: filteredCursor),
    );
  }),
];

sealed class _MarketSearchPick {
  const _MarketSearchPick();
}

final class _MarketListingPick extends _MarketSearchPick {
  const _MarketListingPick(this.result);
  final StockSearchResult result;
}

final class _ManualTickerPick extends _MarketSearchPick {
  const _ManualTickerPick(this.ticker);
  final String ticker;
}

class StockSearchField extends StatefulWidget {
  const StockSearchField({
    required this.controller,
    required this.service,
    required this.type,
    required this.quantityField,
    required this.onChanged,
    required this.onSelected,
    this.selectedName,
    this.selectedSymbol,
    this.currency,
    this.exchange,
    this.errorText,
    this.onManualSelected,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.canvas = false,
    super.key,
  });

  final TextEditingController controller;
  final StockSearchService service;
  final StockSearchType type;
  final Widget quantityField;
  final ValueChanged<String> onChanged;
  final ValueChanged<StockSearchResult> onSelected;
  final String? selectedName;
  final String? selectedSymbol;
  final String? currency;
  final StockExchange? exchange;
  final String? errorText;
  final ValueChanged<String>? onManualSelected;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool canvas;

  @override
  State<StockSearchField> createState() => _StockSearchFieldState();
}

class _StockSearchFieldState extends State<StockSearchField> {
  final FocusNode _internalFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _internalFocus;
  final GlobalKey _feedbackKey = GlobalKey();
  Timer? _debounce;
  Timer? _blurReset;
  int _request = 0;
  late String _text;
  bool _searching = false;
  Result<List<StockSearchResult>>? _result;

  @override
  void initState() {
    super.initState();
    _text = widget.controller.text;
    widget.controller.addListener(_onControllerChanged);
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(StockSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalFocus).removeListener(_onFocusChange);
      _focus.addListener(_onFocusChange);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _text = widget.controller.text;
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.type != widget.type) {
      _reset();
    }
  }

  void _onFocusChange() {
    if (widget.canvas) {
      setState(() {});
      return;
    }
    _blurReset?.cancel();
    if (_focus.hasFocus && _text.trim().length >= 2 && _result == null) {
      _debounce?.cancel();
      final int request = _request;
      setState(() => _searching = true);
      _debounce = Timer(const Duration(milliseconds: 350), () {
        unawaited(_search(_text, request));
      });
    } else if (!_focus.hasFocus) {
      _blurReset = Timer(const Duration(milliseconds: 150), () {
        if (mounted && !_focus.hasFocus) _reset();
      });
    }
  }

  void _onControllerChanged() {
    if (_text == widget.controller.text) return;
    _text = widget.controller.text;
    _reset();
  }

  void _reset() {
    _debounce?.cancel();
    _blurReset?.cancel();
    _request++;
    setState(() {
      _searching = false;
      _result = null;
    });
  }

  void _onChanged(String value) {
    widget.onChanged(value);
    if (value.trim().length < 2) return;
    setState(() => _searching = true);
    final int request = _request;
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_search(value, request));
    });
  }

  Future<void> _search(String query, int request) async {
    final Result<List<StockSearchResult>> result = await widget.service.search(
      query,
      type: widget.type,
    );
    if (!mounted || request != _request || !_focus.hasFocus) return;
    setState(() {
      _searching = false;
      _result = result;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? feedback = _feedbackKey.currentContext;
      if (!mounted || request != _request || feedback == null) return;
      unawaited(
        Scrollable.ensureVisible(
          feedback,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 200),
        ),
      );
    });
  }

  void _select(StockSearchResult result) {
    _reset();
    _focus.unfocus();
    widget.onSelected(result);
  }

  Future<void> _openMarketSearchDialog() async {
    FocusScope.of(context).unfocus();
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final String currentSymbol =
        (widget.selectedSymbol ?? widget.controller.text).trim().toUpperCase();
    final _MarketSearchPick? pick = await showDialog<_MarketSearchPick>(
      context: context,
      barrierColor: dark ? const Color(0xAA10231B) : const Color(0x7310231B),
      builder: (BuildContext context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: _MarketSearchDialog(
          service: widget.service,
          type: widget.type,
          exchange: widget.exchange,
          initialQuery: widget.controller.text.trim(),
          selectedSymbol: currentSymbol,
        ),
      ),
    );
    if (!mounted) return;
    if (pick == null) {
      if (ModalRoute.isCurrentOf(context) == true) _focus.requestFocus();
      return;
    }
    switch (pick) {
      case _MarketListingPick(:final StockSearchResult result):
        widget.onSelected(result);
      case _ManualTickerPick(:final String ticker):
        widget.controller.text = ticker;
        if (widget.onManualSelected != null) {
          widget.onManualSelected!(ticker);
        } else {
          widget.onChanged(ticker);
        }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _blurReset?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _focus.removeListener(_onFocusChange);
    _internalFocus.dispose();
    super.dispose();
  }

  Widget _buildCanvasPicker(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String label =
        (widget.type == StockSearchType.crypto
                ? 'Coin or ticker'
                : 'Company or Ticker')
            .tr(context);
    final String name = (widget.selectedName ?? '').trim();
    final String rawSymbol = widget.controller.text.trim();
    final String code = (widget.selectedSymbol ?? rawSymbol)
        .trim()
        .toUpperCase();
    final bool hasSymbol = code.isNotEmpty;
    final String currency = (widget.currency ?? '').trim();
    final StockExchange effectiveExchange = widget.exchange ?? StockExchange.us;
    final (String exName, String exTicker) = effectiveExchange.exampleHolding(
      fund: widget.type == StockSearchType.fund,
    );
    final String qualifiedExample = effectiveExchange.qualify(exTicker);
    final String placeholder = switch (widget.type) {
      StockSearchType.crypto => 'e.g. Bitcoin, Ethereum, or BTC-USD'.tr(
        context,
      ),
      StockSearchType.fund || StockSearchType.stock =>
        'Search {name}, or enter {ticker}'
            .tr(context)
            .replaceAll('{name}', exName)
            .replaceAll('{ticker}', qualifiedExample),
    };
    final String helperText = switch (widget.type) {
      StockSearchType.crypto =>
        'e.g. BTC defaults to BTC-USD, or pick BTC-EUR.'.tr(context),
      StockSearchType.fund || StockSearchType.stock =>
        widget.exchange != null && widget.exchange!.suffix.isNotEmpty
            ? 'e.g. {ticker} ({exchange}) or {qualified}'
                  .tr(context)
                  .replaceAll('{ticker}', exTicker)
                  .replaceAll(
                    '{exchange}',
                    widget.exchange!.displayName.tr(context),
                  )
                  .replaceAll('{qualified}', qualifiedExample)
            : 'e.g. {ticker}, AIR.PA, or RELIANCE.BO'
                  .tr(context)
                  .replaceAll('{ticker}', qualifiedExample),
    };
    final String? errorText = widget.errorText;
    final bool hasError = errorText != null && errorText.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 7),
        Semantics(
          button: true,
          label: label,
          child: Material(
            key: hasSymbol
                ? const ValueKey<String>('selected-market-holding')
                : const ValueKey<String>('market-search-trigger'),
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: hasError
                    ? colors.error
                    : _focus.hasFocus
                    ? colors.primary
                    : canvasBoxBorderColor(colors),
                width: _focus.hasFocus ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              focusNode: _focus,
              borderRadius: BorderRadius.circular(10),
              onTap: _openMarketSearchDialog,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 54),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: hasSymbol ? 10 : 14,
                  ),
                  child: hasSymbol
                      ? Row(
                          children: <Widget>[
                            _TickerBadge(code),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    name.isNotEmpty ? name : code,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: colors.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    name.isNotEmpty
                                        ? (currency.isEmpty
                                              ? code
                                              : '$code / $currency')
                                        : <String>[
                                            'Manual ticker'.tr(context),
                                            if (currency.isNotEmpty) currency,
                                          ].join(' · '),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.search, size: 18, color: colors.primary),
                          ],
                        )
                      : Row(
                          children: <Widget>[
                            Icon(Icons.search, size: 19, color: colors.primary),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                placeholder,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.expand_more, size: 16),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          hasError ? errorText : helperText,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            height: 1.4,
            color: hasError ? colors.error : colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        widget.quantityField,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.canvas) return _buildCanvasPicker(context);
    final ThemeData theme = Theme.of(context);
    final Result<List<StockSearchResult>>? result = _result;
    return TextFieldTapRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FormFieldPair(
            first: LabeledTextField(
              controller: widget.controller,
              focusNode: _focus,
              inputFormatters: _marketQueryFormatters,
              label:
                  (widget.type == StockSearchType.crypto
                          ? 'Coin or ticker'
                          : 'Company or Ticker')
                      .tr(context),
              placeholder: 'Search'.tr(context),
              onChanged: _onChanged,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
            ),
            second: widget.quantityField,
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: result.isOffline
                  ? Row(
                      key: _feedbackKey,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            top: 2,
                            end: 6,
                          ),
                          child: Icon(
                            Icons.cloud_off_outlined,
                            size: 15,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            'No internet connection. Enter a ticker manually to save offline.'
                                .tr(context),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    )
                  : result.isFailure || result.value.isEmpty
                  ? Text(
                      key: _feedbackKey,
                      (result.isFailure
                              ? 'Search unavailable. Enter a ticker manually or try again.'
                              : 'No matches. Try another name or enter a ticker.')
                          .tr(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: result.isFailure
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Material(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: <Widget>[
                          for (final StockSearchResult match in result.value)
                            ListTile(
                              key: match == result.value.first
                                  ? _feedbackKey
                                  : null,
                              title: Text(
                                match.name,
                                style: theme.textTheme.bodyMedium,
                              ),
                              subtitle: Text(
                                <String>[
                                  match.symbol,
                                  if (widget.type != StockSearchType.crypto &&
                                      match.exchange.isNotEmpty)
                                    match.exchange,
                                ].join(' · '),
                                style: theme.textTheme.bodySmall,
                              ),
                              onTap: () => _select(match),
                            ),
                        ],
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _TickerBadge extends StatelessWidget {
  const _TickerBadge(this.symbol);

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String upper = symbol.trim().toUpperCase();
    final String letters = upper.length <= 2 ? upper : upper.substring(0, 2);
    return Container(
      width: 33,
      height: 33,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        letters,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.primary,
          height: 1,
        ),
      ),
    );
  }
}

class _MarketSearchDialog extends StatefulWidget {
  const _MarketSearchDialog({
    required this.service,
    required this.type,
    required this.initialQuery,
    required this.selectedSymbol,
    this.exchange,
  });

  final StockSearchService service;
  final StockSearchType type;
  final StockExchange? exchange;
  final String initialQuery;
  final String selectedSymbol;

  @override
  State<_MarketSearchDialog> createState() => _MarketSearchDialogState();
}

class _MarketSearchDialogState extends State<_MarketSearchDialog> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  int _request = 0;
  bool _searching = false;
  Result<List<StockSearchResult>>? _result;

  @override
  void initState() {
    super.initState();
    final String initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _query.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _query.text.length,
      );
      if (initial.length >= 2) {
        _searching = true;
        final int request = _request;
        _debounce = Timer(const Duration(milliseconds: 350), () {
          unawaited(_search(initial, request));
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _request++;
    if (value.trim().length < 2) {
      setState(() {
        _searching = false;
        _result = null;
      });
      return;
    }
    setState(() => _searching = true);
    final int request = _request;
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_search(value, request));
    });
  }

  Future<void> _search(String query, int request) async {
    final Result<List<StockSearchResult>> result = await widget.service.search(
      query,
      type: widget.type,
    );
    if (!mounted || request != _request) return;
    setState(() {
      _searching = false;
      _result = result;
    });
  }

  void _submitFirstOrManual(String raw) {
    final String cleaned = raw.trim().toUpperCase();
    if (cleaned.isEmpty) return;
    final List<StockSearchResult> matches =
        _result != null && _result!.isSuccess
        ? _result!.value
        : const <StockSearchResult>[];
    final StockSearchResult? exact = matches
        .where(
          (StockSearchResult item) =>
              item.symbol.trim().toUpperCase() == cleaned,
        )
        .firstOrNull;
    if (exact != null) {
      Navigator.of(context).pop(_MarketListingPick(exact));
      return;
    }
    if (isValidTickerSymbol(
      cleaned,
      isCrypto: widget.type == StockSearchType.crypto,
    )) {
      Navigator.of(context).pop(_ManualTickerPick(cleaned));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color boxBorder = canvasBoxBorderColor(colors);
    final String searchLabel = 'Search'.tr(context);
    final bool isCrypto = widget.type == StockSearchType.crypto;
    final String typeLabel = switch (widget.type) {
      StockSearchType.crypto => 'Cryptocurrency'.tr(context),
      StockSearchType.fund => 'Mutual fund / ETF'.tr(context),
      StockSearchType.stock => 'Stock'.tr(context),
    };
    final String eyebrow = '$typeLabel · ${'Market search'.tr(context)}';
    final String title = switch (widget.type) {
      StockSearchType.crypto => 'Choose coin or ticker'.tr(context),
      StockSearchType.fund => 'Choose fund or ticker'.tr(context),
      StockSearchType.stock => 'Choose company or ticker'.tr(context),
    };
    final StockExchange effectiveExchange = widget.exchange ?? StockExchange.us;
    final (String exName, String exTicker) = effectiveExchange.exampleHolding(
      fund: widget.type == StockSearchType.fund,
    );
    final String qualifiedExample = effectiveExchange.qualify(exTicker);
    final String placeholder = switch (widget.type) {
      StockSearchType.crypto => 'e.g. Bitcoin, BTC-USD, ETH-EUR'.tr(context),
      StockSearchType.fund || StockSearchType.stock =>
        'e.g. {name} or {ticker}'
            .tr(context)
            .replaceAll('{name}', exName)
            .replaceAll('{ticker}', qualifiedExample),
    };
    final OutlineInputBorder searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: boxBorder),
    );
    final String trimmed = _query.text.trim();
    final String upper = trimmed.toUpperCase();
    final Result<List<StockSearchResult>>? result = _result;
    final List<StockSearchResult> matches = result != null && result.isSuccess
        ? result.value
        : const <StockSearchResult>[];
    final bool validManual = isValidTickerSymbol(upper, isCrypto: isCrypto);
    final bool showManualRow =
        upper.isNotEmpty &&
        validManual &&
        !matches.any(
          (StockSearchResult item) => item.symbol.trim().toUpperCase() == upper,
        );

    final List<Widget> rows = <Widget>[
      for (int index = 0; index < matches.length; index++)
        Builder(
          builder: (BuildContext context) {
            final StockSearchResult match = matches[index];
            final bool isSelected =
                widget.selectedSymbol.isNotEmpty &&
                match.symbol.trim().toUpperCase() == widget.selectedSymbol;
            final bool nextIsSelected =
                index + 1 < matches.length &&
                widget.selectedSymbol.isNotEmpty &&
                matches[index + 1].symbol.trim().toUpperCase() ==
                    widget.selectedSymbol;
            final bool hasMoreBelow =
                index < matches.length - 1 || showManualRow;
            final bool showDivider =
                !isSelected && !nextIsSelected && hasMoreBelow;
            final String subtitle = <String>[
              match.symbol,
              if (widget.type != StockSearchType.crypto &&
                  match.exchange.isNotEmpty)
                match.exchange,
            ].join(' · ');
            final Widget tile = ListTile(
              minTileHeight: 62,
              minLeadingWidth: 33,
              horizontalTitleGap: 12,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 3,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              selected: isSelected,
              selectedTileColor: colors.primaryContainer,
              leading: _TickerBadge(match.symbol),
              title: Text(
                match.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurface,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              trailing: isSelected
                  ? Icon(Icons.check_rounded, size: 18, color: colors.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(_MarketListingPick(match)),
            );
            if (!showDivider) return tile;
            return DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: tile,
            );
          },
        ),
      if (showManualRow)
        ListTile(
          key: const ValueKey<String>('use-manual-ticker'),
          minTileHeight: 62,
          minLeadingWidth: 22,
          horizontalTitleGap: 12,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: Icon(Icons.search, size: 20, color: colors.primary),
          title: Text(
            'Use "{ticker}"'.tr(context).replaceAll('{ticker}', upper),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: colors.onSurface,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              result != null && result.isOffline
                  ? '${'Enter ticker manually'.tr(context)} · ${'Save offline'.tr(context)}'
                  : 'Enter ticker manually'.tr(context),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
          onTap: () => Navigator.of(context).pop(_ManualTickerPick(upper)),
        ),
    ];

    Widget? statusNotice;
    if (trimmed.isEmpty) {
      statusNotice = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Text(
          'Type a name or ticker symbol above.'.tr(context),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    } else if (result != null && result.isOffline) {
      statusNotice = Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2, end: 6),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
            ),
            Flexible(
              child: Text(
                'No internet connection. Enter a ticker manually to save offline.'
                    .tr(context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (result != null && result.isFailure) {
      statusNotice = Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(
          'Search unavailable. Enter a ticker manually or try again.'.tr(
            context,
          ),
          style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
        ),
      );
    } else if (trimmed.isNotEmpty &&
        !validManual &&
        matches.isEmpty &&
        !_searching) {
      statusNotice = Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(
          (isCrypto
                  ? 'Search by name or enter a valid ticker (e.g. BTC or BTC-USD).'
                  : 'Search by name or enter a valid ticker (e.g. AAPL, AIR.PA, or 7203.T).')
              .tr(context),
          key: const ValueKey<String>('invalid-ticker-notice'),
          style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
        ),
      );
    } else if (result != null && matches.isEmpty && !_searching) {
      statusNotice = Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(
          'No matches. Try another name or enter a ticker.'.tr(context),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: boxBorder),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
      actionsAlignment: MainAxisAlignment.center,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            eyebrow.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.35,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.6,
              height: 1.25,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 375,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              searchLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 7),
            Semantics(
              label: searchLabel,
              child: TextField(
                controller: _query,
                autofocus: true,
                inputFormatters: _marketQueryFormatters,
                onChanged: _onQueryChanged,
                onSubmitted: _submitFirstOrManual,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurface,
                ),
                decoration: InputDecoration(
                  labelText: null,
                  hintText: placeholder,
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: theme.brightness == Brightness.dark
                      ? colors.surfaceContainerLow
                      : colors.surfaceContainerLowest,
                  border: searchBorder,
                  enabledBorder: searchBorder,
                  focusedBorder: searchBorder.copyWith(
                    borderSide: BorderSide(color: colors.primary, width: 1.5),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 13,
                  ),
                ),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 10),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 318),
                child: ClipRect(
                  child: Material(
                    type: MaterialType.transparency,
                    clipBehavior: Clip.hardEdge,
                    child: Scrollbar(
                      controller: _scroll,
                      child: ListView(
                        controller: _scroll,
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: <Widget>[...rows, ?statusNotice],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
              minimumSize: const Size.fromHeight(48),
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text('Close'.tr(context)),
          ),
        ),
      ],
    );
  }
}
