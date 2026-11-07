import 'dart:convert';
import 'dart:typed_data';

import 'package:okanzo/data/backup/backup_models.dart';
import 'package:okanzo/data/security/backup_crypto.dart';
import 'package:test/test.dart';

/// A backup produced by the original Android/Kotlin implementation
/// (PBKDF2WithHmacSHA256, 210k iterations, AES-256/GCM with a 128-bit tag),
/// generated with a fixed salt and IV so the fixture stays stable.
const String _goldenBackupBase64 =
    'TVdCMQEDChEYHyYtNDtCSVBXXmVsBRAbJjE8R1JdaHN+9o6HrVAjQ7y3LWhk9wPsZBOO65ib'
    '8d+bZDHkQIsfD/4aoG69jf1vST0Qb/bDDSmCEsBgEcPDRhVLY2+G40rBJDu3J9qB7TgphCGW'
    'F5VMV3OJOjDfr61vNqt2bZEM2Quh6TWM3H7Imk1zsLkSe/kPo0DEt/flMwnhGnYHgm5k7V2v'
    '8aQeaVEdBJgzFVH0QhD5GxgDIjY9IfNFx/lVLan/+zYZLKDUQu1VEA77f4u6Zc3fLCY0gtR+'
    '30Xa2pLbCblUfE2/rh6A9XjJuom9cfPj4Mam+KiT8C3yoS4NfP6mVHA8C05FKZNqTJRyMh05'
    'HwNw0aVb936RH5zk0uPTl83ynJrdcIrR7Mk3RN1OdIXZG2cFMAf8bZKJ+pInNAxo09LW/2v6'
    'N+Or6OVFVcw0PR1SdcKlW3g8lmL0ZVXOup//ZjwralC6g4gjiAlfQfF3TL+2zbyTVRTkDkkJ'
    'E+T1HSIY3Q0FpqZYVzyCaHAcHSZDpLJBRsIxMxXQmoLOVwuPl6Vk+yayIhLd3D/MOUnvxeUW'
    'oPeeHHe/jnKAkcMa/lOKKeCqt4SKp2Wdn+9HWn3Fi0YZAx91B6T1msHA0jLE+ZttwONyQyx+'
    '/cjFEiCt9XyiPnE7zCvuNdGjCpblFIFdJm6sWog=';

/// Deliberately non-ASCII, proving the password is UTF-8 encoded exactly like
/// Java's `PBEKeySpec`.
const String _goldenPassword = 'pässwörd✓ 1';

// NOTE: this is the decrypted plaintext of the immutable _goldenBackupBase64
// fixture produced by the original Android/Kotlin app, so the "app" field must
// stay as the historical name ("Networthy") for the round-trip to be exact.
// New backups written by this app use the current name (see BackupFile default).
const String _goldenJson =
    '{"schema":1,"app":"Networthy","exportedAt":1717171717171,"portfolios":'
    '[{"name":"Golden","isDefault":true,"assets":'
    '[{"type":"STOCK","name":"Acme Corp","currency":"USD","quantity":12.5,'
    '"symbol":"ACME","lastPrice":31.4,"lastPriceTimestamp":1717171700000,'
    '"position":0},'
    '{"type":"CASH","name":"Wallet","currency":"EUR","manualValue":250.0,'
    '"notes":"emergency","position":1}],"liabilities":'
    '[{"type":"LOAN","name":"Car loan","currency":"USD","amount":4200.0,'
    '"position":0}]}]}';

