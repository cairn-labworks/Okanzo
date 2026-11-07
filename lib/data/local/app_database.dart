import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

/// Table names, also used as change-notification topics.
class Tables {
  const Tables._();

  static const String portfolios = 'portfolios';
  static const String assets = 'assets';
  static const String liabilities = 'liabilities';
  static const String fxRates = 'fx_rates';
}

/// The encrypted SQLCipher database holding every portfolio, asset, liability
/// and cached exchange rate. Nothing here ever leaves the device.
///
/// Room invalidates queries automatically; sqflite does not, so writes announce
/// the tables they touched through [changes] and [watch] re-runs the read.
class AppDatabase {
  AppDatabase(this.db);

  static const String databaseName = 'okanzo.db';

  /// The pre-rebrand database filename. Kept only so upgrading users' data can
  /// be migrated to [databaseName] (see AppContainer); it is not a brand name.
  static const String legacyDatabaseName = 'mywealth.db';
  static const int schemaVersion = 2;

  final Database db;

  final StreamController<Set<String>> _changes =
      StreamController<Set<String>>.broadcast();

  /// Opens (or creates) the encrypted database with [password] as the key.
  ///
  /// Migrations are managed manually via `PRAGMA user_version` instead of
  /// sqflite's `version`/`onCreate`/`onUpgrade` callbacks. Those callbacks make
  /// sqflite_common cast the open options to its concrete
  /// `SqfliteOpenDatabaseOptions`, which the `sqflite_sqlcipher` options object
  /// does not extend, so the version-managed open path throws
  /// "SqfliteSqlCipherOpenDatabaseOptions is not a subtype of
  /// SqfliteOpenDatabaseOptions". Opening with just the password sidesteps that
  /// path entirely while keeping the exact same schema and migration steps.
  static Future<AppDatabase> open({
    required String path,
    required String password,
  }) async {
    final Database db = await openDatabase(path, password: password);
    await _migrate(db);
    return AppDatabase(db);
  }

  /// Applies the schema at [schemaVersion], creating tables on first run and
  /// upgrading older databases in place, tracking progress with
  /// `PRAGMA user_version`.
  static Future<void> _migrate(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    final int currentVersion =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;

    if (currentVersion == 0) {
      await db.transaction((Transaction txn) async {
        for (final String statement in _createStatements) {
          await txn.execute(statement);
        }
      });
      await db.execute('PRAGMA user_version = $schemaVersion');
      return;
    }

    if (currentVersion < 2) {
      await db.transaction((Transaction txn) async {
        await txn.execute(
          'ALTER TABLE assets ADD COLUMN position INTEGER NOT NULL DEFAULT 0',
        );
        await txn.execute(
          'ALTER TABLE liabilities '
          'ADD COLUMN position INTEGER NOT NULL DEFAULT 0',
        );
      });
    }

    for (final String statement in _orderingIndexStatements) {
      await db.execute(statement);
    }

    if (currentVersion != schemaVersion) {
      await db.execute('PRAGMA user_version = $schemaVersion');
    }
  }

  /// Emits the set of tables touched by the most recent write.
  Stream<Set<String>> get changes => _changes.stream;

  /// Announces that [tables] changed so open [watch] streams reload.
  void notify(Set<String> tables) {
    if (!_changes.isClosed) _changes.add(tables);
  }

  /// Runs [load] now and again whenever any of [tables] changes.
  Stream<T> watch<T>(Set<String> tables, Future<T> Function() load) async* {
    yield await load();
    await for (final Set<String> changed in changes) {
      if (changed.any(tables.contains)) {
        yield await load();
      }
    }
  }

  Future<void> close() async {
    await _changes.close();
    await db.close();
  }

  static const List<String> _createStatements = <String>[
    'CREATE TABLE IF NOT EXISTS portfolios ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
        'name TEXT NOT NULL, '
        'isDefault INTEGER NOT NULL, '
        'createdAt INTEGER NOT NULL, '
        'updatedAt INTEGER NOT NULL)',
    'CREATE TABLE IF NOT EXISTS assets ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
        'portfolioId INTEGER NOT NULL, '
        'type TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'currency TEXT NOT NULL, '
        'quantity REAL, '
        'pricePerUnit REAL, '
        'symbol TEXT, '
        'lastPrice REAL, '
        'lastPriceTimestamp INTEGER, '
        'manualValue REAL, '
        'notes TEXT, '
        'position INTEGER NOT NULL DEFAULT 0, '
        'createdAt INTEGER NOT NULL, '
        'updatedAt INTEGER NOT NULL, '
        'FOREIGN KEY(portfolioId) REFERENCES portfolios(id) '
        'ON UPDATE NO ACTION ON DELETE CASCADE)',
    'CREATE INDEX IF NOT EXISTS index_assets_portfolioId '
        'ON assets (portfolioId)',
    'CREATE INDEX IF NOT EXISTS index_assets_portfolioId_position_updatedAt '
        'ON assets (portfolioId, position ASC, updatedAt DESC)',
    'CREATE TABLE IF NOT EXISTS liabilities ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
        'portfolioId INTEGER NOT NULL, '
        'type TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'currency TEXT NOT NULL, '
        'amount REAL NOT NULL, '
        'notes TEXT, '
        'position INTEGER NOT NULL DEFAULT 0, '
        'createdAt INTEGER NOT NULL, '
        'updatedAt INTEGER NOT NULL, '
        'FOREIGN KEY(portfolioId) REFERENCES portfolios(id) '
        'ON UPDATE NO ACTION ON DELETE CASCADE)',
    'CREATE INDEX IF NOT EXISTS index_liabilities_portfolioId '
        'ON liabilities (portfolioId)',
    'CREATE INDEX IF NOT EXISTS '
        'index_liabilities_portfolioId_position_updatedAt '
        'ON liabilities (portfolioId, position ASC, updatedAt DESC)',
    'CREATE TABLE IF NOT EXISTS fx_rates ('
        'currency TEXT NOT NULL, '
        'unitsPerUsd REAL NOT NULL, '
        'timestamp INTEGER NOT NULL, '
        'PRIMARY KEY(currency))',
  ];

  static const List<String> _orderingIndexStatements = <String>[
    'CREATE INDEX IF NOT EXISTS index_assets_portfolioId_position_updatedAt '
        'ON assets (portfolioId, position ASC, updatedAt DESC)',
    'CREATE INDEX IF NOT EXISTS '
        'index_liabilities_portfolioId_position_updatedAt '
        'ON liabilities (portfolioId, position ASC, updatedAt DESC)',
  ];
}
