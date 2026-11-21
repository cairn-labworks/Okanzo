import '../../domain/model/asset_type.dart';
import '../../domain/model/liability_type.dart';
import '../../domain/model/precious_metal.dart';
import '../local/entity/asset_entity.dart';
import '../local/entity/liability_entity.dart';
import 'backup_models.dart';

/// Conversions between stored entities and their backup representation, kept
/// separate from database access so the mapping can be tested on its own.
BackupAsset assetToBackup(AssetEntity asset) => BackupAsset(
  type: asset.type.storageName,
  name: asset.name,
  customName: asset.customName,
  currency: asset.currency,
  quantity: asset.quantity,
  pricePerUnit: asset.pricePerUnit,
  metal: asset.metal?.name,
  purity: asset.purity,
  customPrice: asset.customPrice,
  useTotalValue: asset.useTotalValue,
  symbol: asset.symbol,
  lastPrice: asset.lastPrice,
  lastPriceTimestamp: asset.lastPriceTimestamp,
  manualValue: asset.manualValue,
  notes: asset.notes,
  position: asset.position,
);

BackupLiability liabilityToBackup(LiabilityEntity liability) => BackupLiability(
  type: liability.type.storageName,
  name: liability.name,
  currency: liability.currency,
  amount: liability.amount,
  notes: liability.notes,
  position: liability.position,
);

AssetEntity backupToAsset(BackupAsset asset, int portfolioId, int now) =>
    AssetEntity(
      portfolioId: portfolioId,
      type: AssetType.fromName(asset.type),
      name: asset.name,
      customName: asset.customName,
      currency: asset.currency,
      quantity: asset.quantity,
      pricePerUnit: asset.pricePerUnit,
      metal: PreciousMetal.fromName(asset.metal),
      purity: asset.purity,
      customPrice: asset.customPrice,
      useTotalValue: asset.useTotalValue,
      symbol: asset.symbol,
      lastPrice: asset.lastPrice,
      lastPriceTimestamp: asset.lastPriceTimestamp,
      manualValue: asset.manualValue,
      notes: asset.notes,
      position: asset.position,
      createdAt: now,
      updatedAt: now,
    );

LiabilityEntity backupToLiability(
  BackupLiability liability,
  int portfolioId,
  int now,
) => LiabilityEntity(
  portfolioId: portfolioId,
  type: LiabilityType.fromName(liability.type),
  name: liability.name,
  currency: liability.currency,
  amount: liability.amount,
  notes: liability.notes,
  position: liability.position,
  createdAt: now,
  updatedAt: now,
);

/// Returns [base] if it is free, otherwise "base (2)", "base (3)" and so on, so
/// an import never silently merges into an existing portfolio.
String uniqueName(String base, Set<String> taken) {
  if (!taken.contains(base)) return base;
  int i = 2;
  while (taken.contains('$base ($i)')) {
    i++;
  }
  return '$base ($i)';
}
