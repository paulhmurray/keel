import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/database.dart';
import '../raid/raid_conversion_service.dart' show RaidKind;
import '../people/person_workload.dart';
import '../raid/raid_lifecycle.dart';
import '../platform/web_download.dart';

// ─── Status PDF data models ───────────────────────────────────────────────────

class StatusWorkstreamPdf {
  final String name;
  final String rag;
  final String trend;
  const StatusWorkstreamPdf({
      required this.name, required this.rag, required this.trend});
}

class StatusMilestonePdf {
  final String icon;
  final String name;
  final String date;
  final String owner;
  const StatusMilestonePdf({
      required this.icon, required this.name,
      required this.date, required this.owner});
}

class StatusRiskPdf {
  final String ref;
  final String likelihood;
  final String impact;
  final String description;
  final String? title;
  final String? rating; // "Likely / Major (16)"
  final bool steerco;
  final String? soWhat; // latest status note or first treatment line
  final String? strategy;
  final String? owner;
  final String? dueDate;
  final String? change; // "NEW to top risks", "▲ was …"
  const StatusRiskPdf({
    required this.ref,
    required this.likelihood,
    required this.impact,
    required this.description,
    this.title,
    this.rating,
    this.steerco = false,
    this.soWhat,
    this.strategy,
    this.owner,
    this.dueDate,
    this.change,
  });
}

class StatusDecisionPdf {
  final String ref;
  final String dueDate;
  final String description;
  const StatusDecisionPdf({
      required this.ref, required this.dueDate, required this.description});
}

/// One register code the narrative mentions, spelled out.
class StatusRefPdf {
  final String ref;
  final String kind;
  final String headline;
  final String detail;
  const StatusRefPdf({
    required this.ref,
    required this.kind,
    required this.headline,
    required this.detail,
  });
}

class StatusSummaryForPdf {
  final String programmeRag;
  final String trendArrow;
  final String trendLabel;
  final String? narrative;
  final List<StatusRefPdf> referenced;
  /// "Stage 4: Procurement — Blocked · 3 of 5 stages complete", or null.
  final String? playbookStage;
  final List<StatusWorkstreamPdf> workstreams;
  final List<StatusMilestonePdf> milestones;
  final List<StatusRiskPdf> risks;
  final List<StatusDecisionPdf> decisions;
  final int overdueActions;
  final int openActions;
  final int pendingDecisions;
  final int openRisks;

  const StatusSummaryForPdf({
    required this.programmeRag,
    required this.trendArrow,
    required this.trendLabel,
    this.narrative,
    this.referenced = const [],
    this.playbookStage,
    required this.workstreams,
    required this.milestones,
    required this.risks,
    required this.decisions,
    required this.overdueActions,
    required this.openActions,
    required this.pendingDecisions,
    required this.openRisks,
  });
}

class PdfExporter {
  // ---------------------------------------------------------------------------
  // Public file-writing methods
  // ---------------------------------------------------------------------------

  static Future<String> exportReport({
    required StatusReport report,
    required String projectName,
  }) async {
    final bytes =
        await buildReportBytes(report: report, projectName: projectName);
    final filename = 'report_${_slug(report.title)}.pdf';
    return saveAndOpen(filename, bytes, mimeType: 'application/pdf');
  }

  static Future<String> exportRaid({
    required String projectName,
    required List<Risk> risks,
    required List<Assumption> assumptions,
    required List<Issue> issues,
    required List<ProgramDependency> dependencies,
    bool includeClosed = false,
  }) async {
    final bytes = await buildRaidBytes(
      projectName: projectName,
      allRisks: risks,
      allAssumptions: assumptions,
      allIssues: issues,
      allDependencies: dependencies,
      includeClosed: includeClosed,
    );
    final filename = 'raid_${_slug(projectName)}.pdf';
    return saveAndOpen(filename, bytes, mimeType: 'application/pdf');
  }

  /// Everything pinned on one person, as a brief they can be sent.
  static Future<String> exportPersonBrief({
    required PersonWorkload workload,
    required String projectName,
    String preparedBy = '',
    bool includeClosed = false,
  }) async {
    final bytes = await buildPersonBriefBytes(
      workload: workload,
      projectName: projectName,
      preparedBy: preparedBy,
      includeClosed: includeClosed,
    );
    final filename =
        'brief_${_slug(workload.person.name)}_${_slug(projectName)}.pdf';
    return saveAndOpen(filename, bytes, mimeType: 'application/pdf');
  }

