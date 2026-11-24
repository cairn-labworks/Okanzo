import 'package:sqflite_sqlcipher/sqflite.dart';

import '../app_database.dart';
import '../entity/portfolio_entity.dart';

class DuplicatePortfolioNameException implements Exception {
  const DuplicatePortfolioNameException();
}

class PortfolioDao {
  const PortfolioDao(this._database);

  final AppDatabase _database;

  AppDatabase get database => _database;

  Database get _db => _database.db;

  static const String _order = 'isDefault DESC, name COLLATE NOCASE ASC';

  Stream<List<PortfolioEntity>> observeAll() =>
      _database.watch(<String>{Tables.portfolios}, getAll);

  Stream<PortfolioEntity?> observeById(int id) =>
      _database.watch(<String>{Tables.portfolios}, () => getById(id));

  Future<List<PortfolioEntity>> getAll() async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.portfolios,
      orderBy: _order,
    );
    return rows.map(PortfolioEntity.fromMap).toList(growable: false);
  }

  Future<PortfolioEntity?> getById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.portfolios,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return rows.isEmpty ? null : PortfolioEntity.fromMap(rows.first);
  }

  Future<PortfolioEntity?> getDefault() async {
    final List<Map<String, Object?>> rows = await _db.query(
      Tables.portfolios,
      where: 'isDefault = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : PortfolioEntity.fromMap(rows.first);
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM ${Tables.portfolios}'),
      ) ??
      0;

  Future<int> insert(PortfolioEntity portfolio) async {
    final int id = await _db.transaction((Transaction txn) async {
      await _checkName(txn, portfolio.name);
      return txn.insert(Tables.portfolios, portfolio.toMap());
    });
    _notifyPortfolios();
    return id;
  }

  Future<void> rename(int id, String name, int updatedAt) async {
    await _db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        Tables.portfolios,
        columns: <String>['name'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (rows.isEmpty || rows.first['name'] == name) return;
      await _checkName(txn, name, exceptId: id);
      await txn.update(
        Tables.portfolios,
        <String, Object?>{'name': name, 'updatedAt': updatedAt},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
    _notifyPortfolios();
  }

  Future<void> _checkName(Transaction txn, String name, {int? exceptId}) async {
    final String key = name.trim().toLowerCase();
    final List<Map<String, Object?>> rows = await txn.query(
      Tables.portfolios,
      columns: <String>['id', 'name'],
    );
    if (rows.any(
      (row) =>
          row['id'] != exceptId &&
          (row['name'] as String).trim().toLowerCase() == key,
    )) {
      throw const DuplicatePortfolioNameException();
    }
  }

  Future<void> deleteById(int id) async {
    await _db.delete(
      Tables.portfolios,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    _database.notify(<String>{
      Tables.portfolios,
      Tables.assets,
      Tables.liabilities,
    });
  }

  /// Atomically make [id] the one and only default portfolio.
  Future<void> setDefault(int id) async {
    await _db.transaction((Transaction txn) async {
      await txn.rawUpdate('UPDATE ${Tables.portfolios} SET isDefault = 0');
      await txn.rawUpdate(
        'UPDATE ${Tables.portfolios} SET isDefault = 1 WHERE id = ?',
        <Object?>[id],
      );
    });
    _notifyPortfolios();
  }

  void _notifyPortfolios() => _database.notify(<String>{Tables.portfolios});
}
