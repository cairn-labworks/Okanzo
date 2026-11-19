import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../di/app_container.dart';
import '../asset/asset_edit_screen.dart';
import '../asset/asset_edit_view_model.dart';
import '../asset/asset_form_state.dart';
import '../liability/liability_edit_screen.dart';
import '../liability/liability_edit_view_model.dart';
import '../liability/liability_form_state.dart';

class HoldingCreateScreen extends StatefulWidget {
  const HoldingCreateScreen({
    required this.portfolioId,
    required this.asset,
    super.key,
  });

  final int portfolioId;
  final bool asset;

  @override
  State<HoldingCreateScreen> createState() => _HoldingCreateScreenState();
}

class _HoldingCreateScreenState extends State<HoldingCreateScreen> {
  AssetEditViewModel? _asset;
  LiabilityEditViewModel? _liability;
  late AssetFormState _initialAsset;
  late LiabilityFormState _initialLiability;
  late bool _showAsset = widget.asset;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asset != null) return;
    final AppContainer container = AppScope.of(context);
    _asset = AssetEditViewModel(
      assetRepository: container.assetRepository,
      settingsRepository: container.settingsRepository,
      portfolioId: widget.portfolioId,
      assetId: 0,
    );
    _liability = LiabilityEditViewModel(
      liabilityRepository: container.liabilityRepository,
      settingsRepository: container.settingsRepository,
      portfolioId: widget.portfolioId,
      liabilityId: 0,
    );
    _initialAsset = _asset!.form;
    _initialLiability = _liability!.form;
  }

  @override
  void dispose() {
    _asset?.dispose();
    _liability?.dispose();
    super.dispose();
  }

  void _selectKind(bool asset) {
    if (_showAsset == asset) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _showAsset = asset);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(<Listenable>[_asset!, _liability!]),
    builder: (context, _) {
      final bool dirty =
          !mapEquals(
            _initialAsset.toEntity(now: 0).toMap(),
            _asset!.form.toEntity(now: 0).toMap(),
          ) ||
          !mapEquals(
            _initialLiability.toEntity(now: 0).toMap(),
            _liability!.form.toEntity(now: 0).toMap(),
          );
      return _showAsset
          ? AssetEditScreen(
              portfolioId: widget.portfolioId,
              assetId: 0,
              viewModel: _asset,
              hasUnsavedChanges: dirty,
              onKindSelected: _selectKind,
            )
          : LiabilityEditScreen(
              portfolioId: widget.portfolioId,
              liabilityId: 0,
              viewModel: _liability,
              hasUnsavedChanges: dirty,
              onKindSelected: _selectKind,
            );
    },
  );
}