  // ---------------------------------------------------------------------------
  // Public bytes-returning methods (used by HandoverExporter)
  // ---------------------------------------------------------------------------

  static Future<List<int>> buildReportBytes({
    required StatusReport report,
    required String projectName,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // Title block
          pw.Header(
            level: 0,
            child: pw.Text(
              _sanitize(report.title),
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Project: ${_sanitize(projectName)}',
              style: const pw.TextStyle(fontSize: 12)),
          if (report.period != null)
            pw.Text('Period: ${_sanitize(report.period!)}',
                style: const pw.TextStyle(fontSize: 12)),
          pw.Text(
            'Status: ${report.overallRag.toUpperCase()}',
            style: pw.TextStyle(
                fontSize: 12, color: _ragColor(report.overallRag)),
          ),
          pw.SizedBox(height: 16),
          // Sections
          if (report.summary != null && report.summary!.isNotEmpty) ...[
            _sectionHeader('Summary'),
            pw.Text(_sanitize(report.summary!)),
            pw.SizedBox(height: 12),
          ],
          if (report.accomplishments != null &&
              report.accomplishments!.isNotEmpty) ...[
            _sectionHeader('Accomplishments'),
            pw.Text(_sanitize(report.accomplishments!)),
            pw.SizedBox(height: 12),
          ],
          if (report.nextSteps != null && report.nextSteps!.isNotEmpty) ...[
            _sectionHeader('Next Steps'),
            pw.Text(_sanitize(report.nextSteps!)),
            pw.SizedBox(height: 12),
          ],
          if (report.risksHighlighted != null &&
              report.risksHighlighted!.isNotEmpty) ...[
            _sectionHeader('Risks Highlighted'),
            pw.Text(_sanitize(report.risksHighlighted!)),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static Future<List<int>> buildRaidBytes({
    required String projectName,
    required List<Risk> allRisks,
    required List<Assumption> allAssumptions,
    required List<Issue> allIssues,
    required List<ProgramDependency> allDependencies,
    bool includeClosed = false,
  }) async {
    final doc = pw.Document();
    final date = DateTime.now().toIso8601String().substring(0, 10);
    // Body shows open items; closed ones go in a trailing audit section.
    final risks = splitClosed<Risk>(allRisks,
        kind: RaidKind.risk, status: (r) => r.status).open;
    final assumptions = splitClosed<Assumption>(allAssumptions,
        kind: RaidKind.assumption, status: (a) => a.status).open;
    final issues = splitClosed<Issue>(allIssues,
        kind: RaidKind.issue, status: (i) => i.status).open;
    final dependencies = splitClosed<ProgramDependency>(allDependencies,
        kind: RaidKind.dependency, status: (d) => d.status).open;
    final closed = includeClosed
        ? closedRaidRows(
            risks: allRisks,
            assumptions: allAssumptions,
            issues: allIssues,
            dependencies: allDependencies)
        : const <ClosedItemRow>[];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'RAID Log - $projectName',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(date,
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600)),
            ],
          ),
        ),
        build: (context) => [
          // Risks
          _raidSectionHeader('Risks (${risks.length})'),
          pw.SizedBox(height: 6),
          if (risks.isEmpty)
            _emptyNote('No risks recorded.')
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'Ref',
                'Description',
                'Likelihood',
                'Impact',
                'Owner',
                'Status'
              ],
              data: risks
                  .map((r) => [
                        r.ref ?? '',
                        _sanitize(r.description),
                        _severityText(r.likelihood),
                        _severityText(r.impact),
                        _sanitize(r.owner ?? ''),
                        r.status,
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              columnWidths: {
                0: const pw.FixedColumnWidth(36),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(56),
                3: const pw.FixedColumnWidth(44),
                4: const pw.FlexColumnWidth(1.5),
                5: const pw.FixedColumnWidth(60),
              },
            ),
          pw.SizedBox(height: 16),

          // Assumptions
          _raidSectionHeader('Assumptions (${assumptions.length})'),
          pw.SizedBox(height: 6),
          if (assumptions.isEmpty)
            _emptyNote('No assumptions recorded.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Ref', 'Description', 'Owner', 'Status'],
              data: assumptions
                  .map((a) => [
                        a.ref ?? '',
                        _sanitize(a.description),
                        _sanitize(a.owner ?? ''),
                        a.status,
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              columnWidths: {
                0: const pw.FixedColumnWidth(36),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FixedColumnWidth(60),
              },
            ),
          pw.SizedBox(height: 16),

          // Issues
          _raidSectionHeader('Issues (${issues.length})'),
          pw.SizedBox(height: 6),
          if (issues.isEmpty)
            _emptyNote('No issues recorded.')
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'Ref',
                'Description',
                'Priority',
                'Owner',
                'Status'
              ],
              data: issues
                  .map((i) => [
                        i.ref ?? '',
                        _sanitize(i.description),
                        _severityText(i.priority),
                        _sanitize(i.owner ?? ''),
                        i.status,
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              columnWidths: {
                0: const pw.FixedColumnWidth(36),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(52),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FixedColumnWidth(60),
              },
            ),
          pw.SizedBox(height: 16),

          // Dependencies
          _raidSectionHeader('Dependencies (${dependencies.length})'),
          pw.SizedBox(height: 6),
          if (dependencies.isEmpty)
            _emptyNote('No dependencies recorded.')
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'Ref',
                'Description',
                'Type',
                'Owner',
                'Due',
                'Status'
              ],
              data: dependencies
                  .map((d) => [
                        d.ref ?? '',
                        _sanitize(d.description),
                        d.dependencyType,
                        _sanitize(d.owner ?? ''),
                        d.dueDate ?? '',
                        d.status,
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              columnWidths: {
                0: const pw.FixedColumnWidth(36),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(56),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FixedColumnWidth(52),
                5: const pw.FixedColumnWidth(60),
              },
            ),
          if (includeClosed) ...[
            pw.SizedBox(height: 16),
            _raidSectionHeader('Closed items (${closed.length})'),
            pw.SizedBox(height: 6),
            if (closed.isEmpty)
              _emptyNote('No closed items.')
            else
              pw.TableHelper.fromTextArray(
                headers: [
                  'Ref', 'Type', 'Description', 'Status', 'Closed on',
                  'Why / outcome',
                ],
                data: closed
                    .map((c) => [
                          c.ref,
                          c.kind,
                          _sanitize(c.description),
                          c.status,
                          c.closedOn,
                          _sanitize(c.note),
                        ])
                    .toList(),
                headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                columnWidths: {
                  0: const pw.FixedColumnWidth(36),
                  1: const pw.FixedColumnWidth(58),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FixedColumnWidth(52),
                  4: const pw.FixedColumnWidth(56),
                  5: const pw.FlexColumnWidth(2),
                },
              ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // Person brief PDF
  // ---------------------------------------------------------------------------

  /// One section per populated register: open items (overdue first) in
  /// the body, closed ones only when [includeClosed]. Styled for print:
  /// light page, grey table headers, no Keel theme colours.
  static Future<List<int>> buildPersonBriefBytes({
    required PersonWorkload workload,
    required String projectName,
    String preparedBy = '',
    bool includeClosed = false,
    DateTime? now,
  }) async {
    final doc = pw.Document();
    final today = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    final person = workload.person;
    final subtitle = [
      if ((person.role ?? '').trim().isNotEmpty) person.role!.trim(),
      if ((person.organisation ?? '').trim().isNotEmpty)
        person.organisation!.trim(),
    ].join(' - ');

    var openTotal = 0;
    var overdueTotal = 0;
    var closedTotal = 0;
    for (final kind in workload.populatedKinds) {
      final b = workload.buckets(kind, today);
      openTotal += b.open.length;
      overdueTotal += b.overdue.length;
      closedTotal += b.closed.length;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Items with ${_sanitize(person.name)} - ${_sanitize(projectName)}',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(today,
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600)),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                preparedBy.trim().isEmpty
                    ? 'Prepared from Keel'
                    : 'Prepared by ${_sanitize(preparedBy.trim())}',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (context) => [
          if (subtitle.isNotEmpty)
            pw.Text(_sanitize(subtitle),
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(
            [
              '$openTotal open',
              if (overdueTotal > 0) '$overdueTotal overdue',
              if (includeClosed) '$closedTotal completed',
            ].join(' - '),
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 14),
          if (workload.isEmpty)
            _emptyNote('Nothing in this project is assigned to '
                '${_sanitize(person.name)}.')
          else
            for (final kind in workload.populatedKinds)
              ..._personBriefSection(
                  kind, workload.buckets(kind, today), includeClosed),
        ],
      ),
    );

    return doc.save();
  }

  static List<pw.Widget> _personBriefSection(
    WorkloadKind kind,
    WorkloadBuckets buckets,
    bool includeClosed,
  ) {
    final rows = [
      ...buckets.overdue,
      ...buckets.open,
      if (includeClosed) ...buckets.closed,
    ];
    if (rows.isEmpty) return const [];
    final hasRef = rows.any((r) => (r.ref ?? '').isNotEmpty);
    final hasDue = rows.any((r) => r.dueDate != null);
    final hasQualifier = rows.any((r) => (r.qualifier ?? '').isNotEmpty);
    final showRole = kind == WorkloadKind.risk &&
        rows.any((r) => r.role == WorkloadRole.assignee);
    final countLabel = includeClosed && buckets.closed.isNotEmpty
        ? '${buckets.activeCount} open, ${buckets.closed.length} completed'
        : '${buckets.activeCount}';
    return [
      _raidSectionHeader('${kind.label} ($countLabel)'),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: [
          if (hasRef) 'Ref',
          'Item',
          if (hasQualifier) kind.qualifierLabel,
          if (showRole) 'Role',
          if (hasDue) 'Due',
          'Status',
        ],
        data: rows
            .map((r) => [
                  if (hasRef) r.ref ?? '',
                  _personBriefCell(r, buckets),
                  if (hasQualifier) _sanitize(r.qualifier ?? ''),
                  if (showRole) r.role.label,
                  if (hasDue) r.dueDate ?? '',
                  _personBriefStatus(r, buckets),
                ])
            .toList(),
        headerStyle:
            pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellAlignment: pw.Alignment.topLeft,
        columnWidths: {
          if (hasRef) 0: const pw.FixedColumnWidth(36),
          (hasRef ? 1 : 0): const pw.FlexColumnWidth(4),
          for (var i = (hasRef ? 2 : 1); i < 6; i++)
            i: const pw.FixedColumnWidth(64),
        },
      ),
      pw.SizedBox(height: 16),
    ];
  }

  static String _personBriefCell(WorkloadItem r, WorkloadBuckets b) {
    final detail = (r.detail ?? '').trim();
    if (detail.isEmpty) return _sanitize(r.title);
    return '${_sanitize(r.title)}\n${_sanitize(detail)}';
  }

  static String _personBriefStatus(WorkloadItem r, WorkloadBuckets b) {
    final s = r.status.replaceAll('_', ' ');
    if (b.overdue.contains(r)) return '$s (OVERDUE)';
    return s;
  }

  // ---------------------------------------------------------------------------
  // PDF widget helpers
  // ---------------------------------------------------------------------------

  static pw.Widget _sectionHeader(String title) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(
          border:
              pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
        ),
        child: pw.Text(
          title,
          style:
              pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _raidSectionHeader(String title) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
        child: pw.Text(
          title,
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800),
        ),
      );

  static pw.Widget _emptyNote(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Text(text,
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey500)),
      );

