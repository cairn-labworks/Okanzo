import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../domain/model/asset_type.dart';
import '../app_database.dart';
import '../entity/asset_entity.dart';

class AssetDao {
  const AssetDao(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  Stream<List<AssetEntity>> observeForPortfolio(int portfolioId) =>
      _database.watch(<String>{
        Tables.assets,
      }, () => getForPortfolioOrdered(portfolioId));

  Stream<AssetEntity?> observeById(int id) =>
      _database.watch(<String>{Tables.assets}, () => getById(id));

  Future<List<AssetEntity>> getForPortfolioOrdered(int portfolioId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.assets,
      where: 'portfolioId = ?',
      whereArgs: <Object?>[portfolioId],
      orderBy: 'position ASC, updatedAt DESC',
    );
    return rows.map(AssetEntity.fromMap).toList(growable: false);
  }

  Future<List<AssetEntity>> getForPortfolio(int portfolioId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.assets,
      where: 'portfolioId = ?',
      whereArgs: <Object?>[portfolioId],
    );
    return rows.map(AssetEntity.fromMap).toList(growable: false);
  }

  Future<AssetEntity?> getById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.assets,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return rows.isEmpty ? null : AssetEntity.fromMap(rows.first);
  }

  Future<int> insert(AssetEntity asset) async {
    final int id = await _db.insert(
      Tables.assets,
      asset.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
    return id;
  }

  Future<void> update(AssetEntity asset) async {
    await _db.update(
      Tables.assets,
      asset.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[asset.id],
    );
    _notify();
  }

  Future<void> deleteById(int id) async {
    await _db.delete(Tables.assets, where: 'id = ?', whereArgs: <Object?>[id]);
    _notify();
  }

  Future<void> updatePrice(
    int id,
    double price,
    int timestamp, {
    String? currency,
  }) async {
    await _db.update(
      Tables.assets,
      <String, Object?>{
        'lastPrice': price,
        'lastPriceTimestamp': timestamp,
        'updatedAt': timestamp,
        if (currency != null && currency.isNotEmpty) 'currency': currency,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    _notify();
  }

  /// Updates multiple asset prices in a single transaction and notifies once.
  Future<void> updatePrices(
    List<({int id, double price, int timestamp, String? currency})> updates,
  ) async {
    if (updates.isEmpty) return;
    await _db.transaction((Transaction txn) async {
      for (final ({int id, double price, int timestamp, String? currency})
          update
          in updates) {
        await txn.update(
          Tables.assets,
          <String, Object?>{
            'lastPrice': update.price,
            'lastPriceTimestamp': update.timestamp,
            'updatedAt': update.timestamp,
            if (update.currency != null && update.currency!.isNotEmpty)
              'currency': update.currency,
          },
          where: 'id = ?',
          whereArgs: <Object?>[update.id],
        );
      }
    });
    _notify();
  }

  Future<int> maxPosition(int portfolioId, AssetType type) async =>
      Sqflite.firstIntValue(
        await _db.rawQuery(
          'SELECT COALESCE(MAX(position), -1) FROM ${Tables.assets} '
          'WHERE portfolioId = ? AND type = ?',
          <Object?>[portfolioId, type.storageName],
        ),
      ) ??
      -1;

  /// Persists a new order for the given asset ids (index becomes position).
  Future<void> updatePositions(List<int> orderedIds) async {
    await _db.transaction((Transaction txn) async {
      for (int index = 0; index < orderedIds.length; index++) {
        await txn.rawUpdate(
          'UPDATE ${Tables.assets} SET position = ? WHERE id = ?',
          <Object?>[index, orderedIds[index]],
        );
      }
    });
    _notify();
  }

  void _notify() => _database.notify(<String>{Tables.assets});
}