void main() {
  group('MWB1 container', () {
    test('round-trips a payload', () {
      final Uint8List payload = Uint8List.fromList(utf8.encode('hello wealth'));
      final Uint8List file = BackupCrypto.encrypt(payload, 'swordfish');

      expect(utf8.decode(file.sublist(0, 4)), 'MWB1');
      expect(file[4], 1);
      expect(file.length, greaterThan(4 + 1 + 16 + 12));
      expect(
        utf8.decode(BackupCrypto.decrypt(file, 'swordfish')),
        'hello wealth',
      );
    });

    test('uses a fresh salt and IV for every export', () {
      final Uint8List payload = Uint8List.fromList(utf8.encode('same input'));
      final Uint8List first = BackupCrypto.encrypt(payload, 'pw');
      final Uint8List second = BackupCrypto.encrypt(payload, 'pw');
      expect(first.sublist(5, 33), isNot(second.sublist(5, 33)));
    });

    test('rejects the wrong password', () {
      final Uint8List file = BackupCrypto.encrypt(
        Uint8List.fromList(utf8.encode('secret')),
        'right',
      );
      expect(
        () => BackupCrypto.decrypt(file, 'wrong'),
        throwsA(
          isA<InvalidBackupException>().having(
            (InvalidBackupException e) => e.message,
            'message',
            'Incorrect password or corrupted file.',
          ),
        ),
      );
    });

    test('rejects a truncated file', () {
      expect(
        () => BackupCrypto.decrypt(Uint8List.fromList(<int>[1, 2, 3]), 'pw'),
        throwsA(
          isA<InvalidBackupException>().having(
            (InvalidBackupException e) => e.message,
            'message',
            'File is not a valid Okanzo backup.',
          ),
        ),
      );
    });

    test('rejects a file with foreign magic bytes', () {
      final Uint8List file = BackupCrypto.encrypt(
        Uint8List.fromList(utf8.encode('secret')),
        'pw',
      );
      file[1] = 0x58;
      expect(
        () => BackupCrypto.decrypt(file, 'pw'),
        throwsA(
          isA<InvalidBackupException>().having(
            (InvalidBackupException e) => e.message,
            'message',
            'File is not a valid Okanzo backup.',
          ),
        ),
      );
    });

    test('tampered ciphertext fails authentication', () {
      final Uint8List file = BackupCrypto.encrypt(
        Uint8List.fromList(utf8.encode('secret')),
        'pw',
      );
      file[file.length - 1] ^= 0xFF;
      expect(
        () => BackupCrypto.decrypt(file, 'pw'),
        throwsA(isA<InvalidBackupException>()),
      );
    });

    test(
      'encryptAsync and decryptAsync round-trip on a background isolate',
      () async {
        final Uint8List payload = Uint8List.fromList(
          utf8.encode('isolate backup payload'),
        );
        final Uint8List encrypted = await BackupCrypto.encryptAsync(
          payload,
          'swordfish',
        );
        final Uint8List decrypted = await BackupCrypto.decryptAsync(
          encrypted,
          'swordfish',
        );
        expect(utf8.decode(decrypted), 'isolate backup payload');
        await expectLater(
          BackupCrypto.decryptAsync(encrypted, 'wrong'),
          throwsA(isA<InvalidBackupException>()),
        );
      },
    );
  });

  group('Android compatibility', () {
    test('decrypts a backup written by the Kotlin app', () {
      final Uint8List golden = base64.decode(_goldenBackupBase64);
      final String json = utf8.decode(
        BackupCrypto.decrypt(golden, _goldenPassword),
      );
      expect(json, _goldenJson);
    });

    test('parses the Kotlin payload into the same model graph', () {
      final Uint8List golden = base64.decode(_goldenBackupBase64);
      final BackupFile backup = BackupFile.fromJson(
        jsonDecode(utf8.decode(BackupCrypto.decrypt(golden, _goldenPassword)))
            as Map<String, Object?>,
      );

      expect(backup.schema, 1);
      expect(backup.app, 'Networthy');
      expect(backup.exportedAt, 1717171717171);
      expect(backup.portfolios, hasLength(1));

      final BackupPortfolio portfolio = backup.portfolios!.single;
      expect(portfolio.name, 'Golden');
      expect(portfolio.isDefault, isTrue);
      expect(portfolio.assets, hasLength(2));
      expect(portfolio.assets![0].symbol, 'ACME');
      expect(portfolio.assets![0].quantity, 12.5);
      expect(portfolio.assets![0].lastPrice, 31.4);
      expect(portfolio.assets![0].pricePerUnit, isNull);
      expect(portfolio.assets![1].manualValue, 250.0);
      expect(portfolio.assets![1].notes, 'emergency');
      expect(portfolio.assets![1].position, 1);
      expect(portfolio.liabilities!.single.amount, 4200.0);
    });

    test('re-serialises to byte-identical Gson JSON', () {
      final Uint8List golden = base64.decode(_goldenBackupBase64);
      final BackupFile backup = BackupFile.fromJson(
        jsonDecode(utf8.decode(BackupCrypto.decrypt(golden, _goldenPassword)))
            as Map<String, Object?>,
      );
      expect(jsonEncode(backup.toJson()), _goldenJson);
    });

    test('a Dart-written backup can be read back with the same parameters', () {
      final Uint8List file = BackupCrypto.encrypt(
        Uint8List.fromList(utf8.encode(_goldenJson)),
        _goldenPassword,
      );
      // Header layout must stay identical for the Kotlin reader.
      expect(file.sublist(0, 5), <int>[0x4D, 0x57, 0x42, 0x31, 0x01]);
      expect(
        file.length,
        4 + 1 + 16 + 12 + utf8.encode(_goldenJson).length + 16,
      );
      expect(
        utf8.decode(BackupCrypto.decrypt(file, _goldenPassword)),
        _goldenJson,
      );
    });
  });
}
