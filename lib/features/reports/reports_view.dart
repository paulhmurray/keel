import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../core/export/html_exporter.dart';
import '../../core/export/pdf_exporter.dart';
import '../../core/export/handover_exporter.dart';
import '../../core/llm/llm_client_factory.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/rag_badge.dart';
import '../../shared/widgets/dropdown_field.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project.'));
    }
    final db = context.read<AppDatabase>();
    final settings = context.watch<SettingsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              const Icon(Icons.description, color: KColors.amber, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text('Reports',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: KColors.border)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Status Reports'),
              Tab(text: 'RAID Export'),
              Tab(text: 'Programme Narrative'),
              Tab(text: 'Handover Pack'),
            ],
            indicatorColor: KColors.amber,
            labelColor: KColors.amber,
            unselectedLabelColor: KColors.textDim,
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _StatusReportsTab(
                  projectId: projectId, db: db, settings: settings),
              _RaidExportTab(projectId: projectId, db: db),
              _NarrativeExportTab(projectId: projectId, db: db),
              _HandoverPackTab(projectId: projectId, db: db),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status Reports Tab
// ---------------------------------------------------------------------------

class _StatusReportsTab extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final SettingsProvider settings;

  const _StatusReportsTab(
      {required this.projectId, required this.db, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _ReportFormDialog(
                      projectId: projectId, db: db, settings: settings),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Report'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<StatusReport>>(
              stream: db.reportsDao.watchReportsForProject(projectId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No status reports yet.',
                        style: TextStyle(color: KColors.textDim)),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _ReportCard(
                    report: items[i],
                    db: db,
                    projectId: projectId,
                    settings: settings,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final StatusReport report;
  final AppDatabase db;
  final String projectId;
  final SettingsProvider settings;

  const _ReportCard({
    required this.report,
    required this.db,
    required this.projectId,
    required this.settings,
  });

  Future<String> _projectName() async {
    final proj = await db.projectDao.getProjectById(projectId);
    return proj?.name ?? 'Project';
  }

  void _exportHtml(BuildContext context) async {
    final name = await _projectName();
    try {
      final path =
          await HtmlExporter.exportReport(report: report, projectName: name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Saved: $path'),
              duration: const Duration(seconds: 4)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'),
              backgroundColor: KColors.red),
        );
      }
    }
  }

  void _exportPdf(BuildContext context) async {
    final name = await _projectName();
    try {
      final path =
          await PdfExporter.exportReport(report: report, projectName: name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Saved: $path'),
              duration: const Duration(seconds: 4)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'),
              backgroundColor: KColors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => _ReportDetailDialog(report: report),
        ),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RAGBadge(rag: report.overallRag, showLabel: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(report.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  if (report.period != null) ...[
                    Flexible(
                      child: Text(report.period!,
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                  ],
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (val) {
                      if (val == 'edit') {
                        showDialog(
                          context: context,
                          builder: (_) => _ReportFormDialog(
                            projectId: projectId,
                            db: db,
                            settings: settings,
                            report: report,
                          ),
                        );
                      } else if (val == 'html') {
                        _exportHtml(context);
                      } else if (val == 'pdf') {
                        _exportPdf(context);
                      } else if (val == 'delete') {
                        db.reportsDao.deleteReport(report.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                          value: 'html',
                          child: Row(children: [
                            Icon(Icons.code, size: 16),
                            SizedBox(width: 8),
                            Text('Export HTML'),
                          ])),
                      PopupMenuItem(
                          value: 'pdf',
                          child: Row(children: [
                            Icon(Icons.picture_as_pdf, size: 16),
                            SizedBox(width: 8),
                            Text('Export PDF'),
                          ])),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              if (report.summary != null && report.summary!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(report.summary!,
                    style: const TextStyle(
                        color: KColors.textDim, fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report detail (read-only view)
// ---------------------------------------------------------------------------

class _ReportDetailDialog extends StatelessWidget {
  final StatusReport report;
  const _ReportDetailDialog({required this.report});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          RAGBadge(rag: report.overallRag, showLabel: false),
          const SizedBox(width: 10),
          Expanded(child: Text(report.title)),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (report.period != null) ...[
                Text('Period: ${report.period}',
                    style: const TextStyle(
                        color: KColors.textDim, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              if (report.summary != null && report.summary!.isNotEmpty) ...[
                _SectionLabel('Summary'),
                Text(report.summary!),
                const SizedBox(height: 12),
              ],
              if (report.accomplishments != null &&
                  report.accomplishments!.isNotEmpty) ...[
                _SectionLabel('Accomplishments'),
                Text(report.accomplishments!),
                const SizedBox(height: 12),
              ],
              if (report.nextSteps != null &&
                  report.nextSteps!.isNotEmpty) ...[
                _SectionLabel('Next Steps'),
                Text(report.nextSteps!),
                const SizedBox(height: 12),
              ],
              if (report.risksHighlighted != null &&
                  report.risksHighlighted!.isNotEmpty) ...[
                _SectionLabel('Risks Highlighted'),
                Text(report.risksHighlighted!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
              color: KColors.amber,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.8)),
    );
  }
}

// ---------------------------------------------------------------------------
// Report form dialog (new + edit + Claude draft)
// ---------------------------------------------------------------------------

class _ReportFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final SettingsProvider settings;
  final StatusReport? report;

  const _ReportFormDialog({
    required this.projectId,
    required this.db,
    required this.settings,
    this.report,
  });

  @override
  State<_ReportFormDialog> createState() => _ReportFormDialogState();
}

class _ReportFormDialogState extends State<_ReportFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtrl;
  late TextEditingController _periodCtrl;
  late TextEditingController _summaryCtrl;
  late TextEditingController _accomplishmentsCtrl;
  late TextEditingController _nextStepsCtrl;
  late TextEditingController _risksCtrl;
  late String _overallRag;
  bool _drafting = false;
  String? _draftError;

  final _rags = ['green', 'amber', 'red'];

  @override
  void initState() {
    super.initState();
    final r = widget.report;
    _titleCtrl = TextEditingController(text: r?.title ?? '');
    _periodCtrl = TextEditingController(text: r?.period ?? '');
    _summaryCtrl = TextEditingController(text: r?.summary ?? '');
    _accomplishmentsCtrl =
        TextEditingController(text: r?.accomplishments ?? '');
    _nextStepsCtrl = TextEditingController(text: r?.nextSteps ?? '');
    _risksCtrl = TextEditingController(text: r?.risksHighlighted ?? '');
    _overallRag = r?.overallRag ?? 'green';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _periodCtrl.dispose();
    _summaryCtrl.dispose();
    _accomplishmentsCtrl.dispose();
    _nextStepsCtrl.dispose();
    _risksCtrl.dispose();
    super.dispose();
  }

  Future<void> _draftWithClaude() async {
    if (!widget.settings.settings.hasApiKey) {
      setState(() => _draftError = 'No API key set. Add one in Settings.');
      return;
    }

    setState(() {
      _drafting = true;
      _draftError = null;
    });

    try {
      // Gather project data
      final risks =
          await widget.db.raidDao.getRisksForProject(widget.projectId);
      final decisions =
          await widget.db.decisionsDao.getDecisionsForProject(widget.projectId);
      final actions =
          await widget.db.actionsDao.getActionsForProject(widget.projectId);

      final openRisks = risks.where((r) => r.status == 'open').toList();
      final highRisks = openRisks
          .where((r) => r.impact == 'high' || r.likelihood == 'high')
          .take(5)
          .toList();
      final recentDecisions = decisions.take(5).toList();
      final openActions =
          actions.where((a) => a.status != 'closed').toList();
      final overdueActions = openActions.where((a) {
        if (a.dueDate == null) return false;
        final today = DateTime.now().toIso8601String().substring(0, 10);
        return a.dueDate!.compareTo(today) < 0;
      }).toList();

      final buffer = StringBuffer();
      buffer.writeln('PROJECT DATA FOR STATUS REPORT:');
      buffer.writeln();

      if (highRisks.isNotEmpty) {
        buffer.writeln('TOP RISKS (open, high impact/likelihood):');
        for (final r in highRisks) {
          buffer.writeln(
              '- ${r.ref ?? ''} ${r.description} [likelihood: ${r.likelihood}, impact: ${r.impact}]');
          if (r.mitigation != null) {
            buffer.writeln('  Mitigation: ${r.mitigation}');
          }
        }
        buffer.writeln();
      }

      if (recentDecisions.isNotEmpty) {
        buffer.writeln('RECENT DECISIONS:');
        for (final d in recentDecisions) {
          buffer.writeln('- ${d.ref ?? ''} ${d.description} [${d.status}]');
          if (d.outcome != null) buffer.writeln('  Outcome: ${d.outcome}');
        }
        buffer.writeln();
      }

      buffer.writeln('ACTIONS SUMMARY:');
      buffer.writeln('- ${openActions.length} open actions');
      buffer.writeln('- ${overdueActions.length} overdue actions');
      if (overdueActions.isNotEmpty) {
        buffer.writeln('Overdue:');
        for (final a in overdueActions.take(5)) {
          buffer.writeln(
              '  - ${a.description} (owner: ${a.owner ?? "unassigned"}, due: ${a.dueDate})');
        }
      }

      final period =
          _periodCtrl.text.isNotEmpty ? _periodCtrl.text : 'current period';

      final client = LLMClientFactory.fromSettings(widget.settings.settings);

      final response = await client.complete(
        systemPrompt:
            'You are an expert Technical Programme Manager. Write concise, professional status report sections. '
            'Use plain prose. No markdown headers or bullet symbols. '
            'Keep each section to 2-4 sentences unless detail is needed.',
        userMessage:
            'Draft a status report for $period using this project data:\n\n'
            '${buffer.toString()}\n\n'
            'Write four sections separated by these exact labels on their own lines:\n'
            'SUMMARY:\n'
            'ACCOMPLISHMENTS:\n'
            'NEXT STEPS:\n'
            'RISKS:\n'
            'Keep each section focused and professional.',
        maxTokens: 1500,
      );

      // Parse response into sections
      final sections = _parseSections(response);
      setState(() {
        if (sections['SUMMARY'] != null) {
          _summaryCtrl.text = sections['SUMMARY']!;
        }
        if (sections['ACCOMPLISHMENTS'] != null) {
          _accomplishmentsCtrl.text = sections['ACCOMPLISHMENTS']!;
        }
        if (sections['NEXT STEPS'] != null) {
          _nextStepsCtrl.text = sections['NEXT STEPS']!;
        }
        if (sections['RISKS'] != null) {
          _risksCtrl.text = sections['RISKS']!;
        }
        _drafting = false;
      });
    } catch (e) {
      setState(() {
        _drafting = false;
        _draftError = 'Draft failed: $e';
      });
    }
  }

  Map<String, String> _parseSections(String text) {
    final result = <String, String>{};
    final labels = ['SUMMARY', 'ACCOMPLISHMENTS', 'NEXT STEPS', 'RISKS'];
    for (int i = 0; i < labels.length; i++) {
      final label = labels[i];
      final pattern =
          RegExp('${RegExp.escape(label)}:\\s*', caseSensitive: false);
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final start = match.end;
      // Find where next section starts
      int end = text.length;
      for (int j = i + 1; j < labels.length; j++) {
        final nextPattern = RegExp('${RegExp.escape(labels[j])}:\\s*',
            caseSensitive: false);
        final nextMatch = nextPattern.firstMatch(text.substring(start));
        if (nextMatch != null) {
          end = start + nextMatch.start;
          break;
        }
      }
      result[label] = text.substring(start, end).trim();
    }
    return result;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final companion = StatusReportsCompanion(
      id: Value(widget.report?.id ?? const Uuid().v4()),
      projectId: Value(widget.projectId),
      title: Value(_titleCtrl.text.trim()),
      period: Value(
          _periodCtrl.text.trim().isEmpty ? null : _periodCtrl.text.trim()),
      overallRag: Value(_overallRag),
      summary: Value(
          _summaryCtrl.text.trim().isEmpty ? null : _summaryCtrl.text.trim()),
      accomplishments: Value(_accomplishmentsCtrl.text.trim().isEmpty
          ? null
          : _accomplishmentsCtrl.text.trim()),
      nextSteps: Value(_nextStepsCtrl.text.trim().isEmpty
          ? null
          : _nextStepsCtrl.text.trim()),
      risksHighlighted: Value(_risksCtrl.text.trim().isEmpty
          ? null
          : _risksCtrl.text.trim()),
      updatedAt: Value(DateTime.now()),
    );

    await widget.db.reportsDao.upsertReport(companion);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.report != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Report' : 'New Status Report'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Claude draft button
                Row(
                  children: [
                    Expanded(
                      child: _drafting
                          ? const Row(
                              children: [
                                SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text('Drafting with Claude…',
                                    style: TextStyle(
                                        color: KColors.textDim)),
                              ],
                            )
                          : OutlinedButton.icon(
                              onPressed: _draftWithClaude,
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('Draft with Claude'),
                            ),
                    ),
                  ],
                ),
                if (_draftError != null) ...[
                  const SizedBox(height: 6),
                  Text(_draftError!,
                      style: const TextStyle(
                          color: KColors.red, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _titleCtrl,
                        autofocus: true,
                        decoration:
                            const InputDecoration(labelText: 'Title *'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 140,
                      child: TextFormField(
                        controller: _periodCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Period', hintText: 'e.g. Week 14'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownField(
                  label: 'Overall RAG',
                  value: _overallRag,
                  items: _rags,
                  onChanged: (v) => setState(() => _overallRag = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _summaryCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Summary'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _accomplishmentsCtrl,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Accomplishments'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nextStepsCtrl,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Next Steps'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _risksCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Risks Highlighted'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
            onPressed: _save,
            child: Text(isEdit ? 'Save' : 'Create')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// RAID Export Tab
// ---------------------------------------------------------------------------

class _RaidExportTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;

  const _RaidExportTab({required this.projectId, required this.db});

  @override
  State<_RaidExportTab> createState() => _RaidExportTabState();
}

class _RaidExportTabState extends State<_RaidExportTab> {
  bool _exportingHtml = false;
  bool _exportingPdf = false;

  Future<void> _doExport({required bool asPdf}) async {
    if (asPdf) {
      setState(() => _exportingPdf = true);
    } else {
      setState(() => _exportingHtml = true);
    }
    try {
      final project =
          await widget.db.projectDao.getProjectById(widget.projectId);
      final projectName = project?.name ?? 'Project';
      final risks =
          await widget.db.raidDao.getRisksForProject(widget.projectId);
      final assumptions =
          await widget.db.raidDao.getAssumptionsForProject(widget.projectId);
      final issues =
          await widget.db.raidDao.getIssuesForProject(widget.projectId);
      final deps =
          await widget.db.raidDao.getDependenciesForProject(widget.projectId);

      final String path;
      if (asPdf) {
        path = await PdfExporter.exportRaid(
          projectName: projectName,
          risks: risks,
          assumptions: assumptions,
          issues: issues,
          dependencies: deps,
        );
      } else {
        path = await HtmlExporter.exportRaid(
          projectName: projectName,
          risks: risks,
          assumptions: assumptions,
          issues: issues,
          dependencies: deps,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('RAID export saved: $path'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: KColors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _exportingHtml = false;
          _exportingPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RAID Export',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Exports all risks, assumptions, issues, and dependencies for '
            'this project. Choose HTML for a browser-viewable file, or PDF '
            'for a print-ready document.',
            style: TextStyle(color: KColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed:
                    (_exportingHtml || _exportingPdf)
                        ? null
                        : () => _doExport(asPdf: false),
                icon: _exportingHtml
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.code, size: 16),
                label: Text(_exportingHtml ? 'Exporting…' : 'Export RAID as HTML'),
              ),
              ElevatedButton.icon(
                onPressed:
                    (_exportingHtml || _exportingPdf)
                        ? null
                        : () => _doExport(asPdf: true),
                icon: _exportingPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf, size: 16),
                label: Text(_exportingPdf ? 'Exporting…' : 'Export RAID as PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Programme Narrative Tab
// ---------------------------------------------------------------------------

class _NarrativeExportTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;

  const _NarrativeExportTab({required this.projectId, required this.db});

  @override
  State<_NarrativeExportTab> createState() => _NarrativeExportTabState();
}

class _NarrativeExportTabState extends State<_NarrativeExportTab> {
  bool _exportingHtml = false;

  Future<void> _doExport() async {
    setState(() => _exportingHtml = true);
    try {
      final project =
          await widget.db.projectDao.getProjectById(widget.projectId);
      final projectName = project?.name ?? 'Project';
      final entries =
          await widget.db.journalDao.getEntriesForProject(widget.projectId);

      if (entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No journal entries to export.'),
            ),
          );
        }
        return;
      }

      final path = await HtmlExporter.exportNarrative(
        projectName: projectName,
        entries: entries,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Narrative export saved: $path'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: KColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingHtml = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Programme Narrative',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          StreamBuilder<int>(
            stream: widget.db.journalDao
                .watchEntryCountForProject(widget.projectId),
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return Text(
                '$count journal ${count == 1 ? 'entry' : 'entries'} · '
                'Exports a chronological narrative from all journal entries.',
                style: const TextStyle(color: KColors.textDim, fontSize: 13),
              );
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _exportingHtml ? null : _doExport,
            icon: _exportingHtml
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.article_outlined, size: 16),
            label: Text(
                _exportingHtml ? 'Exporting…' : 'Export Narrative as HTML'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Handover Pack Tab
// ---------------------------------------------------------------------------

class _HandoverPackTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;

  const _HandoverPackTab({required this.projectId, required this.db});

  @override
  State<_HandoverPackTab> createState() => _HandoverPackTabState();
}

class _HandoverPackTabState extends State<_HandoverPackTab> {
  bool _exportingHandover = false;
  bool _exportingStakeholderMap = false;

  Future<void> _exportHandoverPack() async {
    setState(() => _exportingHandover = true);
    try {
      final project =
          await widget.db.projectDao.getProjectById(widget.projectId);
      final projectName = project?.name ?? 'Project';
      final risks =
          await widget.db.raidDao.getRisksForProject(widget.projectId);
      final assumptions =
          await widget.db.raidDao.getAssumptionsForProject(widget.projectId);
      final issues =
          await widget.db.raidDao.getIssuesForProject(widget.projectId);
      final deps =
          await widget.db.raidDao.getDependenciesForProject(widget.projectId);
      final entries =
          await widget.db.journalDao.getEntriesForProject(widget.projectId);
      final persons =
          await widget.db.peopleDao.getPersonsForProject(widget.projectId);
      final stakeholders = await widget.db.peopleDao
          .getStakeholdersForProject(widget.projectId);
      final reports =
          await widget.db.reportsDao.getReportsForProject(widget.projectId);
      final latestReport = reports.isNotEmpty ? reports.first : null;

      final path = await HandoverExporter.exportHandoverPack(
        projectName: projectName,
        risks: risks,
        assumptions: assumptions,
        issues: issues,
        dependencies: deps,
        entries: entries,
        persons: persons,
        stakeholders: stakeholders,
        latestReport: latestReport,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Handover pack saved: $path'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: KColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingHandover = false);
    }
  }

  Future<void> _exportStakeholderMap() async {
    setState(() => _exportingStakeholderMap = true);
    try {
      final project =
          await widget.db.projectDao.getProjectById(widget.projectId);
      final projectName = project?.name ?? 'Project';
      final persons =
          await widget.db.peopleDao.getPersonsForProject(widget.projectId);
      final stakeholders = await widget.db.peopleDao
          .getStakeholdersForProject(widget.projectId);

      if (stakeholders.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No stakeholder profiles to export.'),
            ),
          );
        }
        return;
      }

      final path = await HtmlExporter.exportStakeholderMap(
        projectName: projectName,
        persons: persons,
        stakeholders: stakeholders,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stakeholder map saved: $path'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: KColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingStakeholderMap = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Handover Pack',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Export a complete handover package as a ZIP file. '
            'Contains all project artefacts in open formats.',
            style: TextStyle(color: KColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 16),
          const _BulletList(items: [
            'RAID log (HTML + PDF)',
            'Programme narrative (HTML, if journal entries exist)',
            'Stakeholder influence/stance map (HTML, if profiles exist)',
            'Latest status report (HTML + PDF, if one exists)',
            'README.txt with contents guide',
          ]),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: (_exportingHandover || _exportingStakeholderMap)
                ? null
                : _exportHandoverPack,
            icon: _exportingHandover
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.folder_zip_outlined, size: 16),
            label: Text(
                _exportingHandover ? 'Exporting…' : 'Export Handover Pack'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 20),
          const Text(
            'Stakeholder Map',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Export a standalone influence × stance grid for all stakeholders.',
            style: TextStyle(color: KColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (_exportingHandover || _exportingStakeholderMap)
                ? null
                : _exportStakeholderMap,
            icon: _exportingStakeholderMap
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.people_outline, size: 16),
            label: Text(_exportingStakeholderMap
                ? 'Exporting…'
                : 'Export Stakeholder Map'),
          ),
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  const _BulletList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(color: KColors.amber, fontSize: 13)),
                    Expanded(
                      child: Text(item,
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 13)),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
