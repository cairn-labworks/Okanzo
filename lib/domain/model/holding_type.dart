import 'asset_type.dart';
import 'liability_type.dart';

/// Whether an entry adds to net worth ([asset]) or subtracts from it
/// ([liability]). Determined automatically from [HoldingType].
enum HoldingKind { asset, liability }

/// Unified category across all [AssetType] and [LiabilityType] options so
/// selecting a type automatically classifies the entry as an asset or a
/// liability without a separate manual step.
final class HoldingType {
  const HoldingType.asset(AssetType this.assetType) : liabilityType = null;

  const HoldingType.liability(LiabilityType this.liabilityType)
    : assetType = null;

  final AssetType? assetType;
  final LiabilityType? liabilityType;

  HoldingKind get kind =>
      assetType != null ? HoldingKind.asset : HoldingKind.liability;

  bool get isAsset => kind == HoldingKind.asset;

  bool get isLiability => kind == HoldingKind.liability;

  /// Unambiguous label used when asset and liability types appear together.
  String get pickerLabel {
    if (assetType case final AssetType asset) {
      return asset == AssetType.other ? 'Other asset' : asset.displayName;
    }
    final LiabilityType liability = liabilityType!;
    return liability == LiabilityType.other
        ? 'Other liability'
        : liability.displayName;
  }

  static final List<HoldingType> assetTypes = List<HoldingType>.unmodifiable(
    <HoldingType>[
      for (final AssetType type in AssetType.values) HoldingType.asset(type),
    ],
  );

  static final List<HoldingType> liabilityTypes =
      List<HoldingType>.unmodifiable(<HoldingType>[
        for (final LiabilityType type in LiabilityType.values)
          HoldingType.liability(type),
      ]);

  static final List<HoldingType> values = List<HoldingType>.unmodifiable(
    <HoldingType>[...assetTypes, ...liabilityTypes],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HoldingType &&
          other.assetType == assetType &&
          other.liabilityType == liabilityType;

  @override
  int get hashCode => Object.hash(assetType, liabilityType);

  @override
  String toString() => isAsset
      ? 'HoldingType.asset($assetType)'
      : 'HoldingType.liability($liabilityType)';
}
