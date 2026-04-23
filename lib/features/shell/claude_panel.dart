import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/llm/context_builder.dart';
import '../../core/llm/llm_client_factory.dart';
import '../../core/llm/ollama_client.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';

// ---------------------------------------------------------------------------
// Context section data class
// ---------------------------------------------------------------------------

class _ContextSection {
  final String label;
  final int count;
  const _ContextSection(this.label, this.count);
}

// ---------------------------------------------------------------------------
// Chat message model
// ---------------------------------------------------------------------------

enum _MessageRole { user, assistant, system }

class _ChatMessage {
  final _MessageRole role;
  final String content;
  final DateTime timestamp;

  _ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ---------------------------------------------------------------------------
// Claude Panel
// ---------------------------------------------------------------------------

class ClaudePanel extends StatefulWidget {
  const ClaudePanel({super.key});

  @override
  State<ClaudePanel> createState() => _ClaudePanelState();
}

class _ClaudePanelState extends State<ClaudePanel> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // Per-project message history, keyed by projectId.
  final Map<String, List<_ChatMessage>> _historyByProject = {};
  String? _activeProjectId;

  bool _isLoading = false;
  String? _errorMessage;

  bool _showContextInfo = false;
  List<_ContextSection> _contextSections = [];

  List<_ChatMessage> get _messages =>
      _historyByProject[_activeProjectId ?? ''] ?? [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final projectProvider = context.read<ProjectProvider>();
    final newId = projectProvider.currentProjectId;
    final newName =
        projectProvider.currentProject?.name ?? 'Unknown Project';
    if (newId != null && newId != _activeProjectId) {
      _handleProjectSwitch(newId, newName);
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _ensureProjectHistory(String projectId) {
    _historyByProject.putIfAbsent(projectId, () => []);
  }

  void _handleProjectSwitch(String newProjectId, String newProjectName) {
    if (_activeProjectId == newProjectId) return;
    _ensureProjectHistory(newProjectId);
    setState(() {
      _activeProjectId = newProjectId;
      _errorMessage = null;
      final history = _historyByProject[newProjectId]!;
      if (history.isNotEmpty) {
        history.add(_ChatMessage(
          role: _MessageRole.system,
          content: 'Switched to $newProjectName',
        ));
      }
    });
    _scrollToBottom();
  }

  Future<void> _loadContextSummary(String projectId) async {
    final db = context.read<AppDatabase>();
    final sections = await ContextBuilder(db).buildContextSummary(projectId);
    if (mounted) setState(() => _contextSections = sections.map((e) => _ContextSection(e.$1, e.$2)).toList());
  }

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _isLoading) return;

    final settings = context.read<SettingsProvider>();
    final sp = settings.settings;
    final projectId = context.read<ProjectProvider>().currentProjectId;
    final db = context.read<AppDatabase>();

    _inputCtrl.clear();

    final pid = projectId ?? '';
    _ensureProjectHistory(pid);

    setState(() {
      _historyByProject[pid]!
          .add(_ChatMessage(role: _MessageRole.user, content: text));
      _isLoading = true;
      _errorMessage = null;
    });
    _scrollToBottom();

    try {
      final contextBuilder = ContextBuilder(db);
      final systemPrompt = projectId != null
          ? await contextBuilder.buildSystemPrompt(projectId)
          : _defaultSystemPrompt();

      // For Ollama: ensure the server is running, starting it if needed
      if (sp.llmProvider == LLMProvider.ollama) {
        final running =
            await OllamaClient.ensureRunning(sp.ollamaBaseUrl);
        if (!running) {
          throw Exception(
            'Could not reach Ollama at ${sp.ollamaBaseUrl}.\n'
            'Make sure the ollama binary is installed and in your PATH, '
            'or start it manually with: ollama serve',
          );
        }
      }

      // For Ollama: auto-correct the model to whatever is actually installed
      if (sp.llmProvider == LLMProvider.ollama) {
        final installed = await OllamaClient.getAvailableModels(sp.ollamaBaseUrl);
        if (installed.isNotEmpty) {
          final configuredBase = sp.ollamaModel.split(':').first;
          final match = installed.firstWhere(
            (m) => m.split(':').first == configuredBase,
            orElse: () => '',
          );
          if (match.isEmpty) {
            // Configured model not installed — silently use the first installed one
            final firstBase = installed.first.split(':').first;
            await settings.save(sp.copyWith(ollamaModel: firstBase));
          }
        }
      }

      final client = LLMClientFactory.fromSettings(settings.settings);
      final userMessage = _buildUserMessage(text, pid);

      // Insert a placeholder the user sees immediately; fill it as tokens arrive.
      if (mounted) {
        setState(() {
          _historyByProject[pid]!.add(
              _ChatMessage(role: _MessageRole.assistant, content: ''));
        });
        _scrollToBottom();
      }

      final buffer = StringBuffer();
      await for (final token in client.stream(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
      )) {
        buffer.write(token);
        if (mounted) {
          setState(() {
            final msgs = _historyByProject[pid]!;
            msgs[msgs.length - 1] =
                _ChatMessage(role: _MessageRole.assistant, content: buffer.toString());
          });
          _scrollToBottom();
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          final h = _historyByProject[pid]!;
          if (h.length > 20) h.removeRange(0, h.length - 20);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Remove empty assistant placeholder if streaming failed mid-flight
          final msgs = _historyByProject[pid];
          if (msgs != null &&
              msgs.isNotEmpty &&
              msgs.last.role == _MessageRole.assistant &&
              msgs.last.content.isEmpty) {
            msgs.removeLast();
          }
          _isLoading = false;
          _errorMessage = _formatError(e.toString());
        });
        _scrollToBottom();
      }
    }
  }

  String _buildUserMessage(String currentText, String projectId) {
    final history = (_historyByProject[projectId] ?? [])
        .where((m) =>
            m.role != _MessageRole.system &&
            !(m.role == _MessageRole.user && m.content == currentText))
        .toList();
    if (history.isEmpty) return currentText;

    final recent =
        history.length > 8 ? history.sublist(history.length - 8) : history;
    final buffer = StringBuffer();
    buffer.writeln('[Conversation history]');
    for (final m in recent) {
      final label = m.role == _MessageRole.user ? 'User' : 'Assistant';
      buffer.writeln('$label: ${m.content}');
    }
    buffer.writeln('[End of history]');
    buffer.writeln();
    buffer.writeln(currentText);
    return buffer.toString();
  }

  String _defaultSystemPrompt() {
    return 'You are Keel, an expert AI assistant for Technical Programme Managers (TPMs). '
        'You help with programme planning, risk management, decision-making, '
        'stakeholder communication, and delivery governance. '
        'You are precise, concise, and action-oriented.';
  }

  String _formatError(String raw) {
    if (raw.contains('401'))
      return 'Authentication failed — check your API key in Settings.';
    if (raw.contains('429'))
      return 'Rate limit reached. Please wait a moment and try again.';
    if (raw.contains('500') || raw.contains('529'))
      return 'API is temporarily unavailable. Please try again shortly.';
    if (raw.contains('SocketException') || raw.contains('HandshakeException'))
      return 'Network error — check your internet connection.';
    if (raw.contains('404') && raw.contains('not found'))
      return 'Model not found. Go to Settings → LLM Settings and check your Ollama model name.';
    if (raw.contains('Connection refused') || raw.contains('localhost:11434'))
      return 'Ollama is not running. Try reopening the Local AI Setup wizard in Settings.';
    return 'Error: $raw';
  }

  @override
  Widget build(BuildContext context) {
    final projectProvider = context.watch<ProjectProvider>();
    final newId = projectProvider.currentProjectId;
    if (newId != null && newId != _activeProjectId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleProjectSwitch(
              newId, projectProvider.currentProject?.name ?? newId);
        }
      });
    }

    final settings = context.watch<SettingsProvider>();
    final hasKey = settings.hasApiKey;

    return Container(
      color: KColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            hasKey: hasKey,
            showContextInfo: _showContextInfo,
            onToggleContextInfo: () {
              if (!_showContextInfo && _activeProjectId != null) {
                _loadContextSummary(_activeProjectId!);
              }
              setState(() => _showContextInfo = !_showContextInfo);
            },
          ),

          if (_showContextInfo && _contextSections.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: KColors.surface2,
                border: Border(bottom: BorderSide(color: KColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONTEXT INJECTED',
                    style: TextStyle(color: KColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.1),
                  ),
                  const SizedBox(height: 6),
                  ..._contextSections.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.check, size: 10, color: KColors.phosphor),
                        const SizedBox(width: 5),
                        Expanded(child: Text(s.label, style: const TextStyle(color: KColors.textDim, fontSize: 10))),
                        if (s.count > 0) Text('${s.count}', style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
                      ],
                    ),
                  )),
                ],
              ),
            ),

          // Context summary
          if (_activeProjectId != null)
            _ContextSummary(projectId: _activeProjectId!),

          Expanded(
            child: hasKey ? _buildChatArea() : _buildNoKeyPrompt(),
          ),

          _InputBar(
            controller: _inputCtrl,
            enabled: hasKey && !_isLoading,
            isLoading: _isLoading,
            onSend: hasKey ? _sendMessage : null,
          ),
        ],
      ),
    );
  }

  Widget _buildNoKeyPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_outlined,
                size: 36, color: KColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'Configure your API key to start chatting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'Go to Settings → LLM Settings to add your Anthropic API key.',
              textAlign: TextAlign.center,
              style: TextStyle(color: KColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatArea() {
    final msgs = _messages;
    final visibleMessages =
        msgs.where((m) => m.role != _MessageRole.system).toList();
    if (visibleMessages.isEmpty && !_isLoading && _errorMessage == null) {
      return _buildWelcomeScreen();
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemCount: msgs.length +
          (_isLoading ? 1 : 0) +
          (_errorMessage != null ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i < msgs.length) {
          final m = msgs[i];
          if (m.role == _MessageRole.system) {
            return _ProjectSwitchDivider(label: m.content);
          }
          return _MessageBubble(message: m);
        }
        if (_isLoading && i == msgs.length) {
          return const _TypingIndicator();
        }
        if (_errorMessage != null) {
          return _ErrorBubble(message: _errorMessage!);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildWelcomeScreen() {
    final projectName =
        context.watch<ProjectProvider>().currentProject?.name ??
            'your project';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome,
                size: 28, color: KColors.phosphor),
            const SizedBox(height: 12),
            Text(
              'Ask me anything about $projectName',
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                  color: KColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 14),
            _SuggestionChips(onTap: (s) {
              _inputCtrl.text = s;
              _sendMessage();
            }),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Context Summary
// ---------------------------------------------------------------------------

class _ContextSummary extends StatelessWidget {
  final String projectId;

  const _ContextSummary({required this.projectId});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final projectProvider = context.watch<ProjectProvider>();
    final projectName = projectProvider.currentProject?.name;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          if (projectName != null)
            _ContextPill(label: projectName, icon: Icons.folder_outlined),
          StreamBuilder<List<Risk>>(
            stream: db.raidDao.watchRisksForProject(projectId),
            builder: (_, snap) {
              final count = snap.data?.length ?? 0;
              if (count == 0) return const SizedBox.shrink();
              return _ContextPill(label: '$count risks');
            },
          ),
          StreamBuilder<List<Decision>>(
            stream:
                db.decisionsDao.watchPendingDecisionsForProject(projectId),
            builder: (_, snap) {
              final count = snap.data?.length ?? 0;
              if (count == 0) return const SizedBox.shrink();
              return _ContextPill(label: '$count pending');
            },
          ),
          StreamBuilder<List<ProjectAction>>(
            stream:
                db.actionsDao.watchOverdueActionsForProject(projectId),
            builder: (_, snap) {
              final count = snap.data?.length ?? 0;
              if (count == 0) return const SizedBox.shrink();
              return _ContextPill(
                  label: '$count overdue', color: KColors.red);
            },
          ),
        ],
      ),
    );
  }
}

