import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/export/csv_exporter.dart';
import '../../core/export/json_exporter.dart';
import '../../core/import/json_importer.dart';
import '../../core/inbox/watcher_service.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/keybindings_table.dart';
import 'llm_settings_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.settings, color: KColors.amber, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text('Settings',
                    style: theme.textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Profile section
          _ProfileSection(),

          const SizedBox(height: 16),

          // LLM Settings section
          _SettingsSection(
            title: 'LLM / AI Settings',
            icon: Icons.auto_awesome_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsRow(
                  label: 'Provider',
                  value: _llmProviderLabel(settings.settings.llmProvider),
                ),
                ..._llmStatusRows(settings.settings),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LLMSettingsView(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Configure LLM Settings'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          const SizedBox(height: 16),

          // Display section — not available on web
          if (!kIsWeb) _DisplaySection(),

          // File Watcher section — not available on web
          if (!kIsWeb) _WatcherSection(),

          if (!kIsWeb) const SizedBox(height: 16),
          _SyncSection(),

          const SizedBox(height: 16),
          _DataSection(),

          const SizedBox(height: 16),
          _EditorSection(),

          const SizedBox(height: 16),
          if (!kIsWeb)
            _SettingsSection(
              title: 'Keyboard Shortcuts',
              icon: Icons.keyboard_outlined,
              child: const KeybindingsTable(),
            ),

          const SizedBox(height: 16),
          _SettingsSection(
            title: 'About',
            icon: Icons.info_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsRow(label: 'App', value: 'Keel'),
                const SizedBox(height: 4),
                _SettingsRow(label: 'Version', value: '1.0.0'),
                const SizedBox(height: 4),
                _SettingsRow(
                    label: 'Description',
                    value: 'Local-first TPM command centre.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: KColors.amber),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KColors.amber)),
              ],
            ),
            const Divider(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Display Section
// ---------------------------------------------------------------------------

class _DisplaySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final scale = settingsProvider.settings.uiScale;

    return _SettingsSection(
      title: 'Display',
      icon: Icons.display_settings_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adjust the UI scale if the app appears too large or small on your display. Default is 1.0.',
            style: TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('UI Scale',
                  style: TextStyle(color: KColors.text, fontSize: 13)),
              const SizedBox(width: 16),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: KColors.amber,
                    inactiveTrackColor: KColors.border2,
                    thumbColor: KColors.amber,
                    overlayColor: KColors.amber.withValues(alpha: 0.12),
                    trackHeight: 2,
                  ),
                  child: Slider(
                    value: scale,
                    min: 0.7,
                    max: 1.3,
                    divisions: 12,
                    onChanged: (v) {
                      final rounded = (v * 20).round() / 20;
                      settingsProvider
                          .save(settingsProvider.settings.copyWith(uiScale: rounded));
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 36,
                child: Text(
                  scale.toStringAsFixed(2),
                  style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: scale == 1.0
                    ? null
                    : () => settingsProvider
                        .save(settingsProvider.settings.copyWith(uiScale: 1.0)),
                child: const Text('Reset', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile Section
// ---------------------------------------------------------------------------

class _ProfileSection extends StatefulWidget {
  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<_ProfileSection> {
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>().settings;
    _nameCtrl = TextEditingController(text: settings.myName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return _SettingsSection(
      title: 'Your Profile',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Set your name so you can quickly assign tasks to yourself and be identified in People lists.',
            style: TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: KColors.text, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: 'e.g. Paul Murray',
                  ),
                  onSubmitted: (_) => _save(context),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _save(context),
                child: const Text('Save'),
              ),
            ],
          ),
          if (settings.settings.myName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: KColors.phosphor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Showing as "Me — ${settings.settings.myName}" in owner dropdowns',
                  style: const TextStyle(
                      color: KColors.phosphor, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final provider = context.read<SettingsProvider>();
    await provider.save(
        provider.settings.copyWith(myName: _nameCtrl.text.trim()));
  }
}

// ---------------------------------------------------------------------------

class _WatcherSection extends StatefulWidget {
  @override
  State<_WatcherSection> createState() => _WatcherSectionState();
}

class _WatcherSectionState extends State<_WatcherSection> {
  late TextEditingController _dirCtrl;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>().settings;
    _dirCtrl = TextEditingController(text: settings.watcherDirectory);
  }

  @override
  void dispose() {
    _dirCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final watcher = context.watch<WatcherService>();
    final enabled = settings.settings.watcherEnabled;

    return _SettingsSection(
      title: 'File Watcher',
      icon: Icons.folder_open_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Automatically parse .org, .md, and .txt files dropped into a folder '
            'and add them to the Inbox.',
            style: const TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dirCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Watch folder path',
                    hintText: '/Users/you/keel-inbox',
                  ),
                  onSubmitted: (v) => settings.updateWatcher(directory: v.trim()),
                  onChanged: (v) {
                    // Save on blur — handled by onEditingComplete via unfocus
                  },
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () =>
                    settings.updateWatcher(directory: _dirCtrl.text.trim()),
                child: const Text('Set'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Switch(
                value: enabled,
                onChanged: (v) => settings.updateWatcher(enabled: v),
                activeColor: KColors.amber,
              ),
              const SizedBox(width: 8),
              Text(
                enabled ? 'Enabled' : 'Disabled',
                style: TextStyle(
                  color: enabled
                      ? KColors.phosphor
                      : KColors.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                watcher.isActive
                    ? Icons.fiber_manual_record
                    : Icons.fiber_manual_record_outlined,
                size: 12,
                color: watcher.isActive
                    ? KColors.phosphor
                    : KColors.textDim,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  watcher.statusMessage,
                  style: TextStyle(
                    color: watcher.isActive
                        ? KColors.phosphor
                        : KColors.textDim,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _llmProviderLabel(LLMProvider p) {
  switch (p) {
    case LLMProvider.claudeApi:    return 'Claude (Anthropic)';
    case LLMProvider.openAi:       return 'ChatGPT (OpenAI)';
    case LLMProvider.grok:         return 'Grok (xAI)';
    case LLMProvider.githubModels: return 'GitHub Models';
    case LLMProvider.azureOpenAi:  return 'Azure OpenAI';
    case LLMProvider.ollama:       return 'Ollama (Local / Free)';
  }
}

List<Widget> _llmStatusRows(AppSettings s) {
  switch (s.llmProvider) {
    case LLMProvider.claudeApi:
      final hasKey = s.claudeApiKey.isNotEmpty;
      return [
        const SizedBox(height: 4),
        _SettingsRow(
          label: 'API Key',
          value: hasKey ? '••••••••••••••••' : 'Not set',
          valueColor: hasKey ? KColors.phosphor : KColors.amber,
        ),
        const SizedBox(height: 4),
        _SettingsRow(label: 'Model', value: s.claudeModel),
      ];
    case LLMProvider.openAi:
      final hasKey = s.openAiApiKey.isNotEmpty;
      return [
        const SizedBox(height: 4),
        _SettingsRow(
          label: 'API Key',
          value: hasKey ? '••••••••••••••••' : 'Not set',
          valueColor: hasKey ? KColors.phosphor : KColors.amber,
        ),
        const SizedBox(height: 4),
        _SettingsRow(label: 'Model', value: s.openAiModel),
      ];
    case LLMProvider.grok:
      final hasKey = s.grokApiKey.isNotEmpty;
      return [
        const SizedBox(height: 4),
        _SettingsRow(
          label: 'API Key',
          value: hasKey ? '••••••••••••••••' : 'Not set',
          valueColor: hasKey ? KColors.phosphor : KColors.amber,
        ),
        const SizedBox(height: 4),
        _SettingsRow(label: 'Model', value: s.grokModel),
      ];
    case LLMProvider.githubModels:
      final hasToken = s.githubToken.isNotEmpty;
      return [
        const SizedBox(height: 4),
        _SettingsRow(
          label: 'Token',
          value: hasToken ? '••••••••••••••••' : 'Not set',
          valueColor: hasToken ? KColors.phosphor : KColors.amber,
        ),
        const SizedBox(height: 4),
        _SettingsRow(label: 'Model', value: s.githubModel),
      ];
    case LLMProvider.azureOpenAi:
      final hasKey = s.azureApiKey.isNotEmpty;
      return [
        const SizedBox(height: 4),
        _SettingsRow(
          label: 'Endpoint',
          value: s.azureEndpoint.isNotEmpty ? s.azureEndpoint : 'Not set',
          valueColor: s.azureEndpoint.isNotEmpty ? null : KColors.amber,
        ),
        const SizedBox(height: 4),
        _SettingsRow(
          label: 'API Key',
          value: hasKey ? '••••••••••••••••' : 'Not set',
          valueColor: hasKey ? KColors.phosphor : KColors.amber,
        ),
        const SizedBox(height: 4),
        _SettingsRow(
          label: 'Model',
          value: s.azureModel.isNotEmpty ? s.azureModel : 'Not set',
          valueColor: s.azureModel.isNotEmpty ? null : KColors.amber,
        ),
      ];
    case LLMProvider.ollama:
      final hasModel = s.ollamaModel.isNotEmpty;
      return [
        const SizedBox(height: 4),
        _SettingsRow(label: 'Base URL', value: s.ollamaBaseUrl),
        const SizedBox(height: 4),
        _SettingsRow(
          label: 'Model',
          value: hasModel ? s.ollamaModel : 'Not set',
          valueColor: hasModel ? KColors.phosphor : KColors.amber,
        ),
      ];
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SettingsRow(
      {required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label,
              style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
        Text(value,
            style: TextStyle(
                color: valueColor ?? KColors.text, fontSize: 13)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sync Section
// ---------------------------------------------------------------------------

class _SyncSection extends StatefulWidget {
  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _syncPasswordCtrl = TextEditingController();
  final _serverUrlCtrl = TextEditingController();
  bool _showServerUrl = false;

  @override
  void initState() {
    super.initState();
    final sync = context.read<SyncProvider>();
    final settings = context.read<SettingsProvider>().settings;
    _emailCtrl.text = sync.userEmail ?? settings.syncEmail;
    _serverUrlCtrl.text = sync.serverUrl;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _syncPasswordCtrl.dispose();
    _serverUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final sync = context.read<SyncProvider>();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) return;
    await sync.login(email, password);
    if (sync.isAuthenticated && mounted) {
      await context.read<SettingsProvider>().updateSync(email: email);
      _passwordCtrl.clear();
    }
  }

  Future<void> _register() async {
    final sync = context.read<SyncProvider>();
    final db = context.read<AppDatabase>();
    final projectId = context.read<ProjectProvider>().currentProjectId;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) return;
    await sync.register(email, password, db, projectId ?? '');
    if (sync.isAuthenticated && mounted) {
      await context.read<SettingsProvider>().updateSync(email: email);
      _passwordCtrl.clear();
    }
  }

  Future<void> _syncNow() async {
    final sync = context.read<SyncProvider>();
    if (sync.plan != 'solo') {
      _showSnack('Sync requires a Solo plan. Upgrade to continue.');
      return;
    }
    final db = context.read<AppDatabase>();
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      _showSnack('Select a project first.');
      return;
    }
    final syncPwd = await _askSyncPassword();
    if (syncPwd == null || syncPwd.isEmpty) return;
    await sync.syncProject(projectId, syncPwd, db);
  }

  Future<void> _pullNow() async {
    final sync = context.read<SyncProvider>();
    final db = context.read<AppDatabase>();
    final projectProvider = context.read<ProjectProvider>();

    if (sync.plan != 'solo') {
      _showSnack('Sync requires a Solo plan. Upgrade to continue.');
      return;
    }

    // Always pull based on what's on the server, not the local project ID,
    // since the local project may be a seeded demo with a non-UUID id.
    final serverProjects = await sync.listServerProjects();
    if (serverProjects.isEmpty) {
      _showSnack('No projects found on server.');
      return;
    }

    final syncPwd = await _askSyncPassword();
    if (syncPwd == null || syncPwd.isEmpty) return;
    await sync.pullProject(serverProjects.first.id, syncPwd, db);
    await projectProvider.refreshProjects();
  }

  /// Shows an inline password dialog via a bottom sheet-style dialog.
  Future<String?> _askSyncPassword() async {
    _syncPasswordCtrl.clear();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KColors.surface,
        title: const Text('Sync Password',
            style: TextStyle(color: KColors.text, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your sync password to encrypt/decrypt data.\n'
              'This can be the same as your account password.',
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _syncPasswordCtrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Sync password',
                hintText: 'Enter encryption password',
              ),
              onSubmitted: (_) =>
                  Navigator.of(ctx).pop(_syncPasswordCtrl.text),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel',
                style: TextStyle(color: KColors.textDim)),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_syncPasswordCtrl.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBillingPortal() async {
    final sync = context.read<SyncProvider>();
    final isSolo = sync.plan == 'solo';
    final url = isSolo
        ? await sync.getBillingPortalUrl()
        : await sync.getCheckoutUrl();
    if (!mounted) return;
    if (url == null) {
      _showSnack('Failed to open billing page.');
      return;
    }
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _showSnack('Could not open browser.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final isSyncing = sync.status == SyncStatus.syncing;

    return _SettingsSection(
      title: 'Sync (Beta)',
      icon: Icons.cloud_sync_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'End-to-end encrypted project sync across devices. '
            'Your data is encrypted before leaving your machine.',
            style: TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),

          if (!sync.isAuthenticated) ...[
            // --- Login / Register form ---
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'Min 8 characters',
              ),
              onSubmitted: (_) => isSyncing ? null : _login(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: isSyncing ? null : _register,
                  child: const Text('Sign Up'),
                ),
                OutlinedButton(
                  onPressed: isSyncing ? null : _login,
                  child: const Text('Log In'),
                ),
              ],
            ),
          ] else ...[
            // --- Authenticated state ---
            Row(
              children: [
                const Icon(Icons.account_circle_outlined,
                    size: 16, color: KColors.phosphor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Signed in as ${sync.userEmail ?? ''}',
                    style: const TextStyle(
                        color: KColors.text, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: sync.plan == 'solo'
                        ? KColors.phosDim
                        : KColors.amberDim,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Plan: ${(sync.plan ?? 'free').toUpperCase()}',
                    style: TextStyle(
                      color: sync.plan == 'solo'
                          ? KColors.phosphor
                          : KColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: isSyncing ? null : _syncNow,
                  icon: isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: KColors.bg),
                        )
                      : const Icon(Icons.upload_outlined, size: 14),
                  label: Text(isSyncing ? 'Syncing\u2026' : 'Sync Now'),
                ),
                OutlinedButton.icon(
                  onPressed: isSyncing ? null : _pullNow,
                  icon: const Icon(Icons.download_outlined, size: 14),
                  label: const Text('Pull from Server'),
                ),
                OutlinedButton.icon(
                  onPressed: _showBillingPortal,
                  icon: Icon(
                    sync.plan == 'solo' ? Icons.credit_card_outlined : Icons.star_outline,
                    size: 14,
                  ),
                  label: Text(sync.plan == 'solo' ? 'Manage Billing' : 'Upgrade to Solo'),
                ),
                TextButton.icon(
                  onPressed: isSyncing ? null : sync.logout,
                  icon: const Icon(Icons.logout, size: 14,
                      color: KColors.textDim),
                  label: const Text('Log Out',
                      style: TextStyle(color: KColors.textDim)),
                ),
              ],
            ),
            if (sync.lastSyncAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last synced: ${_formatDate(sync.lastSyncAt!.toLocal())}',
                style: const TextStyle(
                    color: KColors.textDim, fontSize: 12),
              ),
            ],
          ],

          // Status messages
          if (sync.status == SyncStatus.error && sync.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              sync.lastError!,
              style: const TextStyle(color: KColors.red, fontSize: 12),
            ),
          ],
          if (sync.status == SyncStatus.success) ...[
            const SizedBox(height: 8),
            const Text(
              'Operation completed successfully.',
              style: TextStyle(color: KColors.phosphor, fontSize: 12),
            ),
          ],

          // Advanced: server URL
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _showServerUrl = !_showServerUrl),
            child: Row(
              children: [
                const Text('Advanced',
                    style: TextStyle(
                        color: KColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                Icon(
                  _showServerUrl
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 14,
                  color: KColors.textDim,
                ),
              ],
            ),
          ),
          if (_showServerUrl) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _serverUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://sync.keel-app.dev',
                    ),
                    style: const TextStyle(fontSize: 12),
                    onSubmitted: (v) async {
                      final url = v.trim();
                      context.read<SyncProvider>().serverUrl = url;
                      await context
                          .read<SettingsProvider>()
                          .updateSync(serverUrl: url);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final url = _serverUrlCtrl.text.trim();
                    context.read<SyncProvider>().serverUrl = url;
                    await context
                        .read<SettingsProvider>()
                        .updateSync(serverUrl: url);
                  },
                  child: const Text('Set'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data Section
// ---------------------------------------------------------------------------

class _DataSection extends StatefulWidget {
  @override
  State<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<_DataSection> {
  bool _busy = false;
  String? _lastMessage;
  bool _isError = false;

  Future<void> _run(Future<String> Function() task) async {
    setState(() {
      _busy = true;
      _lastMessage = null;
      _isError = false;
    });
    try {
      final msg = await task();
      if (mounted) setState(() { _busy = false; _lastMessage = msg; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _lastMessage = 'Error: $e';
          _isError = true;
        });
      }
    }
  }

  Future<void> _exportJson(BuildContext context) async {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) { _showNoProject(context); return; }
    final db = context.read<AppDatabase>();
    await _run(() => JsonExporter.exportProject(projectId: projectId, db: db));
  }

  Future<void> _exportRaidCsv(BuildContext context) async {
    final projectProvider = context.read<ProjectProvider>();
    final projectId = projectProvider.currentProjectId;
    if (projectId == null) { _showNoProject(context); return; }
    final db = context.read<AppDatabase>();
    final projectName = projectProvider.currentProject?.name ?? 'project';
    await _run(() => CsvExporter.exportRaidZip(
        projectId: projectId, db: db, projectName: projectName));
  }

  Future<void> _exportDecisionsCsv(BuildContext context) async {
    final projectProvider = context.read<ProjectProvider>();
    final projectId = projectProvider.currentProjectId;
    if (projectId == null) { _showNoProject(context); return; }
    final db = context.read<AppDatabase>();
    final projectName = projectProvider.currentProject?.name ?? 'project';
    await _run(() => CsvExporter.exportDecisions(
        projectId: projectId, db: db, projectName: projectName));
  }

  Future<void> _exportActionsCsv(BuildContext context) async {
    final projectProvider = context.read<ProjectProvider>();
    final projectId = projectProvider.currentProjectId;
    if (projectId == null) { _showNoProject(context); return; }
    final db = context.read<AppDatabase>();
    final projectName = projectProvider.currentProject?.name ?? 'project';
    await _run(() => CsvExporter.exportActions(
        projectId: projectId, db: db, projectName: projectName));
  }

  Future<void> _exportPeopleCsv(BuildContext context) async {
    final projectProvider = context.read<ProjectProvider>();
    final projectId = projectProvider.currentProjectId;
    if (projectId == null) { _showNoProject(context); return; }
    final db = context.read<AppDatabase>();
    final projectName = projectProvider.currentProject?.name ?? 'project';
    await _run(() => CsvExporter.exportPeople(
        projectId: projectId, db: db, projectName: projectName));
  }

  Future<void> _importJson(BuildContext context) async {
    // Capture context-dependent objects before any async gaps
    final db = context.read<AppDatabase>();
    final projectProvider = context.read<ProjectProvider>();

    const jsonType = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [jsonType]);
    if (file == null) return;
    if (!mounted) return;

    setState(() { _busy = true; _lastMessage = null; _isError = false; });
    try {
      final content = await file.readAsString();
      final result = await JsonImporter.importFromString(content, db);
      // Refresh projects list
      await projectProvider.refreshProjects();
      if (mounted) {
        setState(() {
          _busy = false;
          _lastMessage = 'Imported "${result.projectName}": ${result.risks} risks, '
              '${result.decisions} decisions, ${result.actions} actions, '
              '${result.journalEntries} journal entries.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _lastMessage = 'Import failed: $e';
          _isError = true;
        });
      }
    }
  }

  void _showNoProject(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Select a project first.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      title: 'Data',
      icon: Icons.storage_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export',
            style: TextStyle(
              color: KColors.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _exportJson(context),
                icon: const Icon(Icons.download_outlined, size: 14),
                label: const Text('Export All (JSON)'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _exportRaidCsv(context),
                icon: const Icon(Icons.table_chart_outlined, size: 14),
                label: const Text('RAID (CSV)'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _exportDecisionsCsv(context),
                icon: const Icon(Icons.table_chart_outlined, size: 14),
                label: const Text('Decisions (CSV)'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _exportActionsCsv(context),
                icon: const Icon(Icons.table_chart_outlined, size: 14),
                label: const Text('Actions (CSV)'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _exportPeopleCsv(context),
                icon: const Icon(Icons.table_chart_outlined, size: 14),
                label: const Text('People (CSV)'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Import',
            style: TextStyle(
              color: KColors.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _importJson(context),
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_outlined, size: 14),
            label: Text(_busy ? 'Working\u2026' : 'Import from JSON'),
          ),
          if (_lastMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _lastMessage!,
              style: TextStyle(
                color: _isError ? KColors.red : KColors.phosphor,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Editor section
// ---------------------------------------------------------------------------

class _EditorSection extends StatefulWidget {
  @override
  State<_EditorSection> createState() => _EditorSectionState();
}

class _EditorSectionState extends State<_EditorSection> {
  late TextEditingController _escCtrl;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>().settings;
    _escCtrl = TextEditingController(text: settings.vimEscapeSequence);
  }

  @override
  void dispose() {
    _escCtrl.dispose();
    super.dispose();
  }

  void _saveEsc(SettingsProvider provider) {
    final seq = _escCtrl.text.trim();
    provider.save(provider.settings.copyWith(vimEscapeSequence: seq));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final vim = provider.settings.journalVimMode;
    return _SettingsSection(
      title: 'Editor',
      icon: Icons.edit_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vim mode toggle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Vim mode for journal',
                        style: TextStyle(color: KColors.text, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      vim
                          ? 'Normal mode on open · i/a/o to insert · Esc for normal'
                          : 'Standard text editing',
                      style: const TextStyle(
                          color: KColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: vim,
                onChanged: (v) => provider
                    .save(provider.settings.copyWith(journalVimMode: v)),
                activeThumbColor: KColors.amber,
              ),
            ],
          ),
          // Escape sequence — only shown when vim mode is enabled
          if (vim) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Escape sequence',
                          style:
                              TextStyle(color: KColors.text, fontSize: 13)),
                      const SizedBox(height: 2),
                      const Text(
                        'Type this in Insert mode to return to Normal (e.g. jk). '
                        'Only triggers if both keys are pressed within 300 ms. '
                        'Leave blank to disable.',
                        style: TextStyle(
                            color: KColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _escCtrl,
                    maxLength: 3,
                    style: const TextStyle(
                        color: KColors.text,
                        fontSize: 13,
                        fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      hintText: 'e.g. jk',
                      hintStyle: TextStyle(
                          color: KColors.textMuted, fontSize: 12),
                      counterText: '',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    onEditingComplete: () => _saveEsc(provider),
                    onTapOutside: (_) => _saveEsc(provider),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

