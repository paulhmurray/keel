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

  group('AppSettings — analytics fields', () {
    test('defaults: analytics opted out, no install ID', () {
      const s = AppSettings();
      expect(s.analyticsEnabled, isFalse);
      expect(s.analyticsInstallId, isNull);
    });

    test('copyWith can set analytics fields independently', () {
      const s = AppSettings();
      final updated =
          s.copyWith(analyticsEnabled: true, analyticsInstallId: 'inst-1');
      expect(updated.analyticsEnabled, isTrue);
      expect(updated.analyticsInstallId, 'inst-1');
      // Other fields untouched.
      expect(updated.claudeApiKey, s.claudeApiKey);
    });

    test('copyWith install-id sentinel: passing null actually clears it',
        () {
      const s = AppSettings(
          analyticsEnabled: true, analyticsInstallId: 'inst-1');
      // Omitting the field keeps it (sentinel != null).
      expect(s.copyWith().analyticsInstallId, 'inst-1');
      // Explicit null clears it.
      expect(s.copyWith(analyticsInstallId: null).analyticsInstallId,
          isNull);
    });

    test('JSON round-trip preserves opt-in + install ID', () {
      const original = AppSettings(
        analyticsEnabled: true,
        analyticsInstallId: 'inst-42',
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.analyticsEnabled, isTrue);
      expect(restored.analyticsInstallId, 'inst-42');
    });

    test('toJson omits install ID when it is null (no opted-in user)', () {
      const s = AppSettings();
      final json = s.toJson();
      expect(json.containsKey('analyticsInstallId'), isFalse);
      // But the opted-in flag is always serialised so its default flips
      // across versions are explicit.
      expect(json['analyticsEnabled'], isFalse);
    });

    test('fromJson with missing analytics keys uses defaults', () {
      final s = AppSettings.fromJson({});
      expect(s.analyticsEnabled, isFalse);
      expect(s.analyticsInstallId, isNull);
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
