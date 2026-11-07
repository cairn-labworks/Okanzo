import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../local/app_database.dart';
import '../local/dao/asset_dao.dart';
import '../local/dao/liability_dao.dart';
import '../local/dao/portfolio_dao.dart';
import '../local/entity/asset_entity.dart';
import '../local/entity/liability_entity.dart';
import '../local/entity/portfolio_entity.dart';
import '../security/backup_crypto.dart';
import 'backup_mapper.dart';
import 'backup_models.dart';

/// Exports and imports portfolios as password-encrypted files. Export gathers the
/// selected portfolios with all holdings; import re-creates them as new portfolios
/// so existing data is never overwritten.
class BackupRepository {
  const BackupRepository(
    this._portfolioDao,
    this._assetDao,
    this._liabilityDao,
  );

  final PortfolioDao _portfolioDao;
  final AssetDao _assetDao;
  final LiabilityDao _liabilityDao;

  Future<Uint8List> export(List<int> portfolioIds, String password) async {
    final List<BackupPortfolio> portfolios = <BackupPortfolio>[];
    for (final int id in portfolioIds) {
      final PortfolioEntity? portfolio = await _portfolioDao.getById(id);
      if (portfolio == null) continue;
      final List<AssetEntity> assets = await _assetDao.getForPortfolio(id);
      final List<LiabilityEntity> liabilities = await _liabilityDao
          .getForPortfolio(id);
      portfolios.add(
        BackupPortfolio(
          name: portfolio.name,
          isDefault: portfolio.isDefault,
          assets: assets.map(assetToBackup).toList(growable: false),
          liabilities: liabilities
              .map(liabilityToBackup)
              .toList(growable: false),
        ),
      );
    }
    final BackupFile backup = BackupFile(
      exportedAt: DateTime.now().millisecondsSinceEpoch,
      portfolios: portfolios,
    );
    final Uint8List json = Uint8List.fromList(
      utf8.encode(jsonEncode(backup.toJson())),
    );
    return BackupCrypto.encryptAsync(json, password);
  }

  Future<ImportResult> import(Uint8List data, String password) async {
    final String json = utf8.decode(
      await BackupCrypto.decryptAsync(data, password),
    );
    BackupFile? backup;
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is Map<String, Object?>) {
        backup = BackupFile.fromJson(decoded);
      }
    } on FormatException {
      backup = null;
    }
    if (backup == null) {
      throw const InvalidBackupException('Backup file is not readable.');
    }
    final List<BackupPortfolio>? portfolios = backup.portfolios;
    if (portfolios == null) {
      throw const InvalidBackupException('Backup file contains no portfolios.');
    }

    final AppDatabase appDb = _portfolioDao.database;
    int assetCount = 0;
    int liabilityCount = 0;

    await appDb.db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> existingRows = await txn.query(
        Tables.portfolios,
        orderBy: 'isDefault DESC, name COLLATE NOCASE ASC',
      );
      final List<PortfolioEntity> existingPortfolios = existingRows
          .map(PortfolioEntity.fromMap)
          .toList(growable: false);
      final Set<String> existingNames = <String>{
        for (final PortfolioEntity portfolio in existingPortfolios)
          portfolio.name,
      };
      bool hasDefault = existingPortfolios.any(
        (PortfolioEntity portfolio) => portfolio.isDefault,
      );
      int? firstExistingId = existingPortfolios.firstOrNull?.id;

      for (final BackupPortfolio portfolio in portfolios) {
        final String name = uniqueName(
          portfolio.name.trim().isEmpty ? 'Imported portfolio' : portfolio.name,
          existingNames,
        );
        existingNames.add(name);
        final int now = DateTime.now().millisecondsSinceEpoch;
        final bool makeDefault = !hasDefault && firstExistingId == null;
        if (makeDefault) hasDefault = true;
        final int portfolioId = await txn.insert(
          Tables.portfolios,
          PortfolioEntity(
            name: name,
            isDefault: makeDefault,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        for (final BackupAsset asset
            in portfolio.assets ?? const <BackupAsset>[]) {
          await txn.insert(
            Tables.assets,
            backupToAsset(asset, portfolioId, now).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          assetCount++;
        }
        for (final BackupLiability liability
            in portfolio.liabilities ?? const <BackupLiability>[]) {
          await txn.insert(
            Tables.liabilities,
            backupToLiability(liability, portfolioId, now).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          liabilityCount++;
        }
      }

      if (!hasDefault && firstExistingId != null) {
        await txn.rawUpdate(
          'UPDATE ${Tables.portfolios} SET isDefault = 1 WHERE id = ?',
          <Object?>[firstExistingId],
        );
      }
    });

    appDb.notify(<String>{
      Tables.portfolios,
      Tables.assets,
      Tables.liabilities,
    });

    return ImportResult(
      portfolios: portfolios.length,
      assets: assetCount,
      liabilities: liabilityCount,
    );
  }
}
