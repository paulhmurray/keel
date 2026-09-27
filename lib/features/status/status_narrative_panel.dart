import 'package:flutter/material.dart';

import '../../core/llm/llm_client_factory.dart';
import '../../core/raid/risk_rating.dart';
import '../../core/status/risk_ranking.dart';
import '../../core/status/status_calculator.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';

class StatusNarrativePanel extends StatefulWidget {
  final ProgrammeStatusData data;
  final SettingsProvider settings;
  final String projectName;
  /// Programme-kind entity → "programme" wording; otherwise "project".
  /// A project's narrative may still mention the programme it reports
  /// into, but never call the project itself a programme.
  final bool isProgramme;
  final ValueChanged<String?> onNarrativeChanged;
  final String? initialNarrative;

  const StatusNarrativePanel({
    super.key,
    required this.data,
    required this.settings,
    required this.projectName,
    required this.onNarrativeChanged,
    this.initialNarrative,
    this.isProgramme = false,
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
      final entity = widget.isProgramme ? 'programme' : 'project';
      final result = await client.complete(
        systemPrompt: 'You are an expert ${widget.isProgramme ? 'programme' : 'project'} '
            'manager writing a weekly status narrative for a steering '
            'committee about a $entity. Be concise, factual, and '
            'professional. Write in third person. 150-250 words. '
            'Refer to it as "the $entity" throughout'
            '${widget.isProgramme ? '' : '; use the word "programme" only for '
                'the wider programme this project reports into, if the '
                'context names one'}. Section headings, if any, must say '
            '"$entity", e.g. "Overall ${entity[0].toUpperCase()}${entity.substring(1)} Health". '
            'The reader cannot open Keel and has no access to the risk, '
            'decision or action registers, so never rely on a reference code '
            'alone: say what the item is in plain words — what it is, who '
            'owns it, when it is due — and put the code in brackets after, '
            'e.g. "the decision on where payments originate during '
            'transition, needed from the CFO by 3 October (DC14)". A risk '
            'marked [ESCALATED] has been raised above the $entity for '
            'attention; say it has been escalated without naming a forum '
            'unless the context does.',
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
    final entity = widget.isProgramme ? 'programme' : 'project';
    sb.writeln('${widget.isProgramme ? 'Programme' : 'Project'}: ${widget.projectName}');
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
        final soWhat = riskSoWhat(r);
        sb.writeln(
            '  ${r.ref ?? ''}${r.steerco ? ' [ESCALATED]' : ''} '
            '${r.title ?? r.description} '
            '[${ratingSummary(r.likelihood, r.impact)}]'
            '${soWhat != null ? ' — $soWhat' : ''}');
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
        'Write a status narrative covering: overall $entity health, '
        'key highlights, key concerns, and next week\'s focus.');
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action buttons
        Wrap(spacing: 8, runSpacing: 8, children: [
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
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: KColors.surface,
            border: Border.all(
                color: _accepted ? KColors.phosphor : KColors.border),
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
              hintText: 'Write a narrative, or click "Draft narrative" to '
                  'have AI generate one based on the current programme state.',
              hintStyle: TextStyle(color: KColors.textDim, fontSize: 13),
            ),
            onChanged: (v) {
              widget.onNarrativeChanged(v.isEmpty ? null : v);
              setState(() => _accepted = false);
            },
          ),
        ),
      ],
    );
  }
}
