import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// E2E encryption service using AES-256-GCM with Argon2id key derivation.
class EncryptionService {
  EncryptionService._();

  static final _aesGcm = AesGcm.with256bits();

  /// Derives a 32-byte AES-256 key from [password] and [userId].
  /// Uses Argon2id with m=65536 KiB, t=3 iterations, p=4 lanes.
  static Future<SecretKey> deriveKey(String password, String userId) async {
    final argon2id = Argon2id(
      memory: 65536, // 64 MiB
      iterations: 3,
      parallelism: 4,
      hashLength: 32,
    );

    // Use userId bytes as salt (fixed per user so the same password always
    // produces the same key — necessary for pull/decrypt on any device).
    final saltBytes = utf8.encode(userId.padRight(16, '0').substring(0, 16));

    final secretKey = await argon2id.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: saltBytes,
    );
    return secretKey;
  }

  /// Encrypts [plaintext] with AES-256-GCM.
  /// Returns base64(nonce + ciphertext + mac).
  static Future<String> encrypt(SecretKey key, String plaintext) async {
    final plaintextBytes = utf8.encode(plaintext);

    final secretBox = await _aesGcm.encrypt(
      plaintextBytes,
      secretKey: key,
    );

    // Layout: [12-byte nonce][ciphertext][16-byte mac]
    final combined = Uint8List(
        secretBox.nonce.length +
            secretBox.cipherText.length +
            secretBox.mac.bytes.length);
    var offset = 0;
    for (final b in secretBox.nonce) {
      combined[offset++] = b;
    }
    for (final b in secretBox.cipherText) {
      combined[offset++] = b;
    }
    for (final b in secretBox.mac.bytes) {
      combined[offset++] = b;
    }

    return base64.encode(combined);
  }

  /// Decrypts a base64-encoded blob produced by [encrypt].
  /// Returns the original plaintext string.
  static Future<String> decrypt(SecretKey key, String base64Blob) async {
    final combined = base64.decode(base64Blob);

    // AES-GCM nonce is 12 bytes, MAC is 16 bytes
    const nonceLength = 12;
    const macLength = 16;

    if (combined.length < nonceLength + macLength) {
      throw const FormatException('Encrypted blob is too short');
    }

    final nonce = combined.sublist(0, nonceLength);
    final mac = combined.sublist(combined.length - macLength);
    final cipherText =
        combined.sublist(nonceLength, combined.length - macLength);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(mac),
    );

    final decryptedBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: key,
    );

    return utf8.decode(decryptedBytes);
  }
}
