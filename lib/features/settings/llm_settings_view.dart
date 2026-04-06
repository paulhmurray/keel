import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/llm/ollama_client.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import 'ollama_wizard.dart';

// ---------------------------------------------------------------------------
// Ollama connection status enum
// ---------------------------------------------------------------------------

enum _OllamaStatus { unknown, checking, connected, failed }

// ---------------------------------------------------------------------------
// LLMSettingsView
// ---------------------------------------------------------------------------

class LLMSettingsView extends StatefulWidget {
  const LLMSettingsView({super.key});

  @override
  State<LLMSettingsView> createState() => _LLMSettingsViewState();
}

class _LLMSettingsViewState extends State<LLMSettingsView> {
  // Provider selection
  LLMProvider _provider = LLMProvider.claudeApi;

  // Claude
  late TextEditingController _claudeKeyCtrl;
  bool _obscureClaudeKey = true;
  late String _claudeModel;

  // OpenAI
  late TextEditingController _openAiKeyCtrl;
  bool _obscureOpenAiKey = true;
  late String _openAiModel;

  // Grok
  late TextEditingController _grokKeyCtrl;
  bool _obscureGrokKey = true;
  late String _grokModel;

  // GitHub Models
  late TextEditingController _githubTokenCtrl;
  bool _obscureGithubToken = true;
  late String _githubModel;

  // Azure OpenAI
  late TextEditingController _azureEndpointCtrl;
  late TextEditingController _azureKeyCtrl;
  bool _obscureAzureKey = true;
  late TextEditingController _azureModelCtrl;

  // Ollama
  late TextEditingController _ollamaBaseUrlCtrl;
  late String _ollamaModel;
  _OllamaStatus _ollamaStatus = _OllamaStatus.unknown;
  List<String> _ollamaModels = [];

  // Watcher
  late bool _watcherEnabled;
  late TextEditingController _watcherDirCtrl;

  bool _dirty = false;

  static const _claudeModels = [
    'claude-opus-4-6',
    'claude-sonnet-4-6',
    'claude-haiku-4-5-20251001',
  ];

  static const _openAiModels = [
    'gpt-4o',
    'gpt-4o-mini',
    'gpt-4-turbo',
    'o1',
    'o1-mini',
  ];

  static const _grokModels = [
    'grok-3-latest',
    'grok-3-mini-latest',
    'grok-2-latest',
  ];

  static const _githubModels = [
    'gpt-4o',
    'gpt-4o-mini',
    'Llama-3.3-70B-Instruct',
    'Mistral-large-2407',
    'Phi-4',
  ];

  static const _ollamaRecommended = [
    ('llama3.2:3b', 'Fast, 2 GB, great for most tasks'),
    ('phi4-mini', 'Microsoft, very efficient, 2.5 GB'),
    ('gemma3:4b', 'Google, strong reasoning, 3 GB'),
    ('mistral:7b', 'Balanced quality, 4 GB'),
    ('llama3.1:8b', 'Most capable free model, 5 GB'),
  ];

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>().settings;

    _provider = s.llmProvider;

    _claudeKeyCtrl = TextEditingController(text: s.claudeApiKey);
    _claudeModel = _claudeModels.contains(s.claudeModel)
        ? s.claudeModel
        : _claudeModels.first;

    _openAiKeyCtrl = TextEditingController(text: s.openAiApiKey);
    _openAiModel =
        _openAiModels.contains(s.openAiModel) ? s.openAiModel : _openAiModels.first;

    _grokKeyCtrl = TextEditingController(text: s.grokApiKey);
    _grokModel =
        _grokModels.contains(s.grokModel) ? s.grokModel : _grokModels.first;

    _githubTokenCtrl = TextEditingController(text: s.githubToken);
    _githubModel = _githubModels.contains(s.githubModel)
        ? s.githubModel
        : _githubModels.first;

    _azureEndpointCtrl = TextEditingController(text: s.azureEndpoint);
    _azureKeyCtrl = TextEditingController(text: s.azureApiKey);
    _azureModelCtrl = TextEditingController(text: s.azureModel);

    _ollamaBaseUrlCtrl = TextEditingController(text: s.ollamaBaseUrl);
    _ollamaModel = s.ollamaModel;

    _watcherEnabled = s.watcherEnabled;
    _watcherDirCtrl = TextEditingController(text: s.watcherDirectory);

