import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Conditional dart:io import — only used on non-web platforms.
import '_settings_io.dart' if (dart.library.html) '_settings_web.dart';

// Supported LLM providers
enum LLMProvider { claudeApi, openAi, grok, githubModels, azureOpenAi, ollama }

class AppSettings {
  final LLMProvider llmProvider;

  // Claude
  final String claudeApiKey;
  final String claudeModel;

  // OpenAI
  final String openAiApiKey;
  final String openAiModel;

  // Grok
  final String grokApiKey;
  final String grokModel;

  // GitHub Models
  final String githubToken;
  final String githubModel;

  // Azure OpenAI
  final String azureEndpoint;
  final String azureApiKey;
  final String azureModel;

  // Ollama
  final String ollamaBaseUrl;
  final String ollamaModel;

  // File watcher
  final bool watcherEnabled;
  final String watcherDirectory;

  // Sync
  final String syncServerUrl;
  final bool syncEnabled;
  final String syncEmail;

  const AppSettings({
    this.llmProvider = LLMProvider.claudeApi,
    this.claudeApiKey = '',
    this.claudeModel = 'claude-opus-4-5',
    this.openAiApiKey = '',
    this.openAiModel = 'gpt-4o',
    this.grokApiKey = '',
    this.grokModel = 'grok-3-latest',
    this.githubToken = '',
    this.githubModel = 'gpt-4o',
    this.azureEndpoint = '',
    this.azureApiKey = '',
    this.azureModel = 'gpt-4o',
    this.ollamaBaseUrl = 'http://localhost:11434',
    this.ollamaModel = 'llama3.2:3b',
    this.watcherEnabled = false,
    this.watcherDirectory = '',
    this.syncServerUrl = 'https://sync.keelapp.io',
    this.syncEnabled = false,
    this.syncEmail = '',
  });

  bool get hasApiKey {
    switch (llmProvider) {
      case LLMProvider.claudeApi:
        return claudeApiKey.isNotEmpty;
      case LLMProvider.openAi:
        return openAiApiKey.isNotEmpty;
      case LLMProvider.grok:
        return grokApiKey.isNotEmpty;
      case LLMProvider.githubModels:
        return githubToken.isNotEmpty;
      case LLMProvider.azureOpenAi:
        return azureApiKey.isNotEmpty && azureEndpoint.isNotEmpty;
      case LLMProvider.ollama:
        return true; // no key needed
    }
  }

  AppSettings copyWith({
    LLMProvider? llmProvider,
    String? claudeApiKey,
    String? claudeModel,
    String? openAiApiKey,
    String? openAiModel,
    String? grokApiKey,
    String? grokModel,
    String? githubToken,
    String? githubModel,
    String? azureEndpoint,
    String? azureApiKey,
    String? azureModel,
    String? ollamaBaseUrl,
    String? ollamaModel,
    bool? watcherEnabled,
    String? watcherDirectory,
    String? syncServerUrl,
    bool? syncEnabled,
    String? syncEmail,
  }) {
    return AppSettings(
      llmProvider: llmProvider ?? this.llmProvider,
      claudeApiKey: claudeApiKey ?? this.claudeApiKey,
      claudeModel: claudeModel ?? this.claudeModel,
      openAiApiKey: openAiApiKey ?? this.openAiApiKey,
      openAiModel: openAiModel ?? this.openAiModel,
      grokApiKey: grokApiKey ?? this.grokApiKey,
      grokModel: grokModel ?? this.grokModel,
      githubToken: githubToken ?? this.githubToken,
      githubModel: githubModel ?? this.githubModel,
      azureEndpoint: azureEndpoint ?? this.azureEndpoint,
      azureApiKey: azureApiKey ?? this.azureApiKey,
      azureModel: azureModel ?? this.azureModel,
      ollamaBaseUrl: ollamaBaseUrl ?? this.ollamaBaseUrl,
      ollamaModel: ollamaModel ?? this.ollamaModel,
      watcherEnabled: watcherEnabled ?? this.watcherEnabled,
      watcherDirectory: watcherDirectory ?? this.watcherDirectory,
      syncServerUrl: syncServerUrl ?? this.syncServerUrl,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncEmail: syncEmail ?? this.syncEmail,
    );
  }

