import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../core/status/narrative_refs.dart';

import '../../core/export/pdf_exporter.dart';
import '../../core/raid/risk_rating.dart';
import '../../core/status/risk_ranking.dart';
import '../../core/export/status_html_exporter.dart';
import '../../core/status/status_calculator.dart';
import '../../shared/theme/keel_colors.dart';

class StatusExportDialog extends StatefulWidget {
  final String projectName;
  final ProgrammeStatusData data;
  final List<String> monthLabels;
  final String? narrative;
  final DateTime weekOf;
  /// When given, codes in the narrative (R12, DC14…) are resolved to a
  /// "Referenced items" section so the report reads without Keel.
  final AppDatabase? db;
  final String? projectId;

  const StatusExportDialog({
    super.key,
    required this.projectName,
    required this.data,
    required this.monthLabels,
    this.narrative,
    required this.weekOf,
    this.db,
    this.projectId,
  });

  @override
  State<StatusExportDialog> createState() => _StatusExportDialogState();
}

class _StatusExportDialogState extends State<StatusExportDialog> {
  bool _exporting = false;
  String? _result;
  String? _error;

  Future<List<ReferencedItem>> _referenced() async {
    final db = widget.db;
    final pid = widget.projectId;
    if (db == null || pid == null) return const [];
    return resolveNarrativeRefsFromDb(db, pid, widget.narrative);
  }

  Future<void> _exportHtml() async {
    setState(() { _exporting = true; _error = null; _result = null; });
    try {
      final path = await StatusHtmlExporter.export(
        projectName:  widget.projectName,
        data:         widget.data,
        monthLabels:  widget.monthLabels,
        narrative:    widget.narrative,
        referenced:   await _referenced(),
        weekOf:       widget.weekOf,
      );
      setState(() => _result = path);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() { _exporting = true; _error = null; _result = null; });
    try {
      final d = widget.data;
      final referenced = await _referenced();
      final summary = StatusSummaryForPdf(
        programmeRag:      d.programmeRag.value,
        trendArrow:        d.programmeTrend.arrow,
        trendLabel:        d.programmeTrend.label,
        narrative:         widget.narrative,
        referenced: [
          for (final r in referenced)
            StatusRefPdf(ref: r.ref, kind: r.kind, headline: r.headline, detail: r.detail),
        ],
        playbookStage:     d.playbookStageLine,
        workstreams: d.workstreams.map((ws) => StatusWorkstreamPdf(
          name:  ws.wp.shortCode != null
              ? '${ws.wp.shortCode} — ${ws.wp.name}'
              : ws.wp.name,
          rag:   ws.rag.value,
          trend: '${ws.trend.arrow} ${ws.trend.label}',
        )).toList(),
        milestones: d.upcomingMilestones.map((m) {
          final icon = switch (m.activityType) {
            'hard_deadline' => '!', 'gate' => 'G', _ => '*'
          };
          final monthLabel = m.startMonth != null &&
                  m.startMonth! >= 0 &&
                  m.startMonth! < widget.monthLabels.length
              ? widget.monthLabels[m.startMonth!]
              : 'M${m.startMonth ?? '?'}';
          return StatusMilestonePdf(
            icon:  icon,
            name:  m.name,
            date:  monthLabel,
            owner: m.owner ?? '—',
          );
        }).toList(),
        risks: d.topRisks.map((r) => StatusRiskPdf(
          ref:         r.ref ?? '—',
          likelihood:  likelihoodLabel(r.likelihood),
          impact:      consequenceLabel(r.impact),
          description: r.description,
          title:       r.title,
          rating:      ratingSummary(r.likelihood, r.impact),
          steerco:     r.steerco,
          soWhat:      riskSoWhat(r),
          strategy:    kRiskStrategyLabels[r.strategy]?.split(' — ').first,
          owner:       r.owner,
          dueDate:     r.dueDate,
          change:      riskChangeLabel(
              riskChangeSince(r, d.previousTopRisks), r, d.previousTopRisks),
        )).toList(),
        decisions: d.pendingDecisions.map((dec) => StatusDecisionPdf(
          ref:         dec.ref ?? '—',
          dueDate:     dec.dueDate ?? '—',
          description: dec.description,
        )).toList(),
        overdueActions:    d.overdueActionsCount,
        openActions:       d.openActionsCount,
        pendingDecisions:  d.pendingDecisionsCount,
        openRisks:         d.openRisksCount,
      );
      final path = await PdfExporter.exportStatus(
        projectName: widget.projectName,
        summary:     summary,
      );
      setState(() => _result = path);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Export Status',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export the status dashboard as a standalone HTML file '
            'suitable for email or browser viewing.',
            style: TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (_result != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: KColors.phosDim,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_result!,
                  style: const TextStyle(
                      color: KColors.phosphor, fontSize: 11)),
            ),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: KColors.redDim,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_error!,
                  style:
                      const TextStyle(color: KColors.red, fontSize: 11)),
            ),
          const SizedBox(height: 16),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _exporting ? null : _exportHtml,
              icon: _exporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.html, size: 16),
              label: Text(_exporting ? 'Exporting…' : 'HTML'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _exporting ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: KColors.surface2,
                foregroundColor: KColors.text,
                side: const BorderSide(color: KColors.border2),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close',
                  style:
                      TextStyle(color: KColors.textDim, fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }
}