  /// Marks high/critical severity values in bold.
  static String _severityText(String value) {
    final lower = value.toLowerCase();
    if (lower == 'high' || lower == 'critical' || lower == 'likely' ||
        lower == 'almost certain' || lower == 'major' || lower == 'severe') {
      return value.toUpperCase();
    }
    return value;
  }

  static PdfColor _ragColor(String rag) {
    switch (rag.toLowerCase()) {
      case 'red':
        return PdfColors.red;
      case 'amber':
        return PdfColors.orange;
      default:
        return PdfColors.green;
    }
  }

  static String _sanitize(String s) => sanitizeForPdf(s);

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  // ---------------------------------------------------------------------------
  // Status dashboard PDF
  // ---------------------------------------------------------------------------

  static Future<String> exportStatus({
    required String projectName,
    required StatusSummaryForPdf summary,
  }) async {
    final bytes = await buildStatusBytes(
        projectName: projectName, summary: summary);
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final filename =
        'status_${_slug(projectName)}_$date.pdf';
    return saveAndOpen(filename, bytes, mimeType: 'application/pdf');
  }

  static Future<List<int>> buildStatusBytes({
    required String projectName,
    required StatusSummaryForPdf summary,
  }) async {
    final doc = pw.Document();
    final date = DateTime.now().toIso8601String().substring(0, 10);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.only(bottom: 6),
          decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _sanitize('STATUS — $projectName'),
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(date,
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600)),
            ],
          ),
        ),
        build: (ctx) => [
          // Programme RAG
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _ragColor(summary.programmeRag)),
                borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Row(children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: pw.BoxDecoration(
                    color: _ragBgColor(summary.programmeRag),
                    borderRadius: pw.BorderRadius.circular(3)),
                child: pw.Text(
                  summary.programmeRag.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: _ragColor(summary.programmeRag)),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(_sanitize('${summary.trendArrow}  ${summary.trendLabel}'),
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey600)),
            ]),
          ),
          pw.SizedBox(height: 16),

          // Current playbook stage
          if (summary.playbookStage != null) ...[
            _sectionHeader('Current Playbook Stage'),
            pw.SizedBox(height: 6),
            pw.Text(_sanitize(summary.playbookStage!),
                style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 16),
          ],

          // Narrative
          if (summary.narrative != null &&
              summary.narrative!.isNotEmpty) ...[
            _sectionHeader('Status Narrative'),
            pw.SizedBox(height: 6),
            pw.Text(_sanitize(summary.narrative!),
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 3)),
            pw.SizedBox(height: 16),
            if (summary.referenced.isNotEmpty) ...[
              _sectionHeader('Referenced Items'),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(4),
                  2: const pw.FlexColumnWidth(3),
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      _tableHeader('REF'),
                      _tableHeader('WHAT IT IS'),
                      _tableHeader('DETAIL'),
                    ],
                  ),
                  for (final r in summary.referenced)
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(_sanitize(r.ref),
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold)),
                              pw.Text(_sanitize(r.kind),
                                  style: const pw.TextStyle(
                                      fontSize: 7, color: PdfColors.grey600)),
                            ]),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(_sanitize(r.headline),
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(_sanitize(r.detail),
                            style: const pw.TextStyle(
                                fontSize: 8, color: PdfColors.grey700)),
                      ),
                    ]),
                ],
              ),
              pw.SizedBox(height: 16),
            ],
          ],

          // Workstreams
          _sectionHeader('Workstreams'),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _tableHeader('WORK PACKAGE'),
                  _tableHeader('RAG'),
                  _tableHeader('TREND'),
                ],
              ),
              for (final ws in summary.workstreams)
                pw.TableRow(children: [
                  _tableCell(ws.name),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(_sanitize(ws.rag.toUpperCase()),
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: _ragColor(ws.rag))),
                  ),
                  _tableCell(ws.trend),
                ]),
            ],
          ),
          pw.SizedBox(height: 16),

          // Upcoming milestones
          if (summary.milestones.isNotEmpty) ...[
            _sectionHeader('Upcoming Milestones'),
            pw.SizedBox(height: 6),
            for (final m in summary.milestones)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(
                    _sanitize(
                        '${m.icon}  ${m.name}   ${m.date}   ${m.owner}'),
                    style: const pw.TextStyle(fontSize: 10)),
              ),
            pw.SizedBox(height: 16),
          ],

          // Top risks
          if (summary.risks.isNotEmpty) ...[
            _sectionHeader('Top Risks'),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FixedColumnWidth(44),
                1: const pw.FixedColumnWidth(92),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(1.6),
                4: const pw.FixedColumnWidth(84),
              },
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _tableHeader('REF'),
                    _tableHeader('RATING'),
                    _tableHeader('RISK'),
                    _tableHeader('WHAT WE ARE DOING'),
                    _tableHeader('OWNER / DUE'),
                  ],
                ),
                for (final r in summary.risks)
                  pw.TableRow(children: [
                    _tableCell(
                        '${r.ref}${r.steerco ? '\nESCALATED' : ''}'),
                    _tableCell(
                        '${r.rating ?? '${r.likelihood} / ${r.impact}'}'
                        '${r.change != null ? '\n${r.change}' : ''}'),
                    _tableCell(r.title != null && r.title!.isNotEmpty
                        ? '${r.title}\n${r.description}'
                        : r.description),
                    _tableCell(
                        '${r.soWhat ?? '—'}'
                        '${r.strategy != null ? '\n${r.strategy}' : ''}'),
                    _tableCell(
                        '${r.owner ?? '—'}'
                        '${r.dueDate != null ? '\ndue ${r.dueDate}' : ''}'),
                  ]),
              ],
            ),
            pw.SizedBox(height: 16),
          ],

          // Pending decisions
          if (summary.decisions.isNotEmpty) ...[
            _sectionHeader('Pending Decisions'),
            pw.SizedBox(height: 6),
            for (final d in summary.decisions)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(
                    _sanitize(
                        '${d.ref}   Due: ${d.dueDate}   ${d.description}'),
                    style: const pw.TextStyle(fontSize: 10)),
              ),
            pw.SizedBox(height: 16),
          ],

          // Counts
          _sectionHeader('Summary Counts'),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            _countCell('${summary.overdueActions}', 'Overdue actions'),
            pw.SizedBox(width: 8),
            _countCell('${summary.openActions}',    'Open actions'),
            pw.SizedBox(width: 8),
            _countCell('${summary.pendingDecisions}','Pending decisions'),
            pw.SizedBox(width: 8),
            _countCell('${summary.openRisks}',      'Open risks'),
          ]),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _tableHeader(String t) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700)),
      );

  static pw.Widget _tableCell(String t) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(_sanitize(t),
            style: const pw.TextStyle(fontSize: 9)),
      );

  static pw.Widget _countCell(String num, String label) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(num,
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold,
                      color: PdfColors.orange)),
              pw.Text(_sanitize(label),
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ),
      );

  static PdfColor _ragBgColor(String rag) => switch (rag.toLowerCase()) {
        'red'   => const PdfColor.fromInt(0xff3f1515),
        'amber' => const PdfColor.fromInt(0xff3d2b05),
        'green' => const PdfColor.fromInt(0xff0d3325),
        _       => PdfColors.grey100,
      };
}

