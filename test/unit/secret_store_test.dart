import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/secrets/secret_store.dart';
import 'package:keel/providers/settings_provider.dart';

/// In-memory keyring that can be switched off to act locked/missing.
class FakeStore implements SecretStore {
  final Map<String, String> data = {};
  bool available = true;
  // Reports success but keeps nothing (a misbehaving keyring backend).
  bool dropsWrites = false;
  int writes = 0;

  @override
  Future<String?> read(String key) async => available ? data[key] : null;

  @override
  Future<bool> write(String key, String value) async {
    if (!available) return false;
    writes++;
    if (!dropsWrites) data[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    if (!available) return false;
    data.remove(key);
    return true;
  }
}

String slot(String f) => SettingsSecretVault.slot(f);

void main() {
  test('every API key field of AppSettings is treated as a secret', () {
    final json = const AppSettings(
      claudeApiKey: 'a',
      openAiApiKey: 'b',
      grokApiKey: 'c',
      githubToken: 'd',
      azureApiKey: 'e',
    ).toJson();
    for (final f in settingsSecretFields) {
      expect(json.containsKey(f), isTrue, reason: f);
    }
    // Any other field that looks like a key/token must be listed too.
    final suspicious = json.keys.where((k) =>
        RegExp(r'(ApiKey|Token|Secret|Password)$').hasMatch(k));
    expect(suspicious.toSet(), settingsSecretFields.toSet());
  });

  test('a plaintext key from an older Keel moves to the keyring and the '
      'file is rewritten without it', () async {
    final store = FakeStore();
    final vault = SettingsSecretVault(store);
    final (json, resave) = await vault.hydrate({
      'claudeApiKey': 'sk-ant-123',
      'claudeModel': 'claude-sonnet-5',
    });
    expect(json['claudeApiKey'], 'sk-ant-123');
    expect(resave, isTrue);
    expect(store.data[slot('claudeApiKey')], 'sk-ant-123');

    final file = await vault.persist(json);
    expect(file.containsKey('claudeApiKey'), isFalse);
    expect(file['claudeModel'], 'claude-sonnet-5');
  });

  test('keys load from the keyring when the file has none', () async {
    final store = FakeStore()..data[slot('openAiApiKey')] = 'sk-oa';
    final (json, resave) =
        await SettingsSecretVault(store).hydrate({'llmProvider': 'openAi'});
    expect(json['openAiApiKey'], 'sk-oa');
    expect(resave, isFalse);
    expect(AppSettings.fromJson(json).openAiApiKey, 'sk-oa');
  });

  test('a new or changed key goes to the keyring; clearing it deletes it',
      () async {
    final store = FakeStore();
    final vault = SettingsSecretVault(store);
    final (json, _) = await vault.hydrate({});

    var file = await vault.persist({...json, 'grokApiKey': 'xai-1'});
    expect(store.data[slot('grokApiKey')], 'xai-1');
    expect(file.containsKey('grokApiKey'), isFalse);

    file = await vault.persist({...json, 'grokApiKey': ''});
    expect(store.data.containsKey(slot('grokApiKey')), isFalse);
    expect(file.containsKey('grokApiKey'), isFalse);
  });

  test('unchanged keys are not rewritten on every settings save', () async {
    final store = FakeStore()..data[slot('claudeApiKey')] = 'k';
    final vault = SettingsSecretVault(store);
    final (json, _) = await vault.hydrate({});
    await vault.persist({...json, 'themeId': 'dusk'});
    await vault.persist({...json, 'uiScale': 1.2});
    expect(store.writes, 0);
  });

  test('no keyring: the key stays in the file rather than being lost',
      () async {
    final store = FakeStore()..available = false;
    final vault = SettingsSecretVault(store);
    final (json, resave) = await vault.hydrate({'claudeApiKey': 'k'});
    expect(json['claudeApiKey'], 'k');
    expect(resave, isFalse);
    expect((await vault.persist(json))['claudeApiKey'], 'k');
    // A new key typed while the keyring is down is kept in the file too…
    final file = await vault.persist({...json, 'azureApiKey': 'az'});
    expect(file['azureApiKey'], 'az');
    // …and moves to the keyring on the first save once it is back.
    store.available = true;
    final later = await vault.persist({...json, 'azureApiKey': 'az'});
    expect(later.containsKey('azureApiKey'), isFalse);
    expect(store.data[slot('azureApiKey')], 'az');
  });

  test('a keyring locked at launch never wipes the key it could not read',
      () async {
    final store = FakeStore()..data[slot('claudeApiKey')] = 'k';
    store.available = false;
    final vault = SettingsSecretVault(store);
    final (json, _) = await vault.hydrate({}); // key unreadable this run
    store.available = true; // unlocks later in the session
    await vault.persist({...json, 'themeId': 'dusk'});
    expect(store.data[slot('claudeApiKey')], 'k');
  });

  test('a keyring that says yes but keeps nothing does not get the key '
      'stripped from the file', () async {
    final store = FakeStore()..dropsWrites = true;
    final vault = SettingsSecretVault(store);
    final (json, resave) = await vault.hydrate({'claudeApiKey': 'k'});
    expect(resave, isFalse);
    expect((await vault.persist(json))['claudeApiKey'], 'k');
    final file = await vault.persist({...json, 'grokApiKey': 'g'});
    expect(file['grokApiKey'], 'g');
  });
}
