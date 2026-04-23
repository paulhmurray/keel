import 'package:flutter/material.dart';

import '../../core/llm/llm_client_factory.dart';
import '../../core/status/status_calculator.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';

class StatusNarrativePanel extends StatefulWidget {
  final ProgrammeStatusData data;
  final SettingsProvider settings;
  final String projectName;
  final ValueChanged<String?> onNarrativeChanged;
  final String? initialNarrative;

  const StatusNarrativePanel({
    super.key,
    required this.data,
    required this.settings,
    required this.projectName,
    required this.onNarrativeChanged,
    this.initialNarrative,
  });

  @override
  State<StatusNarrativePanel> createState() => _StatusNarrativePanelState();
}

class _StatusNarrativePanelState extends State<StatusNarrativePanel> {
  late final TextEditingController _ctrl;
  bool _drafting = false;
  bool _accepted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialNarrative ?? '');
    _accepted = (widget.initialNarrative?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _draft() async {
    if (!widget.settings.settings.hasApiKey) {
      setState(() => _error = 'No API key set. Add one in Settings.');
      return;
    }
    setState(() { _drafting = true; _error = null; });
    try {
      final client =
          LLMClientFactory.fromSettings(widget.settings.settings);
      final prompt = _buildPrompt();
      final result = await client.complete(
        systemPrompt: 'You are an expert programme manager writing a weekly '
            'status narrative for a steering committee. Be concise, factual, '
            'and professional. Write in third person. 150-250 words.',
        userMessage: prompt,
        maxTokens: 500,
      );
      _ctrl.text = result.trim();
      widget.onNarrativeChanged(result.trim());
      setState(() { _accepted = false; });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  String _buildPrompt() {
    final d = widget.data;
    final sb = StringBuffer();
    sb.writeln('Programme: ${widget.projectName}');
    sb.writeln('Overall RAG: ${d.programmeRag.label}');
    sb.writeln('Trend: ${d.programmeTrend.label}');
    sb.writeln();
    sb.writeln('Workstream RAG:');
    for (final ws in d.workstreams) {
      sb.writeln('  ${ws.wp.name}: ${ws.rag.label}');
    }
    sb.writeln();
    if (d.upcomingMilestones.isNotEmpty) {
      sb.writeln('Upcoming milestones:');
      for (final m in d.upcomingMilestones) {
        sb.writeln('  ${m.name} (${m.owner ?? 'no owner'})');
      }
      sb.writeln();
    }
    if (d.topRisks.isNotEmpty) {
      sb.writeln('Top risks:');
      for (final r in d.topRisks) {
        sb.writeln(
            '  ${r.ref ?? ''} ${r.description} [${r.likelihood}/${r.impact}]');
      }
      sb.writeln();
    }
    if (d.pendingDecisions.isNotEmpty) {
      sb.writeln('Pending decisions:');
      for (final dec in d.pendingDecisions) {
        sb.writeln(
            '  ${dec.ref ?? ''} ${dec.description} (due: ${dec.dueDate ?? 'no date'})');
      }
      sb.writeln();
    }
    sb.writeln('Overdue actions: ${d.overdueActionsCount}');
    sb.writeln('Open actions: ${d.openActionsCount}');
    sb.writeln('Open risks: ${d.openRisksCount}');
    sb.writeln();
    sb.writeln(
        'Write a status narrative covering: overall programme health, '
        'key highlights, key concerns, and next week\'s focus.');
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action buttons
        Row(children: [
          ElevatedButton.icon(
            onPressed: _drafting ? null : _draft,
            icon: _drafting
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 14),
            label: Text(_drafting ? 'Drafting…' : 'Draft narrative'),
          ),
          if (_ctrl.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            if (!_accepted)
              ElevatedButton(
                onPressed: () {
                  widget.onNarrativeChanged(_ctrl.text);
                  setState(() => _accepted = true);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: KColors.phosDim),
                child: const Text('Accept',
                    style: TextStyle(color: KColors.phosphor)),
              ),
            if (_accepted)
              TextButton(
                onPressed: () {
                  widget.onNarrativeChanged(null);
                  _ctrl.clear();
                  setState(() => _accepted = false);
                },
                child: const Text('Clear',
                    style: TextStyle(color: KColors.textDim, fontSize: 12)),
              ),
          ],
        ]),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(color: KColors.red, fontSize: 11)),
        ],
        if (_ctrl.text.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: KColors.surface,
              border: Border.all(
                  color:
                      _accepted ? KColors.phosphor : KColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: TextField(
              controller: _ctrl,
              minLines: 5,
              maxLines: null,
              style: const TextStyle(
                  color: KColors.text, fontSize: 13, height: 1.6),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
              onChanged: (v) {
                widget.onNarrativeChanged(v.isEmpty ? null : v);
                setState(() => _accepted = false);
              },
            ),
          ),
        ],
      ],
    );
  }
}
