import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A place to keep secrets (API keys, tokens) off the plain settings
/// file. Every call is tolerant: a locked or missing keyring reads as
/// null and writes report false — never a throw.
abstract class SecretStore {
  Future<String?> read(String key);

  /// True when the value is safely stored.
  Future<bool> write(String key, String value);

  /// True when the key is gone (or never existed).
  Future<bool> delete(String key);
}

/// The OS keyring via flutter_secure_storage (libsecret on Linux,
/// Keychain on macOS, Credential Manager on Windows). Same store the sync
/// session uses.
class KeyringSecretStore implements SecretStore {
  const KeyringSecretStore();

  static const _storage = FlutterSecureStorage();
  static bool _warned = false;

  Future<T?> _guard<T>(Future<T> Function() op, String what) async {
    try {
      return await op();
    } catch (e) {
      if (!_warned) {
        _warned = true;
        debugPrint('Keel: keyring unavailable ($what): $e — API keys stay '
            'in the settings file until it is.');
      }
      return null;
    }
  }

  @override
  Future<String?> read(String key) =>
      _guard<String?>(() => _storage.read(key: key), 'read');

  @override
  Future<bool> write(String key, String value) async =>
      await _guard(() async {
        await _storage.write(key: key, value: value);
        return true;
      }, 'write') ??
      false;

  @override
  Future<bool> delete(String key) async =>
      await _guard(() async {
        await _storage.delete(key: key);
        return true;
      }, 'delete') ??
      false;
}

/// Keeps the secret fields of the settings JSON in a [SecretStore]
/// instead of the settings file.
///
/// [hydrate] runs on load: it fills secrets from the store, and migrates
/// any plaintext value still in the file into the store. [persist] runs on
/// save: it writes CHANGED secrets to the store and returns the JSON for
/// the file with every secret the store holds stripped out.
///
/// Losing a key is worse than leaving it on disk, so a secret the store
/// would not take stays in the file (as before), and an unchanged secret
/// never touches the store — a keyring that was locked at launch can't
/// cause a save to wipe the key it couldn't read.
class SettingsSecretVault {
  final SecretStore store;
  final List<String> fields;

  SettingsSecretVault(this.store, {this.fields = settingsSecretFields});

  /// Last value known to be persisted per field (keyring or file).
  final Map<String, String> _baseline = {};

  /// Fields whose current value lives in the store, not the file.
  final Set<String> _inStore = {};

  static String slot(String field) => 'keel_secret_$field';

  /// Returns the settings JSON with secrets filled in, and whether the
  /// file should be re-saved (a plaintext secret now lives in the store).
  Future<(Map<String, dynamic>, bool)> hydrate(
    Map<String, dynamic> fileJson,
  ) async {
    final json = Map<String, dynamic>.of(fileJson);
    var resave = false;
    for (final f in fields) {
      final plain = (json[f] as String?) ?? '';
      final stored = await store.read(slot(f));
      if (stored != null && stored.isNotEmpty) {
        json[f] = stored;
        _inStore.add(f);
        if (plain.isNotEmpty) resave = true; // strip the leftover copy
      } else if (plain.isNotEmpty) {
        if (await _storeVerified(f, plain)) {
          _inStore.add(f);
          resave = true;
        }
      }
      _baseline[f] = (json[f] as String?) ?? '';
    }
    return (json, resave);
  }

  /// Writes [value] and reads it back: removing a key from the file is
  /// the one step that can lose it, so only a confirmed copy counts.
  Future<bool> _storeVerified(String field, String value) async {
    if (!await store.write(slot(field), value)) return false;
    return await store.read(slot(field)) == value;
  }

  /// Stores changed secrets and returns the JSON to write to the file.
  Future<Map<String, dynamic>> persist(Map<String, dynamic> fullJson) async {
    final out = Map<String, dynamic>.of(fullJson);
    for (final f in fields) {
      final value = (out[f] as String?) ?? '';
      if (value != (_baseline[f] ?? '')) {
        final ok = value.isEmpty
            ? await store.delete(slot(f))
            : await _storeVerified(f, value);
        if (ok) {
          _baseline[f] = value;
          if (value.isEmpty) {
            _inStore.remove(f);
          } else {
            _inStore.add(f);
          }
        } else {
          // Store refused: keep it in the file; retry on the next save.
          _inStore.remove(f);
        }
      }
      if (value.isEmpty || _inStore.contains(f)) out.remove(f);
    }
    return out;
  }
}

/// The AppSettings JSON fields that are secrets.
const settingsSecretFields = [
  'claudeApiKey',
  'openAiApiKey',
  'grokApiKey',
  'githubToken',
  'azureApiKey',
];