  Map<String, dynamic> toJson() => {
        'llmProvider': llmProvider.name,
        'claudeApiKey': claudeApiKey,
        'claudeModel': claudeModel,
        'openAiApiKey': openAiApiKey,
        'openAiModel': openAiModel,
        'grokApiKey': grokApiKey,
        'grokModel': grokModel,
        'githubToken': githubToken,
        'githubModel': githubModel,
        'azureEndpoint': azureEndpoint,
        'azureApiKey': azureApiKey,
        'azureModel': azureModel,
        'ollamaBaseUrl': ollamaBaseUrl,
        'ollamaModel': ollamaModel,
        'watcherEnabled': watcherEnabled,
        'watcherDirectory': watcherDirectory,
        'syncServerUrl': syncServerUrl,
        'syncEnabled': syncEnabled,
        'syncEmail': syncEmail,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final providerStr = json['llmProvider'] as String? ?? 'claudeApi';
    final provider = LLMProvider.values.firstWhere(
      (e) => e.name == providerStr,
      orElse: () => LLMProvider.claudeApi,
    );
    return AppSettings(
      llmProvider: provider,
      claudeApiKey: json['claudeApiKey'] as String? ?? '',
      claudeModel: json['claudeModel'] as String? ?? 'claude-opus-4-5',
      openAiApiKey: json['openAiApiKey'] as String? ?? '',
      openAiModel: json['openAiModel'] as String? ?? 'gpt-4o',
      grokApiKey: json['grokApiKey'] as String? ?? '',
      grokModel: json['grokModel'] as String? ?? 'grok-3-latest',
      githubToken: json['githubToken'] as String? ?? '',
      githubModel: json['githubModel'] as String? ?? 'gpt-4o',
      azureEndpoint: json['azureEndpoint'] as String? ?? '',
      azureApiKey: json['azureApiKey'] as String? ?? '',
      azureModel: json['azureModel'] as String? ?? 'gpt-4o',
      ollamaBaseUrl:
          json['ollamaBaseUrl'] as String? ?? 'http://localhost:11434',
      ollamaModel: json['ollamaModel'] as String? ?? 'llama3.2:3b',
      watcherEnabled: json['watcherEnabled'] as bool? ?? false,
      watcherDirectory: json['watcherDirectory'] as String? ?? '',
      syncServerUrl:
          json['syncServerUrl'] as String? ?? 'https://sync.keelapp.io',
      syncEnabled: json['syncEnabled'] as bool? ?? false,
      syncEmail: json['syncEmail'] as String? ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Settings storage key (used by both IO and web backends)
// ---------------------------------------------------------------------------

const _kSettingsKey = 'keel_settings';

// ---------------------------------------------------------------------------
// SettingsProvider
// ---------------------------------------------------------------------------

class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  AppSettings get settings => _settings;
  bool get isLoaded => _loaded;
  bool get hasApiKey => _settings.hasApiKey;

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      if (kIsWeb) {
        // Web: use shared_preferences
        final prefs = await SharedPreferences.getInstance();
        final content = prefs.getString(_kSettingsKey);
        if (content != null) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          _settings = AppSettings.fromJson(json);
        }
      } else {
        // Native: use file I/O
        _settings = await loadSettingsFromFile();
      }
    } catch (e) {
      // Use defaults on error
      debugPrint('Failed to load settings: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(AppSettings newSettings) async {
    _settings = newSettings;
    notifyListeners();
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kSettingsKey, jsonEncode(newSettings.toJson()));
      } else {
        await saveSettingsToFile(newSettings.toJson());
      }
    } catch (e) {
      debugPrint('Failed to save settings: $e');
    }
  }

  Future<void> updateApiKey(String key) async {
    await save(_settings.copyWith(claudeApiKey: key));
  }

  Future<void> updateProvider(LLMProvider provider) async {
    await save(_settings.copyWith(llmProvider: provider));
  }

  Future<void> updateWatcher({bool? enabled, String? directory}) async {
    await save(_settings.copyWith(
      watcherEnabled: enabled,
      watcherDirectory: directory,
    ));
  }

  Future<void> updateSync({
    String? serverUrl,
    bool? enabled,
    String? email,
  }) async {
    await save(_settings.copyWith(
      syncServerUrl: serverUrl,
      syncEnabled: enabled,
      syncEmail: email,
    ));
  }
}
