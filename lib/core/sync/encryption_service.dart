import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// E2E encryption service using AES-256-GCM with Argon2id key derivation.
class EncryptionService {
  EncryptionService._();

  static final _aesGcm = AesGcm.with256bits();

  // ── Cascade / link-channel keys ────────────────────────────────────────
  //
  // The programme cascade is encrypted per-link with a random 256-bit
  // secret shared party-to-party (never sent to the server), so the
  // server stores only ciphertext — E2E, matching the project blob. The
  // secret has full entropy, so it IS the AES-256 key directly; no KDF is
  // needed (a slow KDF only buys entropy stretching for weak passwords).

  /// A fresh URL-safe 256-bit link secret to share alongside the routing
  /// code. base64url so it survives copy/paste and never contains '#'.
  static String generateLinkSecret() {
    final rnd = Random.secure();
    final bytes =
        Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
    return base64Url.encode(bytes);
  }

  /// Turns a shared link secret back into the AES-256 key. Returns null
  /// when the secret is missing/malformed (caller then declines to
  /// encrypt/decrypt rather than fall back to plaintext).
  static SecretKey? keyFromLinkSecret(String? secret) {
    if (secret == null || secret.isEmpty) return null;
    try {
      final bytes = base64Url.decode(base64Url.normalize(secret));
      if (bytes.length != 32) return null;
      return SecretKey(bytes);
    } catch (_) {
      return null;
    }
  }

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