/// Replaces characters the PDF's built-in Helvetica cannot draw. Anything
/// outside Latin-1 renders as a blank box, so the trend arrows, the
/// ▲ ESCALATED mark and the milestone glyphs used on screen are turned
/// into words or dropped (their meaning is already carried by the label
/// beside them). Typographic punctuation maps to ASCII. Public so the
/// mapping is testable.
String sanitizeForPdf(String s) {
  var out = s
      .replaceAll('\u2014', '--') // em dash
      .replaceAll('\u2013', '-') // en dash
      .replaceAll('\u2018', "'") // left single quote
      .replaceAll('\u2019', "'") // right single quote / apostrophe
      .replaceAll('\u201C', '"') // left double quote
      .replaceAll('\u201D', '"') // right double quote
      .replaceAll('\u2026', '...') // ellipsis
      .replaceAll('\u2022', '-') // bullet
      .replaceAll('\u00A0', ' ') // non-breaking space
      // Trend arrows: the label ("Steady", "Improved") stands alone.
      .replaceAll('\u2192', '') // →
      .replaceAll('\u2191', '') // ↑
      .replaceAll('\u2193', '') // ↓
      .replaceAll('\u2194', '-') // ↔ (ongoing)
      // Register marks: "▲ ESCALATED" / "▲ was possible/major" read fine bare.
      .replaceAll('\u25B2', '') // ▲
      .replaceAll('\u25BC', '') // ▼
      // Plan glyphs.
      .replaceAll('\u25C6', '') // ◆ milestone
      .replaceAll('\u25C8', '[gate]') // ◈
      .replaceAll('\u26A0', '[deadline]') // ⚠
      .replaceAll('\u25D4', '[due]') // ◔
      .replaceAll('\u25F7', '[due]') // ◷
      .replaceAll('\u2713', 'yes') // ✓
      .replaceAll('\u2717', 'no') // ✗
      .replaceAll('\u00B7', '-') // · (Helvetica has it, but keep plain)
      .replaceAll('\u20AC', 'EUR '); // € is outside Latin-1
  // Anything else outside Latin-1 still can't be drawn — drop it rather
  // than print a box.
  out = out.replaceAll(RegExp(r'[^\x00-\xFF]'), '');
  return out.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}
