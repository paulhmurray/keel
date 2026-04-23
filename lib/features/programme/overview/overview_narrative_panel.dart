import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/context/programme_context_service.dart';
import '../../../core/database/database.dart';
import '../../../core/llm/llm_client_factory.dart';
import '../../../providers/settings_provider.dart';
import '../../../shared/theme/keel_colors.dart';

class OverviewNarrativePanel extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ProgrammeOverviewState? overviewState;
  final VoidCallback? onUseInStatusReport;

  const OverviewNarrativePanel({
    super.key,
    required this.projectId,
    required this.db,
    this.overviewState,
    this.onUseInStatusReport,
  });

  @override
  State<OverviewNarrativePanel> createState() =>
      _OverviewNarrativePanelState();
}

class _OverviewNarrativePanelState extends State<OverviewNarrativePanel> {
  late TextEditingController _ctrl;
  bool _editing = false;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _currentNarrative ?? '');
  }

  @override
  void didUpdateWidget(OverviewNarrativePanel old) {
    super.didUpdateWidget(old);
    if (!_editing && old.overviewState != widget.overviewState) {
      _ctrl.text = _currentNarrative ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? get _currentNarrative =>
      widget.overviewState?.narrativeManualOverride ??
      widget.overviewState?.cachedNarrative;

  String? get _generatedAt =>
      widget.overviewState?.narrativeGeneratedAt != null
          ? _formatAgo(widget.overviewState!.narrativeGeneratedAt!)
          : null;

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _generate() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.settings.hasApiKey) {
      setState(() => _error = 'No API key set. Add one in Settings.');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final ctx = await ProgrammeContextService(widget.db)
          .getContext(widget.projectId);
      final prompt =
          ProgrammeContextService(widget.db).toPromptString(ctx);

      final client = LLMClientFactory.fromSettings(settings.settings);
      final result = await client.complete(
        systemPrompt:
            'You are writing a 30-second programme status narrative for a '
            'Senior PM. Write one paragraph of 4–6 sentences, no bullet '
            'points, plain prose. Focus on: current state, primary concern, '
            'what\'s moving. Do not list items. Do not add commentary. '
            'Write as if briefing a sponsor.',
        userMessage: prompt,
        maxTokens: 400,
      );
      final narrative = result.trim();
      await _save(narrative, isGenerated: true);
      if (mounted) setState(() => _ctrl.text = narrative);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _saveEdits() async {
    await _save(_ctrl.text.trim(), isGenerated: false);
    if (mounted) setState(() => _editing = false);
  }

  Future<void> _save(String narrative, {required bool isGenerated}) async {
    final id = widget.overviewState?.id ?? const Uuid().v4();
    await widget.db.programmeOverviewStateDao.upsert(
      ProgrammeOverviewStatesCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        narrativeManualOverride:
            isGenerated ? const Value(null) : Value(narrative),
        cachedNarrative: isGenerated ? Value(narrative) : Value(null),
        narrativeGeneratedAt:
            isGenerated ? Value(DateTime.now()) : const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _copy() async {
    final text = _currentNarrative;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Narrative copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrative = _currentNarrative;
    final hasNarrative = narrative != null && narrative.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'CURRENT NARRATIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.15,
                  color: KColors.textMuted,
                ),
              ),
              const Spacer(),
              if (_generatedAt != null)
                Text(
                  'Last updated: $_generatedAt',
                  style: const TextStyle(
                      fontSize: 10, color: KColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: KColors.red),
              ),
            ),

          if (_editing)
            TextField(
              controller: _ctrl,
              maxLines: null,
              minLines: 4,
              decoration: const InputDecoration(
                hintText: 'Write or paste your narrative…',
                isDense: true,
              ),
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: KColors.text,
              ),
            )
          else if (hasNarrative)
            Text(
              narrative,
              style: const TextStyle(
                fontSize: 13,
                height: 1.6,
                color: KColors.text,
              ),
            )
          else
            Text(
              _generating
                  ? 'Generating narrative…'
                  : 'No narrative yet. Click "Regenerate" to generate one.',
              style: TextStyle(
                fontSize: 12,
                color: _generating ? KColors.textDim : KColors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),

          const SizedBox(height: 12),
          Row(
            children: [
              if (_editing) ...[
                TextButton.icon(
                  onPressed: _saveEdits,
                  icon: const Icon(Icons.check, size: 13),
                  label: const Text('Save', style: TextStyle(fontSize: 11)),
                  style:
                      TextButton.styleFrom(foregroundColor: KColors.phosphor),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _editing = false;
                      _ctrl.text = _currentNarrative ?? '';
                    });
                  },
                  style:
                      TextButton.styleFrom(foregroundColor: KColors.textDim),
                  child: const Text('Cancel',
                      style: TextStyle(fontSize: 11)),
                ),
              ] else ...[
                TextButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined, size: 13),
                  label:
                      const Text('Edit', style: TextStyle(fontSize: 11)),
                  style:
                      TextButton.styleFrom(foregroundColor: KColors.textDim),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 11,
                          height: 11,
                          child:
                              CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.auto_awesome_outlined, size: 13),
                  label: const Text('Regenerate',
                      style: TextStyle(fontSize: 11)),
                  style:
                      TextButton.styleFrom(foregroundColor: KColors.textDim),
                ),
                if (hasNarrative) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_outlined, size: 13),
                    label: const Text('Copy',
                        style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                        foregroundColor: KColors.textDim),
                  ),
                ],
                if (hasNarrative && widget.onUseInStatusReport != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: widget.onUseInStatusReport,
                    icon:
                        const Icon(Icons.send_outlined, size: 13),
                    label: const Text('Use in status report',
                        style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                        foregroundColor: KColors.textDim),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}
