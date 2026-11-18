import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/remote/stock/stock_search_service.dart';
import '../../l10n/app_localizations.dart';
import '../../util/result.dart';
import '../components/form_components.dart';

class StockSearchField extends StatefulWidget {
  const StockSearchField({
    required this.controller,
    required this.service,
    required this.type,
    required this.quantityField,
    required this.onChanged,
    required this.onSelected,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final StockSearchService service;
  final StockSearchType type;
  final Widget quantityField;
  final ValueChanged<String> onChanged;
  final ValueChanged<StockSearchResult> onSelected;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

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
    _blurReset?.cancel();
    if (!_focus.hasFocus) {
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

  @override
  void dispose() {
    _debounce?.cancel();
    _blurReset?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _focus.removeListener(_onFocusChange);
    _internalFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
