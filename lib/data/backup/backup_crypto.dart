import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'data_export.dart';

/// Password protection for backup files: AES-256-GCM with a key derived by
/// PBKDF2-HMAC-SHA256. There is no recovery if the password is lost.
abstract final class BackupCrypto {
  static const format = 'pennywise-encrypted-backup';
  static const version = 1;
  static const defaultIterations = 600000;
  static const minPasswordLength = 8;

  // Bounds what a tampered file can make the phone compute.
  static const _minIterations = 1000;
  static const _maxIterations = 5000000;

  static bool isEncrypted(String text) {
    try {
      final v = jsonDecode(text);
      return v is Map && v['format'] == format;
    } on FormatException {
      return false;
    }
  }

  /// Runs in the background: key derivation takes seconds on a phone.
  static Future<String> encrypt(String plain, String password, {int iterations = defaultIterations}) =>
      Isolate.run(() => _encrypt(plain, password, iterations));

  /// Throws [BackupFormatException] for a wrong password or a damaged file.
  static Future<String> decrypt(String envelope, String password) => Isolate.run(() => _decrypt(envelope, password));

  static String _encrypt(String plain, String password, int iterations) {
    final random = Random.secure();
    Uint8List bytes(int n) => Uint8List.fromList(List.generate(n, (_) => random.nextInt(256)));
    final salt = bytes(16);
    final nonce = bytes(12);
    final cipher = _cipher(true, _key(password, salt, iterations), nonce, _aad(iterations, salt));
    return jsonEncode({
      'format': format,
      'version': version,
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'data': base64Encode(cipher.process(utf8.encode(plain))),
    });
  }

  static String _decrypt(String envelope, String password) {
    const damaged = BackupFormatException('This encrypted backup is damaged.');
    final Uint8List salt, nonce, data;
    final int iterations;
    try {
      final v = (jsonDecode(envelope) as Map).cast<String, Object?>();
      if (v['version'] != version) {
        throw const BackupFormatException('This backup was made by a newer version of PennyWise. Update the app first.');
      }
      iterations = v['iterations']! as int;
      salt = base64Decode(v['salt']! as String);
      nonce = base64Decode(v['nonce']! as String);
      data = base64Decode(v['data']! as String);
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      throw damaged;
    }
    if (iterations < _minIterations || iterations > _maxIterations || nonce.length != 12) throw damaged;
    try {
      final cipher = _cipher(false, _key(password, salt, iterations), nonce, _aad(iterations, salt));
      return utf8.decode(cipher.process(data));
    } on InvalidCipherTextException {
      throw const BackupFormatException('Wrong password, or the backup is damaged.');
    }
  }

  static Uint8List _key(String password, Uint8List salt, int iterations) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
    return kdf.process(utf8.encode(password));
  }

  /// Authenticates the key settings along with the data.
  static Uint8List _aad(int iterations, Uint8List salt) => utf8.encode('$format|$version|$iterations|${base64Encode(salt)}');

  static GCMBlockCipher _cipher(bool encrypting, Uint8List key, Uint8List nonce, Uint8List aad) =>
      GCMBlockCipher(AESEngine())..init(encrypting, AEADParameters(KeyParameter(key), 128, nonce, aad));
}
