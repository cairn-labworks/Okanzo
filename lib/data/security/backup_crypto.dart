import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Raised when a backup file can't be read with the supplied password.
class InvalidBackupException implements Exception {
  const InvalidBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Password-based authenticated encryption for portfolio export/import files.
///
/// File layout (all binary):
///   magic[4] = "MWB1"
///   version[1]
///   salt[16]
///   iv[12]
///   ciphertext + GCM tag
///
/// The key is derived from the user's password with PBKDF2-HMAC-SHA256 so an
/// exported file is useless without the password, keeping data secure at rest
/// even outside the device. The layout and parameters match the Android app
/// byte-for-byte, so backups are interchangeable between the two versions.
class BackupCrypto {
  const BackupCrypto._();

  static const List<int> _magic = <int>[0x4D, 0x57, 0x42, 0x31]; // "MWB1"
  static const int _version = 1;
  static const int _saltLength = 16;
  static const int _ivLength = 12;
  static const int _tagLengthBits = 128;
  static const int _pbkdf2Iterations = 210000;
  static const int _keyLengthBytes = 32;

  static final Random _random = Random.secure();

  /// Runs [encrypt] on a background isolate so the 210,000-iteration PBKDF2 key
  /// derivation never blocks the UI thread.
  static Future<Uint8List> encryptAsync(Uint8List plaintext, String password) =>
      Isolate.run(() => encrypt(plaintext, password));

  /// Runs [decrypt] on a background isolate so the 210,000-iteration PBKDF2 key
  /// derivation never blocks the UI thread.
  static Future<Uint8List> decryptAsync(Uint8List data, String password) =>
      Isolate.run(() => decrypt(data, password));

  static Uint8List encrypt(Uint8List plaintext, String password) {
    final Uint8List salt = randomBytes(_saltLength);
    final Uint8List iv = randomBytes(_ivLength);
    final Uint8List ciphertext = _crypt(
      forEncryption: true,
      data: plaintext,
      key: deriveKey(password, salt),
      iv: iv,
    );

    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_version)
      ..add(salt)
      ..add(iv)
      ..add(ciphertext);
    return builder.toBytes();
  }

  static Uint8List decrypt(Uint8List data, String password) {
    const int header = 4 + 1 + _saltLength + _ivLength;
    if (data.length < header) {
      throw const InvalidBackupException('File is not a valid Okanzo backup.');
    }
    int offset = 0;
    final Uint8List magic = Uint8List.sublistView(data, 0, _magic.length);
    offset += _magic.length;
    for (int i = 0; i < _magic.length; i++) {
      if (magic[i] != _magic[i]) {
        throw const InvalidBackupException(
          'File is not a valid Okanzo backup.',
        );
      }
    }
    offset += 1; // version (only v1 exists today)
    final Uint8List salt = Uint8List.sublistView(
      data,
      offset,
      offset + _saltLength,
    );
    offset += _saltLength;
    final Uint8List iv = Uint8List.sublistView(
      data,
      offset,
      offset + _ivLength,
    );
    offset += _ivLength;
    final Uint8List ciphertext = Uint8List.sublistView(data, offset);

    try {
      return _crypt(
        forEncryption: false,
        data: ciphertext,
        key: deriveKey(password, salt),
        iv: iv,
      );
    } on Object {
      throw const InvalidBackupException(
        'Incorrect password or corrupted file.',
      );
    }
  }

  /// PBKDF2-HMAC-SHA256 over the UTF-8 bytes of [password], matching the
  /// `PBKDF2WithHmacSHA256` secret key factory used on Android.
  static Uint8List deriveKey(String password, Uint8List salt) {
    final PBKDF2KeyDerivator derivator = PBKDF2KeyDerivator(
      HMac(SHA256Digest(), 64),
    )..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLengthBytes));
    return derivator.process(Uint8List.fromList(_utf8Bytes(password)));
  }

  static Uint8List randomBytes(int length) {
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static Uint8List _crypt({
    required bool forEncryption,
    required Uint8List data,
    required Uint8List key,
    required Uint8List iv,
  }) {
    final GCMBlockCipher cipher = GCMBlockCipher(AESEngine())
      ..init(
        forEncryption,
        AEADParameters(KeyParameter(key), _tagLengthBits, iv, Uint8List(0)),
      );
    return cipher.process(data);
  }

  static List<int> _utf8Bytes(String value) => utf8.encode(value);
}
