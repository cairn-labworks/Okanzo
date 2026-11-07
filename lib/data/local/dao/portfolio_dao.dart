import 'package:sqflite_sqlcipher/sqflite.dart';

import '../app_database.dart';
import '../entity/portfolio_entity.dart';

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
    final int id = await _db.insert(
      Tables.portfolios,
      portfolio.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyPortfolios();
    return id;
  }

  Future<void> update(PortfolioEntity portfolio) async {
    await _db.update(
      Tables.portfolios,
      portfolio.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[portfolio.id],
    );
    _notifyPortfolios();
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