class _ContextPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;

  const _ContextPill({required this.label, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? KColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: KColors.border2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _PanelHeader extends StatelessWidget {
  final bool hasKey;
  final bool showContextInfo;
  final VoidCallback? onToggleContextInfo;

  const _PanelHeader({
    required this.hasKey,
    this.showContextInfo = false,
    this.onToggleContextInfo,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final name = _providerLabel(settings).toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 13, color: KColors.phosphor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '⊹ $name',
              style: GoogleFonts.syne(
                color: KColors.phosphor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.info_outline,
              size: 14,
              color: showContextInfo ? KColors.amber : KColors.textMuted,
            ),
            onPressed: onToggleContextInfo,
            tooltip: 'Context injected',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: hasKey ? KColors.phosDim : KColors.amberDim,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              hasKey ? 'Connected' : 'Not configured',
              style: TextStyle(
                color: hasKey ? KColors.phosphor : KColors.amber,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _providerLabel(AppSettings s) {
  switch (s.llmProvider) {
    case LLMProvider.claudeApi:      return 'Claude';
    case LLMProvider.openAi:         return 'ChatGPT';
    case LLMProvider.grok:           return 'Grok';
    case LLMProvider.githubModels:   return 'GitHub Models';
    case LLMProvider.azureOpenAi:    return 'Azure OpenAI';
    case LLMProvider.ollama:
      final base = s.ollamaModel.split(':').first;
      return base.isEmpty ? 'Ollama' : base;
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool isLoading;
  final VoidCallback? onSend;

  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.isLoading,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: KColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              decoration: InputDecoration(
                hintText: 'Ask ${_providerLabel(context.watch<SettingsProvider>().settings)}…',
                isDense: true,
                fillColor: KColors.bg,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide:
                      const BorderSide(color: KColors.phosphor, width: 1.5),
                ),
              ),
              style: GoogleFonts.jetBrainsMono(fontSize: 11),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled ? (_) => onSend?.call() : null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: enabled ? onSend : null,
            icon: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: KColors.phosphor),
                  )
                : const Icon(Icons.send_outlined),
            iconSize: 16,
            tooltip: 'Send',
            style: IconButton.styleFrom(
              backgroundColor: enabled
                  ? KColors.phosDim
                  : KColors.surface2,
              foregroundColor:
                  enabled ? KColors.phosphor : KColors.textMuted,
              disabledForegroundColor: KColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _MessageRole.user;

    return Align(
      alignment:
          isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isUser ? KColors.blueDim : KColors.surface2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(6),
            topRight: const Radius.circular(6),
            bottomLeft: isUser
                ? const Radius.circular(6)
                : const Radius.circular(1),
            bottomRight: isUser
                ? const Radius.circular(1)
                : const Radius.circular(6),
          ),
          border: Border.all(
            color: isUser ? KColors.border2 : KColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUser
                      ? Icons.person_outline
                      : Icons.auto_awesome,
                  size: 10,
                  color: isUser ? KColors.blue : KColors.phosphor,
                ),
                const SizedBox(width: 4),
                Text(
                  isUser ? 'You' : _providerLabel(context.watch<SettingsProvider>().settings),
                  style: TextStyle(
                    color: isUser ? KColors.blue : KColors.phosphor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            SelectableText(
              message.content,
              style: GoogleFonts.jetBrainsMono(
                color: KColors.text,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: KColors.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: KColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome,
                size: 11, color: KColors.phosphor),
            const SizedBox(width: 6),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor:
                    AlwaysStoppedAnimation<Color>(KColors.phosphor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Thinking…',
              style: GoogleFonts.jetBrainsMono(
                  color: KColors.textDim,
                  fontSize: 11,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  final String message;

  const _ErrorBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.redDim,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: KColors.red.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 13, color: KColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: KColors.red, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectSwitchDivider extends StatelessWidget {
  final String label;

  const _ProjectSwitchDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: KColors.border)),
          const SizedBox(width: 6),
          Icon(Icons.swap_horiz, size: 11, color: KColors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              color: KColors.textMuted,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 6),
          const Expanded(child: Divider(color: KColors.border)),
        ],
      ),
    );
  }
}

class _SuggestionChips extends StatelessWidget {
  final void Function(String) onTap;

  static const _suggestions = [
    'What are the top risks I should focus on?',
    'Summarise the current project status',
    'What decisions are still pending?',
    'Draft a stakeholder update for this week',
  ];

  const _SuggestionChips({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: _suggestions
          .map(
            (s) => InkWell(
              onTap: () => onTap(s),
              borderRadius: BorderRadius.circular(2),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(color: KColors.border2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  s,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: KColors.textDim,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
