import 'dart:convert';

import 'package:okanzo/data/backup/backup_mapper.dart';
import 'package:okanzo/data/backup/backup_models.dart';
import 'package:okanzo/data/local/entity/asset_entity.dart';
import 'package:okanzo/data/local/entity/liability_entity.dart';
import 'package:okanzo/domain/model/asset_type.dart';
import 'package:okanzo/domain/model/liability_type.dart';
import 'package:okanzo/util/relative_time.dart';
import 'package:test/test.dart';

void main() {
  group('uniqueName', () {
    test('keeps the original name when it is free', () {
      expect(uniqueName('Main', <String>{'Other'}), 'Main');
    });

    test('appends the first free numeric suffix', () {
      expect(uniqueName('Main', <String>{'Main'}), 'Main (2)');
      expect(uniqueName('Main', <String>{'Main', 'Main (2)'}), 'Main (3)');
      expect(
        uniqueName('Main', <String>{'Main', 'Main (2)', 'Main (4)'}),
        'Main (3)',
      );
    });
  });

  group('backup mapping', () {
    test(
      'silver metadata and per-gram value survive database and backup maps',
      () {
        final AssetEntity asset = AssetEntity.fromMap(<String, Object?>{
          'id': 42,
          'portfolioId': 1,
          'type': 'METALS',
          'name': 'Sterling pendant',
          'currency': 'USD',
          'metal': 'silver',
          'purity': '925',
          'quantity': 12.5,
          'lastPrice': 0.74,
          'createdAt': 0,
          'updatedAt': 0,
        });
        expect(asset.value, 9.25);
        expect(asset.toMap()['purity'], '925');
        final json = assetToBackup(asset).toJson();
        expect(json['metal'], 'silver');
        expect(json['purity'], '925');
        expect(backupToAsset(BackupAsset.fromJson(json), 2, 0).value, 9.25);
      },
    );

    final AssetEntity asset = AssetEntity(
      id: 11,
      portfolioId: 5,
      type: AssetType.stock,
      name: 'Apple',
      currency: 'USD',
      quantity: 3.0,
      symbol: 'AAPL',
      lastPrice: 190.0,
      lastPriceTimestamp: 1700000000000,
      notes: 'core',
      position: 2,
      createdAt: 1,
      updatedAt: 2,
    );

    test('asset ids and timestamps are not exported', () {
      final Map<String, Object?> json = assetToBackup(asset).toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('portfolioId'), isFalse);
      expect(json.containsKey('createdAt'), isFalse);
      expect(json.containsKey('updatedAt'), isFalse);
      expect(json['type'], 'STOCK');
      expect(json['position'], 2);
    });

    test('null asset fields are omitted, like Gson', () {
      final Map<String, Object?> json = assetToBackup(
        AssetEntity(
          portfolioId: 1,
          type: AssetType.cash,
          name: 'Wallet',
          currency: 'EUR',
          manualValue: 50.0,
          createdAt: 0,
          updatedAt: 0,
        ),
      ).toJson();
      expect(json.keys.toList(), <String>[
        'type',
        'name',
        'currency',
        'manualValue',
        'position',
      ]);
    });

    test('importing re-parents the asset and stamps the clock', () {
      final AssetEntity restored = backupToAsset(assetToBackup(asset), 42, 999);
      expect(restored.id, 0);
      expect(restored.portfolioId, 42);
      expect(restored.createdAt, 999);
      expect(restored.updatedAt, 999);
      expect(restored.name, 'Apple');
      expect(restored.customName, isNull);
      expect(restored.symbol, 'AAPL');
      expect(restored.lastPriceTimestamp, 1700000000000);
      expect(restored.position, 2);

      final AssetEntity withCustom = asset.copyWith(customName: 'Core Apple');
      final Map<String, Object?> customJson = assetToBackup(withCustom)
          .toJson();
      expect(customJson['customName'], 'Core Apple');
      final AssetEntity restoredCustom = backupToAsset(
        BackupAsset.fromJson(customJson),
        42,
        999,
      );
      expect(restoredCustom.name, 'Apple');
      expect(restoredCustom.customName, 'Core Apple');
      expect(restoredCustom.displayName, 'Core Apple');
    });

    test('unknown types fall back instead of failing the import', () {
      final AssetEntity restored = backupToAsset(
        const BackupAsset(type: 'CRYPTO_V2', name: 'X', currency: 'USD'),
        1,
        0,
      );
      expect(restored.type, AssetType.other);

      final LiabilityEntity liability = backupToLiability(
        const BackupLiability(
          type: 'NOPE',
          name: 'Y',
          currency: 'USD',
          amount: 1.0,
        ),
        1,
        0,
      );
      expect(liability.type, LiabilityType.other);
    });

    test('liabilities round-trip through the backup model', () {
      final LiabilityEntity restored = backupToLiability(
        liabilityToBackup(
          LiabilityEntity(
            id: 3,
            portfolioId: 9,
            type: LiabilityType.mortgage,
            name: 'House',
            currency: 'GBP',
            amount: 123.45,
            position: 1,
            createdAt: 5,
            updatedAt: 6,
          ),
        ),
        7,
        8,
      );
      expect(restored.portfolioId, 7);
      expect(restored.type, LiabilityType.mortgage);
      expect(restored.amount, 123.45);
      expect(restored.notes, isNull);
      expect(restored.createdAt, 8);
    });
  });

  group('BackupFile JSON', () {
    test('has the field order the Android export produced', () {
      const BackupFile file = BackupFile(
        exportedAt: 123,
        portfolios: <BackupPortfolio>[
          BackupPortfolio(
            name: 'Main',
            isDefault: true,
            assets: <BackupAsset>[],
            liabilities: <BackupLiability>[],
          ),
        ],
      );
      expect(
        jsonEncode(file.toJson()),
        '{"schema":1,"app":"Okanzo","exportedAt":123,'
        '"portfolios":[{"name":"Main","isDefault":true,'
        '"assets":[],"liabilities":[]}]}',
      );
    });

    test('tolerates a file with missing collections', () {
      final BackupFile parsed = BackupFile.fromJson(
        jsonDecode('{"schema":1,"app":"Okanzo","exportedAt":1}')
            as Map<String, Object?>,
      );
      expect(parsed.portfolios, isNull);
      expect(parsed.exportedAt, 1);
    });

    test('parses portfolios with partial asset records', () {
      final BackupFile parsed = BackupFile.fromJson(
        jsonDecode(
          '{"schema":1,"app":"Okanzo","exportedAt":1,"portfolios":'
          '[{"name":"P","isDefault":false,"assets":'
          '[{"type":"CASH","name":"A","currency":"USD"}]}]}',
        ) as Map<String, Object?>,
      );
      final BackupPortfolio portfolio = parsed.portfolios!.single;
      expect(portfolio.liabilities, isNull);
      expect(portfolio.assets!.single.quantity, isNull);
      expect(portfolio.assets!.single.position, 0);
    });
  });

  group('relativeTimeSpan', () {
    final DateTime now = DateTime(2024, 5, 20, 12);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

    test('under a minute reads as zero minutes', () {
      expect(
        relativeTimeSpan(ago(const Duration(seconds: 30)), now: now),
        '0 minutes ago',
      );
    });

    test('minutes and hours are singular at one', () {
      expect(
        relativeTimeSpan(ago(const Duration(minutes: 1)), now: now),
        '1 minute ago',
      );
      expect(
        relativeTimeSpan(ago(const Duration(minutes: 5)), now: now),
        '5 minutes ago',
      );
      expect(
        relativeTimeSpan(ago(const Duration(hours: 1)), now: now),
        '1 hour ago',
      );
      expect(
        relativeTimeSpan(ago(const Duration(hours: 23)), now: now),
        '23 hours ago',
      );
    });

    test('one day is "Yesterday" and the rest of the week counts days', () {
      expect(
        relativeTimeSpan(ago(const Duration(days: 1)), now: now),
        'Yesterday',
      );
      expect(
        relativeTimeSpan(ago(const Duration(days: 6)), now: now),
        '6 days ago',
      );
    });

    test('a week or more falls back to a date', () {
      final String label = relativeTimeSpan(
        ago(const Duration(days: 30)),
        now: now,
      );
      expect(label, contains('2024'));
      expect(label, isNot(contains('ago')));
    });

    test('future timestamps render as a date', () {
      final String label = relativeTimeSpan(
        now.add(const Duration(days: 2)).millisecondsSinceEpoch,
        now: now,
      );
      expect(label, contains('2024'));
    });
  });
}
