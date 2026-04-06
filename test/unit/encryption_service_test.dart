import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/sync/encryption_service.dart';

void main() {
  // Derive the key once and reuse — Argon2id is intentionally slow.
  late Object derivedKey;

  setUpAll(() async {
    derivedKey =
        await EncryptionService.deriveKey('hunter2', 'user-abc-12345678');
  });

  // ---------------------------------------------------------------------------
  // deriveKey
  // ---------------------------------------------------------------------------

  group('EncryptionService.deriveKey', () {
    test('same password and userId produce the same key bytes', () async {
      final k1 = await EncryptionService.deriveKey('password', 'user-00000000');
      final k2 = await EncryptionService.deriveKey('password', 'user-00000000');
      final b1 = await (k1).extractBytes();
      final b2 = await (k2).extractBytes();
      expect(b1, equals(b2));
    });

    test('different passwords produce different keys', () async {
      final k1 = await EncryptionService.deriveKey('passwordA', 'user-00000000');
      final k2 = await EncryptionService.deriveKey('passwordB', 'user-00000000');
      final b1 = await k1.extractBytes();
      final b2 = await k2.extractBytes();
      expect(b1, isNot(equals(b2)));
    });

    test('different userIds produce different keys', () async {
      final k1 = await EncryptionService.deriveKey('password', 'user-aaaaaaaa');
      final k2 = await EncryptionService.deriveKey('password', 'user-bbbbbbbb');
      final b1 = await k1.extractBytes();
      final b2 = await k2.extractBytes();
      expect(b1, isNot(equals(b2)));
    });

    test('derived key is 32 bytes (256 bits)', () async {
      final k = await EncryptionService.deriveKey('password', 'user-00000000');
      final bytes = await k.extractBytes();
      expect(bytes.length, 32);
    });
  });

  // ---------------------------------------------------------------------------
  // encrypt / decrypt roundtrip
  // ---------------------------------------------------------------------------

  group('EncryptionService encrypt/decrypt', () {
    test('encrypt then decrypt returns original plaintext', () async {
      const plaintext = 'Hello, world!';
      final encrypted = await EncryptionService.encrypt(derivedKey as dynamic, plaintext);
      final decrypted = await EncryptionService.decrypt(derivedKey as dynamic, encrypted);
      expect(decrypted, plaintext);
    });

    test('roundtrip with empty string', () async {
      const plaintext = '';
      final encrypted = await EncryptionService.encrypt(derivedKey as dynamic, plaintext);
      final decrypted = await EncryptionService.decrypt(derivedKey as dynamic, encrypted);
      expect(decrypted, plaintext);
    });

    test('roundtrip with Unicode content', () async {
      const plaintext = 'Programme: \u2014 résumé — café \u00e9';
      final encrypted = await EncryptionService.encrypt(derivedKey as dynamic, plaintext);
      final decrypted = await EncryptionService.decrypt(derivedKey as dynamic, encrypted);
      expect(decrypted, plaintext);
    });

    test('roundtrip with multi-line JSON-like content', () async {
      const plaintext = '{"project":{"id":"p1","name":"Alpha"},"risks":[]}';
      final encrypted = await EncryptionService.encrypt(derivedKey as dynamic, plaintext);
      final decrypted = await EncryptionService.decrypt(derivedKey as dynamic, encrypted);
      expect(decrypted, plaintext);
    });

    test('two encryptions of same plaintext produce different ciphertexts', () async {
      const plaintext = 'same message';
      final e1 = await EncryptionService.encrypt(derivedKey as dynamic, plaintext);
      final e2 = await EncryptionService.encrypt(derivedKey as dynamic, plaintext);
      // AES-GCM uses a random nonce, so the blobs must differ
      expect(e1, isNot(equals(e2)));
    });

    test('encrypted output is valid base64', () async {
      final encrypted =
          await EncryptionService.encrypt(derivedKey as dynamic, 'test');
      expect(() => base64.decode(encrypted), returnsNormally);
    });

    test('decrypt with wrong key throws', () async {
      final encrypted =
          await EncryptionService.encrypt(derivedKey as dynamic, 'secret data');
      final wrongKey =
          await EncryptionService.deriveKey('wrong-password', 'user-abc-12345678');
      expect(
        () => EncryptionService.decrypt(wrongKey, encrypted),
        throwsA(anything),
      );
    });

    test('decrypt with tampered ciphertext throws', () async {
      final encrypted =
          await EncryptionService.encrypt(derivedKey as dynamic, 'important data');
      // Flip a byte in the middle of the base64 blob
      final bytes = base64.decode(encrypted);
      bytes[bytes.length ~/ 2] ^= 0xFF;
      final tampered = base64.encode(bytes);
      expect(
        () => EncryptionService.decrypt(derivedKey as dynamic, tampered),
        throwsA(anything),
      );
    });

    test('decrypt with blob too short throws FormatException', () async {
      // 10 bytes < 12 (nonce) + 16 (mac) minimum
      final tooShort = base64.encode(List.filled(10, 0));
      expect(
        () => EncryptionService.decrypt(derivedKey as dynamic, tooShort),
        throwsFormatException,
      );
    });

    test('decrypt with invalid base64 throws', () async {
      expect(
        () => EncryptionService.decrypt(derivedKey as dynamic, 'not-valid-base64!!!'),
        throwsA(anything),
      );
    });
  });
}