    // Mark dirty on any text change
    for (final ctrl in [
      _claudeKeyCtrl,
      _openAiKeyCtrl,
      _grokKeyCtrl,
      _githubTokenCtrl,
      _azureEndpointCtrl,
      _azureKeyCtrl,
      _azureModelCtrl,
      _ollamaBaseUrlCtrl,
      _watcherDirCtrl,
    ]) {
      ctrl.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    _claudeKeyCtrl.dispose();
    _openAiKeyCtrl.dispose();
    _grokKeyCtrl.dispose();
    _githubTokenCtrl.dispose();
    _azureEndpointCtrl.dispose();
    _azureKeyCtrl.dispose();
    _azureModelCtrl.dispose();
    _ollamaBaseUrlCtrl.dispose();
    _watcherDirCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settingsProvider = context.read<SettingsProvider>();
    await settingsProvider.save(
      settingsProvider.settings.copyWith(
        llmProvider: _provider,
        claudeApiKey: _claudeKeyCtrl.text.trim(),
        claudeModel: _claudeModel,
        openAiApiKey: _openAiKeyCtrl.text.trim(),
        openAiModel: _openAiModel,
        grokApiKey: _grokKeyCtrl.text.trim(),
        grokModel: _grokModel,
        githubToken: _githubTokenCtrl.text.trim(),
        githubModel: _githubModel,
        azureEndpoint: _azureEndpointCtrl.text.trim(),
        azureApiKey: _azureKeyCtrl.text.trim(),
        azureModel: _azureModelCtrl.text.trim(),
        ollamaBaseUrl: _ollamaBaseUrlCtrl.text.trim(),
        ollamaModel: _ollamaModel,
        watcherEnabled: _watcherEnabled,
        watcherDirectory: _watcherDirCtrl.text.trim(),
      ),
    );
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  Future<void> _checkOllamaConnection() async {
    setState(() => _ollamaStatus = _OllamaStatus.checking);
    final url = _ollamaBaseUrlCtrl.text.trim();
    final running = await OllamaClient.isRunning(url);
    if (!mounted) return;
    if (running) {
      final models = await OllamaClient.getAvailableModels(url);
      if (!mounted) return;
      setState(() {
        _ollamaStatus = _OllamaStatus.connected;
        _ollamaModels = models;
        // If the current model is not in the list, pick the first available
        if (_ollamaModels.isNotEmpty && !_ollamaModels.contains(_ollamaModel)) {
          _ollamaModel = _ollamaModels.first;
          _dirty = true;
        }
      });
    } else {
      setState(() {
        _ollamaStatus = _OllamaStatus.failed;
        _ollamaModels = [];
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Provider display helpers
  // ---------------------------------------------------------------------------

  String _providerLabel(LLMProvider p) {
    switch (p) {
      case LLMProvider.claudeApi:
        return 'Claude (Anthropic)';
      case LLMProvider.openAi:
        return 'ChatGPT (OpenAI)';
      case LLMProvider.grok:
        return 'Grok (xAI)';
      case LLMProvider.githubModels:
        return 'GitHub Models';
      case LLMProvider.azureOpenAi:
        return 'Azure OpenAI (Microsoft)';
      case LLMProvider.ollama:
        return 'Ollama (Local / Free)';
    }
  }

  IconData _providerIcon(LLMProvider p) {
    switch (p) {
      case LLMProvider.claudeApi:
        return Icons.auto_awesome;
      case LLMProvider.openAi:
        return Icons.chat_outlined;
      case LLMProvider.grok:
        return Icons.bolt_outlined;
      case LLMProvider.githubModels:
        return Icons.code;
      case LLMProvider.azureOpenAi:
        return Icons.cloud_outlined;
      case LLMProvider.ollama:
        return Icons.computer_outlined;
    }
  }

  // ---------------------------------------------------------------------------
  // Provider-specific settings cards
  // ---------------------------------------------------------------------------

  Widget _buildProviderCard() {
    switch (_provider) {
      case LLMProvider.claudeApi:
        return _buildClaudeCard();
      case LLMProvider.openAi:
        return _buildOpenAiCard();
      case LLMProvider.grok:
        return _buildGrokCard();
      case LLMProvider.githubModels:
        return _buildGithubModelsCard();
      case LLMProvider.azureOpenAi:
        return _buildAzureCard();
      case LLMProvider.ollama:
        return _buildOllamaCard();
    }
  }

  Widget _buildClaudeCard() {
    return _SettingsCard(
      title: 'Claude Settings',
      children: [
        _ApiKeyField(
          controller: _claudeKeyCtrl,
          label: 'Anthropic API Key',
          hint: 'sk-ant-…',
          obscure: _obscureClaudeKey,
          onToggleObscure: () =>
              setState(() => _obscureClaudeKey = !_obscureClaudeKey),
        ),
        const SizedBox(height: 8),
        const Text(
          'Get your API key at console.anthropic.com',
          style: TextStyle(color: KColors.textDim, fontSize: 11),
        ),
        const SizedBox(height: 16),
        _ModelDropdown(
          label: 'Claude model',
          value: _claudeModel,
          models: _claudeModels,
          onChanged: (v) => setState(() {
            _claudeModel = v!;
            _dirty = true;
          }),
        ),
      ],
    );
  }

  Widget _buildOpenAiCard() {
    return _SettingsCard(
      title: 'OpenAI Settings',
      children: [
        _ApiKeyField(
          controller: _openAiKeyCtrl,
          label: 'OpenAI API Key',
          hint: 'sk-…',
          obscure: _obscureOpenAiKey,
          onToggleObscure: () =>
              setState(() => _obscureOpenAiKey = !_obscureOpenAiKey),
        ),
        const SizedBox(height: 16),
        _ModelDropdown(
          label: 'OpenAI model',
          value: _openAiModel,
          models: _openAiModels,
          onChanged: (v) => setState(() {
            _openAiModel = v!;
            _dirty = true;
          }),
        ),
      ],
    );
  }

  Widget _buildGrokCard() {
    return _SettingsCard(
      title: 'Grok Settings',
      children: [
        _ApiKeyField(
          controller: _grokKeyCtrl,
          label: 'xAI API Key',
          hint: 'xai-…',
          obscure: _obscureGrokKey,
          onToggleObscure: () =>
              setState(() => _obscureGrokKey = !_obscureGrokKey),
        ),
        const SizedBox(height: 16),
        _ModelDropdown(
          label: 'Grok model',
          value: _grokModel,
          models: _grokModels,
          onChanged: (v) => setState(() {
            _grokModel = v!;
            _dirty = true;
          }),
        ),
      ],
    );
  }

  Widget _buildGithubModelsCard() {
    return _SettingsCard(
      title: 'GitHub Models Settings',
      children: [
        _ApiKeyField(
          controller: _githubTokenCtrl,
          label: 'GitHub Personal Access Token',
          hint: 'ghp_…',
          obscure: _obscureGithubToken,
          onToggleObscure: () =>
              setState(() => _obscureGithubToken = !_obscureGithubToken),
        ),
        const SizedBox(height: 8),
        const Text(
          'Generate at github.com/settings/tokens',
          style: TextStyle(color: KColors.textDim, fontSize: 11),
        ),
        const SizedBox(height: 16),
        _ModelDropdown(
          label: 'GitHub model',
          value: _githubModel,
          models: _githubModels,
          onChanged: (v) => setState(() {
            _githubModel = v!;
            _dirty = true;
          }),
        ),
      ],
    );
  }

  Widget _buildAzureCard() {
    return _SettingsCard(
      title: 'Azure OpenAI Settings',
      children: [
        TextField(
          controller: _azureEndpointCtrl,
          decoration: const InputDecoration(
            labelText: 'Endpoint URL',
            hintText: 'https://your-resource.openai.azure.com',
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        _ApiKeyField(
          controller: _azureKeyCtrl,
          label: 'Azure API Key',
          hint: 'your-azure-api-key',
          obscure: _obscureAzureKey,
          onToggleObscure: () =>
              setState(() => _obscureAzureKey = !_obscureAzureKey),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _azureModelCtrl,
          decoration: const InputDecoration(
            labelText: 'Deployment / Model name',
            hintText: 'e.g. gpt-4o',
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildOllamaCard() {
    final isConnected = _ollamaStatus == _OllamaStatus.connected;
    final isChecking = _ollamaStatus == _OllamaStatus.checking;

    return _SettingsCard(
      title: 'Ollama Settings',
      children: [
        // Base URL + check button
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ollamaBaseUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'http://localhost:11434',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            isChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : OutlinedButton(
                    onPressed: _checkOllamaConnection,
                    child: const Text('Check connection'),
                  ),
          ],
        ),
        const SizedBox(height: 8),
        // Connection status indicator
        if (_ollamaStatus == _OllamaStatus.connected)
          const Row(
            children: [
              Icon(Icons.check_circle_outline, size: 14, color: KColors.phosphor),
              SizedBox(width: 6),
              Text('Connected',
                  style: TextStyle(color: KColors.phosphor, fontSize: 12)),
            ],
          )
        else if (_ollamaStatus == _OllamaStatus.failed)
          const Row(
            children: [
              Icon(Icons.error_outline, size: 14, color: KColors.red),
              SizedBox(width: 6),
              Text('Not reachable',
                  style: TextStyle(color: KColors.red, fontSize: 12)),
            ],
          ),
        const SizedBox(height: 16),
        // Model selector
        isConnected && _ollamaModels.isNotEmpty
            ? _ModelDropdown(
                label: 'Ollama model',
                value: _ollamaModels.contains(_ollamaModel)
                    ? _ollamaModel
                    : _ollamaModels.first,
                models: _ollamaModels,
                onChanged: (v) => setState(() {
                  _ollamaModel = v!;
                  _dirty = true;
                }),
              )
            : DropdownButtonFormField<String>(
                value: null,
                decoration: const InputDecoration(
                  labelText: 'Ollama model',
                  hintText: 'Connect to Ollama first',
                  isDense: true,
                ),
                items: const [],
                onChanged: null,
              ),
        const SizedBox(height: 20),
        // Setup wizard button
        OutlinedButton.icon(
          onPressed: () => showOllamaWizard(context),
          icon: const Icon(Icons.auto_fix_high_outlined, size: 14),
          label: const Text('Run setup wizard'),
          style: OutlinedButton.styleFrom(
            foregroundColor: KColors.amber,
            side: const BorderSide(color: KColors.amber, width: 0.5),
          ),
        ),
        const SizedBox(height: 20),
        // Recommended models section
        const Text(
          'Recommended free models',
          style: TextStyle(
            color: KColors.amber,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        for (final (name, desc) in _ollamaRecommended)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: KColors.text,
                        ),
                      ),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 11,
                          color: KColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                OllamaModelPullButton(
                  modelId: name,
                  baseUrl: _ollamaBaseUrlCtrl.text.trim().isEmpty
                      ? 'http://localhost:11434'
                      : _ollamaBaseUrlCtrl.text.trim(),
                  onComplete: _checkOllamaConnection,
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Don\'t have Ollama? Use the setup wizard above.',
          style: TextStyle(color: KColors.textDim, fontSize: 11),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM Settings'),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Provider selector card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LLM Provider',
                      style: TextStyle(
                        color: KColors.amber,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<LLMProvider>(
                      value: _provider,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Provider',
                      ),
                      items: LLMProvider.values
                          // Hide Ollama on web — it requires local process access
                          .where((p) => !kIsWeb || p != LLMProvider.ollama)
                          .map((p) {
                        return DropdownMenuItem(
                          value: p,
                          child: Row(
                            children: [
                              Icon(_providerIcon(p), size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _providerLabel(p),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() {
                        _provider = v!;
                        _dirty = true;
                      }),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Provider-specific settings
            _buildProviderCard(),

            if (!kIsWeb) ...[
              const SizedBox(height: 16),

              // File watcher section — not available on web
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'File Watcher',
                        style: TextStyle(
                          color: KColors.amber,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: _watcherEnabled,
                        onChanged: (v) => setState(() {
                          _watcherEnabled = v;
                          _dirty = true;
                        }),
                        title: const Text('Enable file watcher',
                            style: TextStyle(fontSize: 13)),
                        contentPadding: EdgeInsets.zero,
                        activeColor: KColors.amber,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _watcherDirCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Watch directory',
                          hintText: '/path/to/directory',
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            Row(
              children: [
                ElevatedButton(
                  onPressed: _dirty ? _save : null,
                  child: const Text('Save Settings'),
                ),
                const SizedBox(width: 12),
                if (_dirty)
                  const Text(
                    'Unsaved changes',
                    style: TextStyle(
                      color: KColors.amber,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helper widgets
// ---------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: KColors.amber,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ApiKeyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final VoidCallback onToggleObscure;

  const _ApiKeyField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.obscure,
    required this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 18,
          ),
          onPressed: onToggleObscure,
        ),
      ),
    );
  }
}

class _ModelDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> models;
  final ValueChanged<String?> onChanged;

  const _ModelDropdown({
    required this.label,
    required this.value,
    required this.models,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: models.contains(value) ? value : models.first,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
      ),
      items: models
          .map((m) => DropdownMenuItem(
                value: m,
                child: Text(m, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
