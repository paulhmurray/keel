import 'package:flutter_test/flutter_test.dart';
import 'package:keel/providers/settings_provider.dart';

void main() {
  group('AppSettings — defaults', () {
    test('default provider is claudeApi', () {
      const s = AppSettings();
      expect(s.llmProvider, LLMProvider.claudeApi);
    });

    test('default API key is empty', () {
      const s = AppSettings();
      expect(s.claudeApiKey, '');
    });

    test('default model is set', () {
      const s = AppSettings();
      expect(s.claudeModel, isNotEmpty);
    });

    test('watcher disabled by default', () {
      const s = AppSettings();
      expect(s.watcherEnabled, isFalse);
      expect(s.watcherDirectory, '');
    });
  });

  group('AppSettings — copyWith', () {
    test('copyWith overrides only specified fields', () {
      const original = AppSettings(claudeApiKey: 'old-key');
      final updated = original.copyWith(claudeApiKey: 'new-key');
      expect(updated.claudeApiKey, 'new-key');
      expect(updated.llmProvider, original.llmProvider);
      expect(updated.claudeModel, original.claudeModel);
    });

    test('copyWith with no arguments returns equivalent settings', () {
      const s = AppSettings(claudeApiKey: 'key', watcherEnabled: true);
      final copy = s.copyWith();
      expect(copy.claudeApiKey, s.claudeApiKey);
      expect(copy.watcherEnabled, s.watcherEnabled);
    });
  });

  group('AppSettings — JSON serialisation roundtrip', () {
    test('toJson / fromJson roundtrip preserves all fields', () {
      const original = AppSettings(
        llmProvider: LLMProvider.claudeApi,
        claudeApiKey: 'sk-ant-test-key',
        claudeModel: 'claude-sonnet-4-6',
        watcherEnabled: true,
        watcherDirectory: '/home/user/inbox',
        ollamaBaseUrl: 'http://localhost:11434',
      );
      final json = original.toJson();
      final restored = AppSettings.fromJson(json);

      expect(restored.llmProvider, original.llmProvider);
      expect(restored.claudeApiKey, original.claudeApiKey);
      expect(restored.claudeModel, original.claudeModel);
      expect(restored.watcherEnabled, original.watcherEnabled);
      expect(restored.watcherDirectory, original.watcherDirectory);
      expect(restored.ollamaBaseUrl, original.ollamaBaseUrl);
    });

    test('fromJson with missing keys uses defaults', () {
      final s = AppSettings.fromJson({});
      expect(s.llmProvider, LLMProvider.claudeApi);
      expect(s.claudeApiKey, '');
      expect(s.watcherEnabled, isFalse);
    });

    test('fromJson with unknown provider string falls back to claudeApi', () {
      final s = AppSettings.fromJson({'llmProvider': 'unknown_provider'});
      expect(s.llmProvider, LLMProvider.claudeApi);
    });

    test('fromJson correctly restores ollama provider', () {
      final s = AppSettings.fromJson({'llmProvider': 'ollama'});
      expect(s.llmProvider, LLMProvider.ollama);
    });
  });

  group('AppSettings — hasApiKey check (via SettingsProvider logic)', () {
    test('non-empty key is considered set', () {
      const s = AppSettings(claudeApiKey: 'sk-ant-xxxx');
      expect(s.claudeApiKey.isNotEmpty, isTrue);
    });

    test('empty key is not considered set', () {
      const s = AppSettings(claudeApiKey: '');
      expect(s.claudeApiKey.isEmpty, isTrue);
    });
  });
}
